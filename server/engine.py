"""
BikeReclaim 최적화 엔진 v2 — 이강혁 프레임워크 이식판.
원본: main.py (2026-07-21 공유). 서버용 변경점:
  - matplotlib/numpy/샘플데이터/시각화/print 제거
  - build_pickup_options의 전역 locations 참조 버그 → 파라미터로 수정
파라미터 튜닝은 server/.env 의 OPT_* 값으로 한다 (optimizer.py 참고).
"""
from math import atan2, ceil, cos, radians, sin, sqrt
from datetime import datetime


from ortools.constraint_solver import pywrapcp, routing_enums_pb2


# ============================================================
# 1. 설정
# ============================================================

# exact max-age 정렬 대신 신고 경과일을 urgency tier로 구분한다.
# min_age가 큰 tier부터 검사되므로 내림차순으로 작성한다.
URGENCY_TIERS = [
    {
        "label": "Critical",
        "min_age": 90,
        "level": 4,
        "bonus": 300,
    },
    {
        "label": "High",
        "min_age": 60,
        "level": 3,
        "bonus": 150,
    },
    {
        "label": "Medium",
        "min_age": 30,
        "level": 2,
        "bonus": 60,
    },
    {
        "label": "Normal",
        "min_age": 0,
        "level": 1,
        "bonus": 0,
    },
]


# ============================================================
# 2. 샘플 데이터
# ============================================================

def make_bike(
    name,
    lat,
    lon,
    report_date,
    *,
    active=True,
    collectible=True,
    confidence=1.0,
    hazard_score=0,
    pickup_minutes=4,
):
    """
    샘플 자전거 레코드를 생성한다.

    duplicate 여부는 자동 판별하지 않는다. 각 신고 레코드를 독립된
    자전거 1대로 취급한다.

    active/collectible 값은 현장 시스템에서 명시적으로 제공되는 경우에만
    사용한다. 코드가 신고의 진위 여부를 추론하지는 않는다.
    """

    return {
        "name": name,
        "lat": lat,
        "lon": lon,
        "report_date": report_date,
        "active": active,
        "collectible": collectible,
        "confidence": confidence,
        "hazard_score": hazard_score,
        "pickup_minutes": pickup_minutes,
    }



# ============================================================
# 3. 기본 계산 함수
# ============================================================

def haversine_distance_m(lat1, lon1, lat2, lon2):
    """
    두 위경도 좌표 사이의 직선거리(m)를 계산한다.

    hotspot 생성에는 직선거리를 사용한다. 실제 차량 경로에서는
    Kakao Mobility 등의 도로 거리/시간 matrix로 교체하는 것이 좋다.
    """

    earth_radius_m = 6_371_000

    phi1 = radians(lat1)
    phi2 = radians(lat2)
    delta_phi = radians(lat2 - lat1)
    delta_lambda = radians(lon2 - lon1)

    a = (
        sin(delta_phi / 2) ** 2
        + cos(phi1) * cos(phi2) * sin(delta_lambda / 2) ** 2
    )
    c = 2 * atan2(sqrt(a), sqrt(1 - a))

    return int(round(earth_radius_m * c))


def node_distance_m(locations, node_a, node_b):
    return haversine_distance_m(
        locations[node_a]["lat"],
        locations[node_a]["lon"],
        locations[node_b]["lat"],
        locations[node_b]["lon"],
    )


def point_distance_m(point_a, point_b):
    return haversine_distance_m(
        point_a["lat"],
        point_a["lon"],
        point_b["lat"],
        point_b["lon"],
    )


def get_days_old(report_date, current_date):
    report_dt = datetime.strptime(report_date, "%Y-%m-%d")
    return max((current_date - report_dt).days, 0)


def get_urgency(days_old):
    for tier in URGENCY_TIERS:
        if days_old >= tier["min_age"]:
            return tier

    # URGENCY_TIERS에 Normal tier가 있으므로 실제로는 도달하지 않는다.
    return URGENCY_TIERS[-1]


