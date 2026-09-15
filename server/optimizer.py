"""
/optimize 래퍼 v2 — 이강혁 프레임워크(engine.py) 기반.

- 튜닝 파라미터는 환경변수(OPT_*)가 기본값, 요청 본문 값이 있으면 우선.
- 이동시간/거리: 기본 하버사인. KAKAO_MOBILITY_KEY가 설정되면
  최적 순서 확정 후 카카오모빌리티 다중경유지 API로 실제 도로
  경로(폴리라인)·거리·시간을 받아 응답에 포함한다.
"""
import math
import os
from datetime import datetime, timezone

import httpx

import engine
from models import OptimizeRequest, OptimizeResponse, Route, RouteStop


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, default))
    except ValueError:
        return default


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


# ── 튜닝 파라미터 (server/.env 에서 변경 — 이강혁 README 참고) ──
OPT = {
    "cluster_radius_m": _env_float("OPT_CLUSTER_RADIUS_M", 30),
    "completion_bonus_ratio": _env_float("OPT_COMPLETION_BONUS_RATIO", 0.15),
    "cluster_stop_minutes": _env_int("OPT_CLUSTER_STOP_MINUTES", 3),
    "average_speed_kmh": _env_float("OPT_AVERAGE_SPEED_KMH", 25),
    "priority_value_m_per_point": _env_float(
        "OPT_PRIORITY_VALUE_M_PER_POINT", 75),
    "service_cost_m_per_minute": _env_float(
        "OPT_SERVICE_COST_M_PER_MINUTE", 100),
    "pickup_minutes": _env_int("OPT_PICKUP_MINUTES", 4),
    "search_seconds": _env_int("OPT_SEARCH_SECONDS", 10),
}

KAKAO_MOBILITY_KEY = os.getenv("KAKAO_MOBILITY_KEY", "")


def _parse_report_date(iso: str | None) -> str:
    """ISO 문자열 → 'YYYY-MM-DD' (없으면 오늘 = 경과일 0)"""
    if iso:
        try:
            return iso[:10]
        except Exception:
            pass
    return datetime.now().strftime("%Y-%m-%d")


def optimize(req: OptimizeRequest, time_limit_s: int | None = None
             ) -> OptimizeResponse:
    # ── 1) 입력 → 엔진 locations ──
    ret = req.return_to or req.depot
    locations = [{
        "name": "Start",
        "lat": req.depot.lat,
        "lon": req.depot.lng,
        "report_date": None,
    }]
    required_nodes = set()
    for i, s in enumerate(req.stops, start=1):
        locations.append(engine.make_bike(
            s.report_id,
            s.lat,
            s.lng,
            _parse_report_date(s.reported_at),
            hazard_score=max(0, s.priority),
            pickup_minutes=OPT["pickup_minutes"],
        ))
        if s.required:
            required_nodes.add(i)  # locations 인덱스 = i (0은 Start)
    locations.append({
        "name": "Storage",
        "lat": ret.lat,
        "lon": ret.lng,
        "report_date": None,
    })

    # ── 2) 엔진 실행 ──
    result = engine.solve_bike_loop(
        locations=locations,
        start_index=0,
        end_index=len(locations) - 1,
        vehicle_capacity=req.vehicle_capacity,
        cluster_radius_m=OPT["cluster_radius_m"],
        current_date=datetime.now(),
        completion_bonus_ratio=OPT["completion_bonus_ratio"],
        cluster_stop_minutes=OPT["cluster_stop_minutes"],
        max_route_minutes=req.work_minutes,
        average_speed_kmh=req.speed_kmh or OPT["average_speed_kmh"],
        priority_value_m_per_point=OPT["priority_value_m_per_point"],
        service_cost_m_per_minute=OPT["service_cost_m_per_minute"],
        search_seconds=time_limit_s or OPT["search_seconds"],
        required_nodes=required_nodes or None,
    )

    # ── 3) 앱 호환 응답으로 변환 ──
    speed_mpm = (req.speed_kmh or OPT["average_speed_kmh"]) * 1000 / 60
    stops_out: list[RouteStop] = []
    seq = 0
    eta = 0.0
    prev = (req.depot.lat, req.depot.lng)
    anchor_points = []  # 도로 경로용 경유지 (클러스터 대표점)

    for cluster in result["selected_clusters"]:
        a_lat = locations[cluster["anchor_node"]]["lat"]
        a_lng = locations[cluster["anchor_node"]]["lon"]
        eta += engine.haversine_distance_m(
            prev[0], prev[1], a_lat, a_lng) / speed_mpm
        anchor_points.append({"lat": a_lat, "lng": a_lng})
        for node in cluster["selected_nodes"]:
            seq += 1
            stops_out.append(RouteStop(
                report_id=locations[node]["name"],
                seq=seq,
                eta_minutes=int(round(eta)),
                demand=1,
            ))
        eta += cluster["service_minutes"]
        prev = (a_lat, a_lng)

    selected_ids = {s.report_id for s in stops_out}
    dropped = sorted(
        s.report_id for s in req.stops if s.report_id not in selected_ids)

    total_dist = int(result["distance_m"])
    total_min = int(result["route_minutes"])

    # ── 4) 도로 경로 (카카오모빌리티, 키 있을 때만) ──
    road_path = _fetch_road_path(
        req.depot, ret, anchor_points) if KAKAO_MOBILITY_KEY else None
    if road_path:
        total_dist = road_path["distance_m"]
        total_min = int(round(road_path["duration_s"] / 60)) + sum(
            c["service_minutes"] for c in result["selected_clusters"])

    return OptimizeResponse(
        routes=[
            Route(
                vehicle=1,
                stops=stops_out,
                load=result["used_capacity"],
                distance_m=total_dist,
                duration_minutes=total_min,
            )
        ] if stops_out else [],
        dropped_report_ids=dropped,
        total_distance_m=total_dist,
        total_duration_minutes=total_min,
        collected=result["used_capacity"],
        total_demand=len(req.stops),
        road_path=road_path,
    )


