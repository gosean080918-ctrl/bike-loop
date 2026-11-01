"""
BIKE LOOP server — /optimize (v2 engine) + /address + /search.
Kakao REST key, Kakao Mobility key and OPT_* tuning values live in .env only;
they must never be shipped inside the app.
"""
import os

import httpx
from fastapi import Depends, FastAPI, HTTPException

try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from auth import require_user
from models import OptimizeRequest, OptimizeResponse
from optimizer import optimize

app = FastAPI(title="BIKE LOOP Optimizer", version="0.4.0")

KAKAO_REST_KEY = os.getenv("KAKAO_REST_KEY", "")


# Only /health is public: it reports deployment status and touches no API key.
# Everything else is restricted to signed-in app users (see auth.require_user).
@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.get("/address")
def reverse_geocode(
    lat: float, lng: float, _user: str = Depends(require_user)
) -> dict:
    if not KAKAO_REST_KEY:
        raise HTTPException(501, "KAKAO_REST_KEY not set")
    r = httpx.get(
        "https://dapi.kakao.com/v2/local/geo/coord2address.json",
        params={"x": lng, "y": lat},
        headers={"Authorization": f"KakaoAK {KAKAO_REST_KEY}"},
        timeout=5,
    )
    if r.status_code != 200:
        raise HTTPException(502, f"kakao error: {r.status_code}")
    docs = r.json().get("documents", [])
    if not docs:
        return {"address": None}
    d = docs[0]
    road = (d.get("road_address") or {}).get("address_name")
    jibun = (d.get("address") or {}).get("address_name")
    return {"address": road or jibun}


@app.get("/search")
def keyword_search(
    q: str, size: int = 7, _user: str = Depends(require_user)
) -> dict:
    if not KAKAO_REST_KEY:
        raise HTTPException(501, "KAKAO_REST_KEY not set")
    r = httpx.get(
        "https://dapi.kakao.com/v2/local/search/keyword.json",
        params={"query": q, "size": max(1, min(size, 15))},
        headers={"Authorization": f"KakaoAK {KAKAO_REST_KEY}"},
        timeout=5,
    )
    if r.status_code != 200:
        raise HTTPException(502, f"kakao error: {r.status_code}")
    docs = r.json().get("documents", [])
    return {
        "places": [
            {
                "name": d.get("place_name"),
                "address": d.get("road_address_name")
                    or d.get("address_name"),
                "lat": float(d["y"]),
                "lng": float(d["x"]),
            }
            for d in docs
        ]
    }


@app.post("/optimize", response_model=OptimizeResponse)
def run_optimize(
    req: OptimizeRequest, _user: str = Depends(require_user)
) -> OptimizeResponse:
    if not req.stops:
        raise HTTPException(400, "stops is empty")
    if len(req.stops) > 200:
        raise HTTPException(400, "max 200 stops")
    try:
        return optimize(req)
    except RuntimeError as e:
        # Usually raised when mandatory stops exceed capacity or working time
        raise HTTPException(
            422,
            "The selected stops cannot all be visited. "
            "Increase vehicle capacity or working time, or select fewer stops. "
            f"(detail: {e})",
        ) from e
    except ValueError as e:
        raise HTTPException(422, str(e)) from e