def calculate_bike_priority(bike, days_old):
    """
    개별 자전거의 수거 편익(priority points)을 계산한다.

    - 신고 경과일이 길수록 priority 증가
    - SLA에 가까운 순서가 아니라 tier를 넘을 때 추가 bonus 부여
    - hazard_score가 제공되면 위험도 반영
    - confidence가 제공되면 현장 존재 가능성 반영

    confidence와 hazard_score가 데이터에 없다면 각각 1.0과 0을 사용한다.
    """

    urgency = get_urgency(days_old)
    confidence = min(max(float(bike.get("confidence", 1.0)), 0.0), 1.0)
    hazard_score = max(float(bike.get("hazard_score", 0)), 0.0)

    raw_priority = (
        10
        + days_old
        + urgency["bonus"]
        + 20 * hazard_score
    )

    return max(int(round(raw_priority * confidence)), 1)


# ============================================================
# 4. 반경 30m의 compact hotspot 생성
# ============================================================

def get_eligible_bike_nodes(locations, start_index, end_index):
    """
    시스템에 명시적으로 active=False 또는 collectible=False로 저장된
    신고만 제외한다.

    duplicate 탐지나 좌표/사진 기반의 신고 진위 추론은 수행하지 않는다.
    """

    return [
        node
        for node, bike in enumerate(locations)
        if node not in (start_index, end_index)
        and bike.get("report_date") is not None
        and bike.get("active", True)
        and bike.get("collectible", True)
    ]


def create_compact_clusters(
    locations,
    start_index,
    end_index,
    cluster_radius_m=30,
):
    """
    모든 cluster 구성원이 하나의 anchor bike로부터 30m 이내에 있도록
    hotspot을 생성한다.

    기존 connected-component 방식은 A-B와 B-C가 각각 30m 이내이면
    A-C가 30m보다 멀어도 같은 cluster가 되는 chaining 문제가 있었다.
    여기서는 아직 배정되지 않은 자전거를 가장 많이 포함하는 30m 원을
    반복 선택하므로 각 cluster의 반경을 명시적으로 제한한다.
    """

    unassigned = set(
        get_eligible_bike_nodes(
            locations,
            start_index,
            end_index,
        )
    )
    clusters = []

    while unassigned:
        best_anchor = None
        best_members = None

        for candidate in sorted(unassigned):
            members = [
                other
                for other in sorted(unassigned)
                if node_distance_m(locations, candidate, other)
                <= cluster_radius_m
            ]

            if (
                best_members is None
                or len(members) > len(best_members)
                or (
                    len(members) == len(best_members)
                    and candidate < best_anchor
                )
            ):
                best_anchor = candidate
                best_members = members

        clusters.append({
            "anchor_node": best_anchor,
            "nodes": best_members,
        })
        unassigned.difference_update(best_members)

    return clusters


# ============================================================
# 5. Cluster 통계와 priority 계산
# ============================================================