def _fetch_road_path(depot, ret, anchors: list[dict]) -> dict | None:
    """카카오모빌리티 다중경유지 길찾기 → 도로 폴리라인/거리/시간.
    실패하면 None (하버사인 결과 유지)."""
    if not anchors:
        return None
    try:
        body = {
            "origin": {"x": depot.lng, "y": depot.lat},
            "destination": {"x": ret.lng, "y": ret.lat},
            "waypoints": [
                {"x": a["lng"], "y": a["lat"], "name": f"stop{i+1}"}
                for i, a in enumerate(anchors[:30])  # API 한도 30
            ],
            "priority": "RECOMMEND",
        }
        r = httpx.post(
            "https://apis-navi.kakaomobility.com/v1/waypoints/directions",
            json=body,
            headers={
                "Authorization": f"KakaoAK {KAKAO_MOBILITY_KEY}",
                "Content-Type": "application/json",
            },
            timeout=10,
        )
        if r.status_code != 200:
            return None
        route = r.json()["routes"][0]
        if route.get("result_code", 0) != 0:
            return None

        # 도로 좌표(vertexes: [x,y,x,y,...]) 수집
        # section 단위 = 구간(출발→①, ①→②, ...) 이므로 따로 보관해
        # 앱이 구간별로 다른 색(그라데이션)을 그릴 수 있게 한다.
        pts: list[list[float]] = []
        segments: list[list[list[float]]] = []
        for sec in route.get("sections", []):
            seg: list[list[float]] = []
            for road in sec.get("roads", []):
                v = road.get("vertexes", [])
                for i in range(0, len(v) - 1, 2):
                    seg.append([v[i + 1], v[i]])  # [lat, lng]
            if len(seg) > 200:  # 구간당 최대 200점으로 샘플링
                step = math.ceil(len(seg) / 200)
                seg = seg[::step] + [seg[-1]]
            if seg:
                segments.append(seg)
                pts.extend(seg)

        # 전체 폴리라인도 축소(하위호환)
        if len(pts) > 600:
            step = math.ceil(len(pts) / 600)
            pts = pts[::step] + [pts[-1]]

        return {
            "polyline": pts,
            "segments": segments,
            "distance_m": int(route["summary"]["distance"]),
            "duration_s": int(route["summary"]["duration"]),
        }
    except Exception:
        return None
