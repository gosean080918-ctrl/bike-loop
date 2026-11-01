"""
Server access control (2026-09-15, added before the public launch).

[Why this exists]
/address and /search call the Kakao REST API on the caller's behalf. Left open,
anyone could hit them without limit and the quota and the bill would land on us.
Publishing the repository or shipping the app also publishes the server URL, so
access has to be restricted to signed-in users of our own app.

[How it works]
The app sends its Supabase access token in the Authorization header. The server
asks Supabase whether that token is genuine and lets the request through if so.
- Verification results are cached briefly so we do not round-trip on every call.
- Calls are rate-limited per user so a single account cannot flood the service.

[Design choice]
Verifying the JWT signature locally is possible, but Supabase projects differ in
signing scheme (symmetric vs asymmetric), so that approach breaks depending on the
environment. Asking Supabase directly behaves identically on every project.
"""
import os
import time
from collections import deque

import httpx
from fastapi import Header, HTTPException

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

# Can be disabled during local development. Never set this true in production.
AUTH_DISABLED = os.getenv("AUTH_DISABLED", "").lower() in ("1", "true", "yes")

# Verification cache: token -> (user id, expiry timestamp)
_CACHE_TTL = int(os.getenv("AUTH_CACHE_SECONDS", "300"))
_cache: dict[str, tuple[str, float]] = {}

# Per-user rate limit: 60 calls per minute by default
_RATE_LIMIT = int(os.getenv("RATE_LIMIT_PER_MIN", "60"))
_calls: dict[str, deque] = {}


def _rate_check(user_id: str) -> None:
    now = time.time()
    q = _calls.setdefault(user_id, deque())
    while q and now - q[0] > 60:
        q.popleft()
    if len(q) >= _RATE_LIMIT:
        raise HTTPException(429, "Too many requests. Please try again shortly.")
    q.append(now)


def _verify_with_supabase(token: str) -> str:
    """Ask Supabase to validate the token and return the user id; 401 on failure."""
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        # If the deployment is missing config, fail closed rather than letting everyone in
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
        raise HTTPException(401, "Login required (invalid token)")
    uid = (r.json() or {}).get("id")
    if not uid:
        raise HTTPException(401, "Login required (no user)")
    return uid


def require_user(authorization: str = Header(default="")) -> str:
    """
    FastAPI dependency applied to every protected endpoint.
    Returns the user id on success.
    """
    if AUTH_DISABLED:
        return "auth-disabled"

    if not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Login required (missing token)")
    token = authorization[7:].strip()
    if not token:
        raise HTTPException(401, "Login required (empty token)")

    now = time.time()
    hit = _cache.get(token)
    if hit and hit[1] > now:
        _rate_check(hit[0])
        return hit[0]

    uid = _verify_with_supabase(token)
    _cache[token] = (uid, now + _CACHE_TTL)

    # Drop expired entries so the cache cannot grow without bound
    if len(_cache) > 1000:
        for k, (_, exp) in list(_cache.items()):
            if exp <= now:
                _cache.pop(k, None)

    _rate_check(uid)
    return uid