def build_cluster_info(
    locations,
    clusters,
    start_index,
    end_index,
    current_date,
    completion_bonus_ratio=0.15,
    cluster_stop_minutes=3,
):
    cluster_info = []

    direct_start_to_storage = node_distance_m(
        locations,
        start_index,
        end_index,
    )

    for cluster_id, cluster in enumerate(clusters, start=1):
        nodes = cluster["nodes"]
        anchor_node = cluster["anchor_node"]
        bike_data = []

        for node in nodes:
            bike = locations[node]
            days_old = get_days_old(
                bike["report_date"],
                current_date,
            )
            urgency = get_urgency(days_old)

            bike_data.append({
                "node": node,
                "name": bike["name"],
                "days_old": days_old,
                "urgency_label": urgency["label"],
                "urgency_level": urgency["level"],
                "priority_points": calculate_bike_priority(
                    bike,
                    days_old,
                ),
                "pickup_minutes": int(
                    round(bike.get("pickup_minutes", 4))
                ),
            })

        # 부분 수거 시 이 순서의 앞에서부터 선택한다.
        bike_data.sort(
            key=lambda item: (
                item["priority_points"],
                item["days_old"],
            ),
            reverse=True,
        )

        ages = [bike["days_old"] for bike in bike_data]
        oldest_age = max(ages)
        oldest_urgency = get_urgency(oldest_age)
        top_k = min(3, len(ages))
        top3_mean_age = float(sum(sorted(ages, reverse=True)[:top_k]) / max(1, min(top_k, len(ages))))

        full_priority = sum(
            bike["priority_points"]
            for bike in bike_data
        )
        completion_bonus = max(
            int(round(full_priority * completion_bonus_ratio)),
            1,
        )

        overdue_count = sum(
            bike["days_old"] >= 60
            for bike in bike_data
        )
        critical_count = sum(
            bike["days_old"] >= 90
            for bike in bike_data
        )

        start_to_cluster = node_distance_m(
            locations,
            start_index,
            anchor_node,
        )
        cluster_to_storage = node_distance_m(
            locations,
            anchor_node,
            end_index,
        )
        standalone_detour_m = max(
            start_to_cluster
            + cluster_to_storage
            - direct_start_to_storage,
            0,
        )

        max_radius_m = max(
            node_distance_m(locations, anchor_node, node)
            for node in nodes
        )

        cluster_info.append({
            "cluster_id": cluster_id,
            "anchor_node": anchor_node,
            "nodes": nodes,
            "bike_data": bike_data,
            "size": len(nodes),
            "max_age": oldest_age,
            "avg_age": float(sum(ages) / max(1, len(ages))),
            "top3_mean_age": top3_mean_age,
            "overdue_count": overdue_count,
            "critical_count": critical_count,
            "urgency_label": oldest_urgency["label"],
            "urgency_level": oldest_urgency["level"],
            "full_priority": full_priority,
            "completion_bonus": completion_bonus,
            "cluster_priority": full_priority + completion_bonus,
            "standalone_detour_m": standalone_detour_m,
            "max_radius_m": max_radius_m,
            "full_service_minutes": (
                cluster_stop_minutes
                + sum(
                    bike["pickup_minutes"]
                    for bike in bike_data
                )
            ),
        })

    # 이 ranking은 설명용이다. 실제 선택은 route cost와 capacity까지
    # 포함하여 OR-Tools가 joint optimization으로 결정한다.
    cluster_info.sort(
        key=lambda cluster: (
            cluster["urgency_level"],
            cluster["cluster_priority"],
            cluster["max_age"],
            cluster["size"],
        ),
        reverse=True,
    )

    for rank, cluster in enumerate(cluster_info, start=1):
        cluster["priority_rank"] = rank

    return cluster_info


# ============================================================
# 6. Cluster별 수거량 대안 생성
# ============================================================

def build_pickup_options(
    locations,
    cluster_info,
    vehicle_capacity,
    cluster_stop_minutes=3,
    required_nodes=None,
):
    """
    각 cluster에 대해 다음과 같은 대안을 생성한다.

        q=0: cluster를 방문하지 않음
        q=1: 가장 중요한 자전거 1대 수거
        ...
        q=n: cluster 전체 수거 + completion bonus

    q=0은 별도의 node 없이 해당 cluster의 모든 대안을 drop하는 것으로
    표현한다.
    """

    options = []

    for cluster in cluster_info:
        max_pickup = min(cluster["size"], vehicle_capacity)

        for quantity in range(1, max_pickup + 1):
            selected_bikes = cluster["bike_data"][:quantity]
            selected_nodes = [
                bike["node"]
                for bike in selected_bikes
            ]
            fully_collected = quantity == cluster["size"]

            reward_points = sum(
                bike["priority_points"]
                for bike in selected_bikes
            )

            if fully_collected:
                reward_points += cluster["completion_bonus"]

            # 관리자가 명시적으로 지정한 노드(required)를 모두 포함하는
            # 대안인지 표시. 최적화 단계에서 이 대안을 필수 방문으로 다룬다.
            cluster_required = [
                node for node in cluster["nodes"]
                if required_nodes and node in required_nodes
            ]
            covers_required = bool(cluster_required) and all(
                node in selected_nodes for node in cluster_required
            )

            options.append({
                "cluster_required_nodes": cluster_required,
                "covers_required": covers_required,
                "option_id": len(options) + 1,
                "cluster_id": cluster["cluster_id"],
                "priority_rank": cluster["priority_rank"],
                "anchor_node": cluster["anchor_node"],
                "lat": locations[cluster["anchor_node"]]["lat"],
                "lon": locations[cluster["anchor_node"]]["lon"],
                "quantity": quantity,
                "demand": quantity,
                "selected_nodes": selected_nodes,
                "selected_bikes": selected_bikes,
                "fully_collected": fully_collected,
                "reward_points": reward_points,
                "service_minutes": (
                    cluster_stop_minutes
                    + sum(
                        bike["pickup_minutes"]
                        for bike in selected_bikes
                    )
                ),
            })

    return options


