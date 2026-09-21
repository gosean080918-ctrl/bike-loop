"""
서버 접근 통제 (2026-09-15, 일반 공개 대비)

[왜 필요한가]
이 서버의 /address · /search 는 카카오 REST 키를 대신 호출해 준다.
인증 없이 열어두면 누구나 주소·검색 API를 무제한으로 호출할 수 있고,
그 요금과 할당량은 전부 우리(의뢰자) 부담이 된다.
저장소를 공개하거나 앱을 스토어에 올리면 서버 주소도 알려지므로
'로그인한 우리 앱 사용자만' 호출할 수 있게 막아야 한다.

[어떻게 막는가]
앱이 Supabase 로그인 토큰(access token)을 Authorization 헤더로 보낸다.
서버는 그 토큰이 진짜인지 Supabase에 물어보고, 맞으면 통과시킨다.
- 토큰 검증 결과는 짧게 캐시해 매번 왕복하지 않는다.
- 사용자별 호출 횟수를 제한해 한 계정이 폭주하는 것도 막는다.

[설계 선택]
JWT 서명을 직접 검증하는 방법도 있지만, Supabase가 프로젝트마다
서명 방식(대칭키/비대칭키)을 다르게 쓰기 때문에 환경에 따라 깨진다.
Supabase에 직접 물어보는 방식은 어떤 프로젝트에서도 똑같이 동작한다.
"""
import os
import time
from collections import deque

import httpx
from fastapi import Header, HTTPException

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# 개발 중에는 인증을 끌 수 있다. 운영에서는 절대 true로 두지 말 것.
AUTH_DISABLED = os.getenv("AUTH_DISABLED", "").lower() in ("1", "true", "yes")

# 토큰 검증 캐시 (토큰 → (사용자ID, 만료시각))
_CACHE_TTL = int(os.getenv("AUTH_CACHE_SECONDS", "300"))
_cache: dict[str, tuple[str, float]] = {}

# 사용자별 호출 제한: 기본 분당 60회
_RATE_LIMIT = int(os.getenv("RATE_LIMIT_PER_MIN", "60"))
_calls: dict[str, deque] = {}


def _rate_check(user_id: str) -> None:
    now = time.time()
    q = _calls.setdefault(user_id, deque())
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= _RATE_LIMIT:
        raise HTTPException(429, "요청이 너무 잦습니다. 잠시 후 다시 시도해주세요.")
    q.append(now)


def _verify_with_supabase(token: str) -> str:
    """Supabase에 토큰을 물어보고 사용자 ID를 돌려준다. 실패하면 401."""
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        # 설정이 빠진 채로 배포되면 '누구나 통과'가 되지 않도록 막는다
        raise HTTPException(
            500, "server auth is not configured (SUPABASE_URL / SUPABASE_ANON_KEY)"
        )
    try:
        r = httpx.get(
            f"{SUPABASE_URL}/auth/v1/user",
            headers={
                "Authorization": f"Bearer {token}",
                "apikey": SUPABASE_ANON_KEY,
            },
            timeout=5,
        )
    except httpx.HTTPError as e:
        raise HTTPException(503, f"auth check failed: {e}") from e

    if r.status_code != 200:
        raise HTTPException(401, "로그인이 필요합니다 (invalid token)")
    uid = (r.json() or {}).get("id")
    if not uid:
        raise HTTPException(401, "로그인이 필요합니다 (no user)")
    return uid


def require_user(authorization: str = Header(default="")) -> str:
    """
    FastAPI 의존성. 모든 보호 엔드포인트에 붙인다.
    성공하면 사용자 ID를 반환한다.
    """
    if AUTH_DISABLED:
        return "auth-disabled"

    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "로그인이 필요합니다 (missing token)")
    token = authorization[7:].strip()
    if not token:
        raise HTTPException(401, "로그인이 필요합니다 (empty token)")

    now = time.time()
    hit = _cache.get(token)
    if hit and hit[1] > now:
        _rate_check(hit[0])
        return hit[0]

    uid = _verify_with_supabase(token)
    _cache[token] = (uid, now + _CACHE_TTL)

    # 캐시가 무한정 커지지 않도록 만료분 정리
    if len(_cache) > 1000:
        for k, (_, exp) in list(_cache.items()):
            if exp <= now:
                _cache.pop(k, None)

    _rate_check(uid)
    return uid
