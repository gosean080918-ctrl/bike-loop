"""Request / response schemas for POST /optimize (v2 engine)."""
from pydantic import BaseModel, Field


class Point(BaseModel):
    lat: float
    lng: float


class Stop(BaseModel):
    report_id: str
    lat: float
    lng: float
    demand: int = 1            # v2 treats one report as one bicycle
    priority: int = 0          # folded into the hazard score
    required: bool = False     # unused in v2, kept for backward compatibility
    reported_at: str | None = None  # ISO report date -> days elapsed -> urgency


class OptimizeRequest(BaseModel):
    depot: Point                          # start point
    return_to: Point | None = None        # return point; defaults to the depot
    vehicle_count: int = Field(1, ge=1, le=10)  # v2 plans a single vehicle
    vehicle_capacity: int = Field(20, ge=1)
    work_minutes: int = Field(240, ge=10)
    service_minutes: int = Field(5, ge=0)      # v2 uses OPT_PICKUP_MINUTES
    speed_kmh: float | None = None             # falls back to OPT_AVERAGE_SPEED_KMH
    max_per_visit: int = Field(30, ge=1)       # unused in v2; clustering replaces it
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
    # Road-following route from Kakao Mobility (None if the key is unset or the call fails)
    # {"polyline": [[lat,lng],...], "distance_m": int, "duration_s": int}
    road_path: dict | None = None