# ============================================================
# 7. OR-Tools joint selection + route optimization
# ============================================================

def build_problem_points(
    locations,
    start_index,
    end_index,
    pickup_options,
):
    points = [{
        "kind": "start",
        "name": locations[start_index]["name"],
        "lat": locations[start_index]["lat"],
        "lon": locations[start_index]["lon"],
        "demand": 0,
        "service_minutes": 0,
    }]

    for option in pickup_options:
        points.append({
            "kind": "pickup_option",
            "name": (
                f'Cluster {option["cluster_id"]}'
                f' ({option["quantity"]} bikes)'
            ),
            "lat": option["lat"],
            "lon": option["lon"],
            "demand": option["demand"],
            "service_minutes": option["service_minutes"],
            "option": option,
        })

    points.append({
        "kind": "storage",
        "name": locations[end_index]["name"],
        "lat": locations[end_index]["lat"],
        "lon": locations[end_index]["lon"],
        "demand": 0,
        "service_minutes": 0,
    })

    return points


def build_point_distance_matrix(points):
    # OR-Tools transit callback은 int64를 요구하므로 반드시 정수화한다.
    return [
        [
            0 if i == j else int(round(point_distance_m(points[i], points[j])))
            for j in range(len(points))
        ]
        for i in range(len(points))
    ]


