# BIKE LOOP optimization server

A deliberately tiny FastAPI service. The main endpoint is `POST /optimize`, with
`GET /address` and `GET /search` acting as Kakao proxies and `GET /health` reporting status.
The solver is an OR-Tools CVRP, ported from the proof of concept in
`analysis-server/poc_nyc311`.

## Running locally

```bash
cd server
pip install -r requirements.txt
cp .env.example .env      # fill in the Kakao REST key and Supabase URL / anon key
uvicorn main:app --reload
# Swagger UI for ad-hoc testing: http://127.0.0.1:8000/docs
```

Tests: `python test_optimize.py` (three scenarios).

During local development, `AUTH_DISABLED=1` skips token checks. Never set it in a deployed
environment.

## Example request

```json
POST /optimize
{
  "depot": {"lat": 33.306, "lng": 126.286},
  "vehicle_count": 1,
  "vehicle_capacity": 20,
  "work_minutes": 240,
  "service_minutes": 5,
  "stops": [
    {"report_id": "uuid-1", "lat": 33.31, "lng": 126.29, "demand": 1,
     "priority": 2, "required": false}
  ]
}
```

The response carries, per vehicle, the visit order (`seq`), ETAs and load, plus the stops that
were carried over (`dropped_report_ids`) and the total distance and time. The admin screens in
the app save this into `collection_jobs` and `job_stops`.

## Constraints supported

Vehicle count and capacity, available working time, per-stop service time, priority (weighted
so urgent stops are not endlessly deferred), mandatory stops (`required`), and separate start
and return points. Splitting oversized stops across visits and carrying the excess over to the
next run are both automatic — two lessons taken straight from the proof of concept.

## Deploying (Cloud Run)

```bash
gcloud run deploy bikeloop-optimizer --source . --region asia-northeast3 \
  --allow-unauthenticated
```

`--allow-unauthenticated` refers to Cloud Run's own IAM layer only: the application itself
still rejects anonymous callers. Every endpoint except `/health` requires a valid Supabase
access token, verified in `auth.py` and rate-limited per user. Railway and Fly detect the
Dockerfile automatically.

Environment variables (see `.env.example`): `KAKAO_REST_KEY`, `KAKAO_MOBILITY_KEY`,
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, plus the optional `RATE_LIMIT_PER_MIN`,
`AUTH_CACHE_SECONDS` and the `OPT_*` tuning values. None of these are committed.

## Limitations and next steps

- Distances and times inside the solver are still haversine approximations; Kakao's car
  routing matrix is used for display but not yet fed back into the optimizer.
- Multi-vehicle routing is implemented but has not been exercised in the field.
