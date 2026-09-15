"""로컬 검증 v2 — 이강혁 엔진 + FastAPI TestClient (제주 가상 시나리오)"""
from datetime import datetime, timedelta

from fastapi.testclient import TestClient

from main import app

client = TestClient(app)
NOW = datetime(2026, 7, 21)


def iso(days_ago: int) -> str:
    return (NOW - timedelta(days=days_ago)).strftime("%Y-%m-%dT09:00:00")


def make_stops():
    """클러스터 2개 + 고립 3대. 경과일로 urgency 분산."""
    stops = []
    # Cluster A (구억리 인근, 30m 내 3대) — 오래된 신고
    base = (33.2900, 126.2650)
    for i, d in enumerate([95, 70, 40]):
        stops.append({
            "report_id": f"A{i}",
            "lat": base[0] + i * 0.0001,
            "lng": base[1] + i * 0.0001,
            "reported_at": iso(d),
        })
    # Cluster B (저지리 인근, 2대) — 최근 신고
    for i, d in enumerate([5, 10]):
        stops.append({
            "report_id": f"B{i}",
            "lat": 33.3320 + i * 0.0001,
            "lng": 126.2510 + i * 0.0001,
            "reported_at": iso(d),
        })
    # 고립 3대
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


DEPOT = {"lat": 33.2870, "lng": 126.2630}  # 글로벌에듀시티 인근


def test_health():
    assert client.get("/health").json() == {"ok": True}


def test_cost_benefit():
    """엔진 철학: 오래된(긴급) 신고는 수거, 최근+먼 신고는 자동 이월"""
    r = client.post("/optimize", json={
        "depot": DEPOT,
        "vehicle_capacity": 20,
        "work_minutes": 240,
        "stops": make_stops(),
    })
    assert r.status_code == 200, r.text
    b = r.json()
    picked = {s["report_id"] for s in b["routes"][0]["stops"]}
    # 90일/70일 경과(Critical/High)는 반드시 수거
    assert {"A0", "A1"} <= picked, picked
    # 이월된 것들은 전부 30일 미만(Normal)이어야 함
    recent = {"B0", "B1", "X2"}  # 5/10/3일 경과
    assert set(b["dropped_report_ids"]) <= recent, b["dropped_report_ids"]
    seqs = [s["seq"] for s in b["routes"][0]["stops"]]
    assert seqs == sorted(seqs)
    assert b["total_duration_minutes"] > 0
    print("cost-benefit ok:", sorted(picked), "| carry-over:",
          b["dropped_report_ids"], "|", b["total_duration_minutes"], "min")


def test_capacity_priority():
    """용량 4대 → 오래된 신고(urgency 높은) 위주 선택 + 이월"""
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
    # 가장 오래된 A0(95일)는 반드시 포함되어야 함
    assert "A0" in picked, picked
    print("capacity ok: picked", sorted(picked),
          "dropped", b["dropped_report_ids"])


def test_worktime_limit():
    """작업시간 25분 제한 → 일부만 수거하고 시간 내 복귀"""
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
    """복귀지가 출발지와 다를 때도 정상 작동"""
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
    assert {"A0", "A1", "A2"} <= picked  # 오래된 클러스터는 반드시 수거
    print("return ok:", b["collected"], "collected,",
          b["total_distance_m"], "m")


if __name__ == "__main__":
    test_health()
    test_cost_benefit()
    test_capacity_priority()
    test_worktime_limit()
    test_return_to_differs()
    print("ALL TESTS PASSED")