def optimize_collection_and_route(
    locations,
    cluster_info,
    pickup_options,
    start_index,
    end_index,
    *,
    vehicle_capacity,
    max_route_minutes=120,
    average_speed_kmh=25,
    priority_value_m_per_point=75,
    service_cost_m_per_minute=100,
    search_seconds=10,
    has_required=False,
):
    """
    OR-Tools가 다음을 동시에 결정한다.

    1. 방문할 cluster
    2. 각 cluster에서 수거할 자전거 수
    3. Start -> selected clusters -> Storage 방문 순서

    Objective:
        travel distance
        + service-time equivalent cost
        + dropped-priority penalties

    priority_value_m_per_point가 클수록 신고 priority를 이동거리보다 더
    중요하게 취급한다. 운영 정책에 맞게 calibration해야 하는 값이다.
    """

    points = build_problem_points(
        locations,
        start_index,
        end_index,
        pickup_options,
    )
    distance_matrix = build_point_distance_matrix(points)

    num_nodes = len(points)
    start_local_node = 0
    end_local_node = num_nodes - 1

    manager = pywrapcp.RoutingIndexManager(
        num_nodes,
        1,
        [start_local_node],
        [end_local_node],
    )
    routing = pywrapcp.RoutingModel(manager)

    # --------------------------------------------------------
    # Generalized route cost = distance + service-time cost
    # --------------------------------------------------------

    def cost_callback(from_index, to_index):
        from_node = manager.IndexToNode(from_index)
        to_node = manager.IndexToNode(to_index)

        return int(round(
            distance_matrix[from_node][to_node]
            + points[from_node]["service_minutes"]
            * service_cost_m_per_minute
        ))

    cost_callback_index = routing.RegisterTransitCallback(cost_callback)
    routing.SetArcCostEvaluatorOfAllVehicles(cost_callback_index)

    # --------------------------------------------------------
    # 실제 route time constraint
    # --------------------------------------------------------

    meters_per_minute = average_speed_kmh * 1000 / 60

    def time_callback(from_index, to_index):
        from_node = manager.IndexToNode(from_index)
        to_node = manager.IndexToNode(to_index)

        travel_minutes = ceil(
            distance_matrix[from_node][to_node]
            / meters_per_minute
        )

        return int(
            travel_minutes
            + points[from_node]["service_minutes"]
        )

    time_callback_index = routing.RegisterTransitCallback(time_callback)
    routing.AddDimension(
        time_callback_index,
        0,
        max_route_minutes,
        True,
        "Time",
    )
    time_dimension = routing.GetDimensionOrDie("Time")

    # --------------------------------------------------------
    # 차량 적재량 constraint
    # --------------------------------------------------------

    def demand_callback(from_index):
        from_node = manager.IndexToNode(from_index)
        return points[from_node]["demand"]

    demand_callback_index = routing.RegisterUnaryTransitCallback(
        demand_callback
    )
    routing.AddDimensionWithVehicleCapacity(
        demand_callback_index,
        0,
        [vehicle_capacity],
        True,
        "Capacity",
    )

    # --------------------------------------------------------
    # 수거하지 않은 priority는 penalty로 처리
    #
    # 모든 option을 개별 optional node로 만든 뒤, 같은 cluster에서는
    # 최대 하나의 quantity option만 활성화할 수 있도록 제한한다.
    # --------------------------------------------------------

    option_indices_by_cluster = {}
    # 필수 방문(required) 노드를 모두 담는 대안들
    required_option_indices_by_cluster = {}

    for local_node in range(1, end_local_node):
        routing_index = manager.NodeToIndex(local_node)
        option = points[local_node]["option"]
        penalty_m = max(
            int(round(
                option["reward_points"]
                * priority_value_m_per_point
            )),
            1,
        )

        routing.AddDisjunction(
            [routing_index],
            penalty_m,
        )

        option_indices_by_cluster.setdefault(
            option["cluster_id"],
            [],
        ).append(routing_index)

        if option.get("covers_required"):
            required_option_indices_by_cluster.setdefault(
                option["cluster_id"],
                [],
            ).append(routing_index)

    solver = routing.solver()

    for routing_indices in option_indices_by_cluster.values():
        solver.Add(
            solver.Sum([
                routing.ActiveVar(index)
                for index in routing_indices
            ])
            <= 1
        )

    # A안: 관리자가 지정한 노드가 있는 cluster는 반드시 방문하고,
    # 그 노드들을 모두 포함하는 수거량 대안 중 하나를 선택하게 한다.
    if has_required:
        for routing_indices in required_option_indices_by_cluster.values():
            solver.Add(
                solver.Sum([
                    routing.ActiveVar(index)
                    for index in routing_indices
                ])
                == 1
            )

    # --------------------------------------------------------
    # Search
    # --------------------------------------------------------

    search_parameters = pywrapcp.DefaultRoutingSearchParameters()
    search_parameters.first_solution_strategy = (
        routing_enums_pb2
        .FirstSolutionStrategy
        .PARALLEL_CHEAPEST_INSERTION
    )
    search_parameters.local_search_metaheuristic = (
        routing_enums_pb2
        .LocalSearchMetaheuristic
        .GUIDED_LOCAL_SEARCH
    )
    search_parameters.time_limit.seconds = search_seconds

    solution = routing.SolveWithParameters(search_parameters)

    if not solution:
        return None

    # --------------------------------------------------------
    # 결과 추출
    # --------------------------------------------------------

    route_local_nodes = []
    index = routing.Start(0)

    while not routing.IsEnd(index):
        route_local_nodes.append(manager.IndexToNode(index))
        index = solution.Value(routing.NextVar(index))

    route_local_nodes.append(manager.IndexToNode(index))

    total_distance_m = sum(
        distance_matrix[from_node][to_node]
        for from_node, to_node in zip(
            route_local_nodes[:-1],
            route_local_nodes[1:],
        )
    )

    selected_options = [
        points[local_node]["option"]
        for local_node in route_local_nodes
        if points[local_node]["kind"] == "pickup_option"
    ]

    cluster_by_id = {
        cluster["cluster_id"]: cluster
        for cluster in cluster_info
    }

    selected_clusters = []
    selected_nodes = []

    for visit_order, option in enumerate(selected_options, start=1):
        cluster = cluster_by_id[option["cluster_id"]]
        selected_clusters.append({
            **cluster,
            "visit_order": visit_order,
            "selected_nodes": option["selected_nodes"],
            "selected_bikes": option["selected_bikes"],
            "selected_count": option["quantity"],
            "fully_collected": option["fully_collected"],
            "priority_gained": option["reward_points"],
            "service_minutes": option["service_minutes"],
        })
        selected_nodes.extend(option["selected_nodes"])

    used_capacity = sum(
        option["quantity"]
        for option in selected_options
    )

    return {
        "route_points": [
            points[local_node]
            for local_node in route_local_nodes
        ],
        "selected_clusters": selected_clusters,
        "selected_nodes": selected_nodes,
        "used_capacity": used_capacity,
        "remaining_capacity": vehicle_capacity - used_capacity,
        "distance_m": total_distance_m,
        "route_minutes": solution.Value(
            time_dimension.CumulVar(routing.End(0))
        ),
        "priority_gained": sum(
            option["reward_points"]
            for option in selected_options
        ),
        "objective_value": solution.ObjectiveValue(),
    }


