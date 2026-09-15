"""요청/응답 스키마 — POST /optimize (v2: 이강혁 엔진 호환)"""
from pydantic import BaseModel, Field


class Point(BaseModel):
    lat: float
    lng: float


class Stop(BaseModel):
    report_id: str
    lat: float
    lng: float
    demand: int = 1            # (v2에서는 신고 1건 = 자전거 1대로 취급)
    priority: int = 0          # 위험도 가중(hazard_score)으로 반영
    required: bool = False     # (v2 미사용 — 하위호환용)
    reported_at: str | None = None  # ISO 신고일 → 경과일/urgency 계산


class OptimizeRequest(BaseModel):
    depot: Point                          # 출발지
    return_to: Point | None = None        # 복귀지(보관소), 없으면 출발지
    vehicle_count: int = Field(1, ge=1, le=10)  # (v2는 단일 차량)
    vehicle_capacity: int = Field(20, ge=1)
    work_minutes: int = Field(240, ge=10)
    service_minutes: int = Field(5, ge=0)      # (v2는 OPT_PICKUP_MINUTES 사용)
    speed_kmh: float | None = None             # 없으면 OPT_AVERAGE_SPEED_KMH
    max_per_visit: int = Field(30, ge=1)       # (v2 미사용 — 클러스터가 대체)
    stops: list[Stop]


class RouteStop(BaseModel):
    report_id: str
    seq: int
    eta_minutes: int
    demand: int


class Route(BaseModel):
    vehicle: int
    stops: list[RouteStop]
    load: int
    distance_m: int
    duration_minutes: int


class OptimizeResponse(BaseModel):
    routes: list[Route]
    dropped_report_ids: list[str]
    total_distance_m: int
    total_duration_minutes: int
    collected: int
    total_demand: int
    # 카카오모빌리티 도로 경로 (키 미설정/실패 시 None)
    # {"polyline": [[lat,lng],...], "distance_m": int, "duration_s": int}
    road_path: dict | None = None
