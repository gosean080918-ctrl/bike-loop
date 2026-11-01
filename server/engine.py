"""
BIKE LOOP optimization engine v2, ported from an external framework.
Changes made for server use:
  - removed matplotlib / numpy / sample data / plotting / print statements
  - fixed a bug where build_pickup_options referenced a global `locations`
    (now passed as a parameter)
Tune behaviour through the OPT_* values in server/.env (see optimizer.py).
"""
from math import atan2, ceil, cos, radians, sin, sqrt
from datetime import datetime


from ortools.constraint_solver import pywrapcp, routing_enums_pb2


# ============================================================
# 1. Configuration
# ============================================================

# Rather than sorting by exact age, reports are bucketed into urgency tiers.
# Tiers are checked from the largest min_age down, so keep this list descending.
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
# 2. Sample data
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
    Build sample bicycle records.

    Duplicates are not inferred. Every report record is treated as one
    independent bicycle.

    The active / collectible flags are honoured only when the operational
    system supplies them explicitly. This code never guesses whether a report
    is genuine.
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
# 3. Basic computations
# ============================================================

def haversine_distance_m(lat1, lon1, lat2, lon2):
    """
    Straight-line distance in metres between two lat/lng coordinates.

    Hotspot construction uses straight-line distance. For actual vehicle
    routing this should be replaced with a road distance/time matrix such as
    the one from Kakao Mobility.
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

    # Unreachable in practice because URGENCY_TIERS ends with a Normal tier.
    return URGENCY_TIERS[-1]


def calculate_bike_priority(bike, days_old):
    """
    Compute the collection benefit (priority points) of one bicycle.

    - priority grows with the number of days since the report
    - a bonus is granted on crossing a tier boundary, not by proximity to an SLA
    - hazard_score, when supplied, folds in how dangerous the bike is
    - confidence, when supplied, folds in how likely it is still on site

    Missing confidence and hazard_score default to 1.0 and 0 respectively.
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
# 4. Build compact hotspots with a 30 m radius
# ============================================================

def get_eligible_bike_nodes(locations, start_index, end_index):
    """
    Excludes only the reports explicitly stored as active=False or
    collectible=False.

    No duplicate detection, and no inference about a report's authenticity from
    coordinates or photos.
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
    Build hotspots such that every cluster member lies within 30 m of a single
    anchor bike.

    A naive connected-component approach chains: if A-B and B-C are each within
    30 m, A and C join the same cluster even when they are much further apart.
    Instead this repeatedly picks the 30 m circle covering the most unassigned
    bicycles, which bounds each cluster's radius explicitly.
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
# 5. Cluster statistics and priority
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

        # Partial pickups take bicycles from the front of this ordering.
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

    # This ranking is explanatory only. The actual selection is made by
    # OR-Tools, jointly with route cost and capacity.
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
# 6. Generate pickup-quantity options per cluster
# ============================================================

def build_pickup_options(
    locations,
    cluster_info,
    vehicle_capacity,
    cluster_stop_minutes=3,
    required_nodes=None,
):
    """
    For each cluster, generate these options:

        q=0: do not visit the cluster
        q=1: collect the single most important bicycle
        ...
        q=n: collect the whole cluster, plus a completion bonus

    q=0 needs no node of its own: it is expressed by dropping every option
    belonging to that cluster.
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

            # Mark options that cover every administrator-selected (required)
            # node; the solver treats such an option as a mandatory visit.
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
    # OR-Tools transit callbacks require int64, so every value must be an integer.
    # (Returning floats here fails silently and produces wrong routes.)
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
    OR-Tools decides all of the following at once:

    1. which clusters to visit
    2. how many bicycles to collect at each cluster
    3. the visiting order: start -> selected clusters -> storage

    Objective:
        travel distance
        + service-time equivalent cost
        + dropped-priority penalties

    A larger priority_value_m_per_point weights report priority more heavily
    against travel distance. Calibrate it to the operator's policy.
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
    # Route time constraint
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
    # Vehicle capacity constraint
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
    # Uncollected priority is charged as a penalty.
    #
    # Every option becomes its own optional node; a constraint then allows
    # at most one quantity option per cluster to be active.
    # --------------------------------------------------------

    option_indices_by_cluster = {}
    # Options that cover all required nodes
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

    # Mandatory-visit rule: a cluster containing administrator-selected nodes
    # must be visited, choosing one of the options that covers all of them.
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
    # Extract the solution
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
# 8. Solve the full problem
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
    """required_nodes: nodes the administrator selected and that must be collected.
    When present they are visited regardless of the cost/benefit trade-off,
    while capacity and time constraints still apply."""
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
            "No feasible route under the given route-time and capacity "
            "constraints."
        )

    return {
        "cluster_info": cluster_info,
        "pickup_options": pickup_options,
        **route_result,
    }


# ============================================================
# 9. Report the result
# ============================================================
