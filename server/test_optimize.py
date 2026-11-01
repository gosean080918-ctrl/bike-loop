"""Local verification: engine v2 behind the FastAPI TestClient, Jeju scenarios."""
from datetime import datetime, timedelta

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)
NOW = datetime(2026, 7, 21)


def iso(days_ago: int) -> str:
    return (NOW - timedelta(days=days_ago)).strftime("%Y-%m-%dT09:00:00")


def make_stops():
    """Two clusters plus three isolated bikes, spread across urgency tiers."""
    stops = []
    # Cluster A: 3 bikes within 30 m, long-standing reports
    base = (33.2900, 126.2650)
    for i, d in enumerate([95, 70, 40]):
        stops.append({
            "report_id": f"A{i}",
            "lat": base[0] + i * 0.0001,
            "lng": base[1] + i * 0.0001,
            "reported_at": iso(d),
        })
    # Cluster B: 2 bikes, recent reports
    for i, d in enumerate([5, 10]):
        stops.append({
            "report_id": f"B{i}",
            "lat": 33.3320 + i * 0.0001,
            "lng": 126.2510 + i * 0.0001,
            "reported_at": iso(d),
        })
    # Three isolated bikes
    for i, (lat, lng, d) in enumerate([
        (33.3060, 126.2860, 65),
        (33.2750, 126.3050, 20),
        (33.3150, 126.2700, 3),
    ]):
        stops.append({
            "report_id": f"X{i}",
            "lat": lat,
            "lng": lng,
            "reported_at": iso(d),
        })
    return stops


DEPOT = {"lat": 33.2870, "lng": 126.2630}  # depot used in the test scenarios


def test_health():
    assert client.get("/health").json() == {"ok": True}


def test_cost_benefit():
    """Engine policy: urgent old reports are collected; recent distant ones roll over."""
    r = client.post("/optimize", json={
        "depot": DEPOT,
        "vehicle_capacity": 20,
        "work_minutes": 240,
        "stops": make_stops(),
    })
    assert r.status_code == 200, r.text
    b = r.json()
    picked = {s["report_id"] for s in b["routes"][0]["stops"]}
    # 90 and 70 days old (Critical / High) must be collected
    assert {"A0", "A1"} <= picked, picked
    # Everything rolled over must be under 30 days old (Normal)
    recent = {"B0", "B1", "X2"}  # 5, 10 and 3 days old
    assert set(b["dropped_report_ids"]) <= recent, b["dropped_report_ids"]
    seqs = [s["seq"] for s in b["routes"][0]["stops"]]
    assert seqs == sorted(seqs)
    assert b["total_duration_minutes"] > 0
    print("cost-benefit ok:", sorted(picked), "| carry-over:",
          b["dropped_report_ids"], "|", b["total_duration_minutes"], "min")


def test_capacity_priority():
    """Capacity of 4: the solver favours high-urgency reports and rolls over the rest."""
    r = client.post("/optimize", json={
        "depot": DEPOT,
        "vehicle_capacity": 4,
        "work_minutes": 240,
        "stops": make_stops(),
    })
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["collected"] <= 4
    assert len(b["dropped_report_ids"]) >= 4
    picked = {s["report_id"] for s in b["routes"][0]["stops"]}
    # A0, the oldest at 95 days, must be included
    assert "A0" in picked, picked
    print("capacity ok: picked", sorted(picked),
          "dropped", b["dropped_report_ids"])


def test_worktime_limit():
    """A 25-minute budget: collect a subset and still return in time."""
    r = client.post("/optimize", json={
        "depot": DEPOT,
        "vehicle_capacity": 20,
        "work_minutes": 25,
        "stops": make_stops(),
    })
    assert r.status_code == 200, r.text
    b = r.json()
    assert b["total_duration_minutes"] <= 25
    assert b["collected"] < 8
    print("worktime ok:", b["collected"], "collected in",
          b["total_duration_minutes"], "min")


def test_return_to_differs():
    """Works when the return point differs from the depot."""
    r = client.post("/optimize", json={
        "depot": DEPOT,
        "return_to": {"lat": 33.3100, "lng": 126.2900},
        "vehicle_capacity": 20,
        "work_minutes": 240,
        "stops": make_stops()[:4],
    })
    assert r.status_code == 200, r.text
    b = r.json()
    picked = {s["report_id"] for s in b["routes"][0]["stops"]}
    assert {"A0", "A1", "A2"} <= picked  # the old cluster must be collected
    print("return ok:", b["collected"], "collected,",
          b["total_distance_m"], "m")


if __name__ == "__main__":
    test_health()
    test_cost_benefit()
    test_capacity_priority()
    test_worktime_limit()
    test_return_to_differs()
    print("ALL TESTS PASSED")