# ============================================================
# 8. 전체 문제 실행
# ============================================================

def solve_bike_loop(
    locations,
    start_index,
    end_index,
    *,
    vehicle_capacity=8,
    cluster_radius_m=30,
    current_date=None,
    completion_bonus_ratio=0.15,
    cluster_stop_minutes=3,
    max_route_minutes=120,
    average_speed_kmh=25,
    priority_value_m_per_point=75,
    service_cost_m_per_minute=100,
    search_seconds=10,
    required_nodes=None,
):
    """required_nodes: 관리자가 직접 선택해 반드시 수거해야 하는 노드 집합.
    지정되면 비용·편익 판단과 무관하게 방문한다(용량·시간 제약은 유지)."""
    if current_date is None:
        current_date = datetime.now()

    clusters = create_compact_clusters(
        locations,
        start_index,
        end_index,
        cluster_radius_m,
    )

    cluster_info = build_cluster_info(
        locations,
        clusters,
        start_index,
        end_index,
        current_date,
        completion_bonus_ratio,
        cluster_stop_minutes,
    )

    pickup_options = build_pickup_options(
        locations,
        cluster_info,
        vehicle_capacity,
        cluster_stop_minutes,
        required_nodes,
    )

    route_result = optimize_collection_and_route(
        locations,
        cluster_info,
        pickup_options,
        start_index,
        end_index,
        vehicle_capacity=vehicle_capacity,
        max_route_minutes=max_route_minutes,
        average_speed_kmh=average_speed_kmh,
        priority_value_m_per_point=priority_value_m_per_point,
        service_cost_m_per_minute=service_cost_m_per_minute,
        search_seconds=search_seconds,
        has_required=bool(required_nodes),
    )

    if route_result is None:
        raise RuntimeError(
            "주어진 route-time/capacity 조건에서 feasible route를 "
            "찾지 못했습니다."
        )

    return {
        "cluster_info": cluster_info,
        "pickup_options": pickup_options,
        **route_result,
    }


# ============================================================
# 9. 결과 출력
# ============================================================
