"""
BikeReclaim 서버 — /optimize(v2: 이강혁 엔진) + /address + /search.
카카오 REST 키/카카오모빌리티 키/OPT_* 튜닝값: .env (앱에는 절대 금지)
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


# /health 만 공개 — 배포 상태 확인용이며 키를 쓰지 않는다.
# 나머지는 전부 로그인한 앱 사용자만 호출할 수 있다(auth.require_user).
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
        # 필수 방문 지점이 용량/시간 제약을 넘을 때 주로 발생
        raise HTTPException(
            422,
            "선택한 지점을 모두 돌 수 없습니다. "
            "차량 적재량이나 작업시간을 늘리거나 수거 대상을 줄여주세요. "
            f"(상세: {e})",
        ) from e
    except ValueError as e:
        raise HTTPException(422, str(e)) from e
