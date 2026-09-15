"""
PoC 2 — 수거 동선 최적화 (CVRP, OR-Tools)
입력: hotspots_top.csv (Gi* 상위 셀) → 상위 40개 지점을 수거 스톱으로
설정: 차량 3대, 용량 60대/차량, 수요 = 셀 신고건수(추정 방치대수 프록시)
거리: 하버사인(도로거리 근사). 실서비스에선 카카오모빌리티 거리행렬로 대체.
출력: routes.csv, vrp_routes.png
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from ortools.constraint_solver import routing_enums_pb2, pywrapcp

stops = pd.read_csv("hotspots_top.csv").head(40).reset_index(drop=True)
# 용량 초과 대형 지점은 여러 방문으로 분할 (실서비스 로직과 동일)
MAX_PER_VISIT = 30
split = []
for _, r in stops.iterrows():
    d = int(r.n)
    while d > 0:
        take = min(d, MAX_PER_VISIT)
        split.append((r.lat, r.lng, take))
        d -= take
stops = pd.DataFrame(split, columns=["lat", "lng", "n"])
DEPOT = (40.7210, -73.9870)  # 가상 차고지(맨해튼 남부)
lats = np.concatenate([[DEPOT[0]], stops.lat.to_numpy()])
lngs = np.concatenate([[DEPOT[1]], stops.lng.to_numpy()])
demand = [0] + stops.n.astype(int).tolist()
N, V, CAP = len(lats), 3, 60

def haversine_matrix(lat, lng):
    R = 6371000
    la = np.radians(lat)[:, None]; lo = np.radians(lng)[:, None]
    dla = la - la.T; dlo = lo - lo.T
    h = np.sin(dla/2)**2 + np.cos(la)*np.cos(la.T)*np.sin(dlo/2)**2
    return (2*R*np.arcsin(np.sqrt(h))).astype(int)

D = haversine_matrix(lats, lngs)

mgr = pywrapcp.RoutingIndexManager(N, V, 0)
rt = pywrapcp.RoutingModel(mgr)
rt.SetArcCostEvaluatorOfAllVehicles(
    rt.RegisterTransitCallback(lambda i, j: int(D[mgr.IndexToNode(i)][mgr.IndexToNode(j)])))
dcb = rt.RegisterUnaryTransitCallback(lambda i: demand[mgr.IndexToNode(i)])
rt.AddDimensionWithVehicleCapacity(dcb, 0, [CAP]*V, True, "cap")
# 용량 초과분은 이월 허용(수요 큰 지점 우선 수거)
for node in range(1, N):
    rt.AddDisjunction([mgr.NodeToIndex(node)], 100000 * demand[node])

p = pywrapcp.DefaultRoutingSearchParameters()
p.first_solution_strategy = routing_enums_pb2.FirstSolutionStrategy.PATH_CHEAPEST_ARC
p.local_search_metaheuristic = routing_enums_pb2.LocalSearchMetaheuristic.GUIDED_LOCAL_SEARCH
p.time_limit.FromSeconds(10)
sol = rt.SolveWithParameters(p)
assert sol, "no solution"

rows, total = [], 0
colors = ["tab:red", "tab:blue", "tab:green"]
fig, ax = plt.subplots(figsize=(8, 9))
ax.scatter(*DEPOT[::-1], marker="s", s=120, c="black", zorder=5, label="depot")
for v in range(V):
    idx, seq, load, dist = rt.Start(v), 0, 0, 0
    path = [0]
    while not rt.IsEnd(idx):
        nxt = sol.Value(rt.NextVar(idx))
        a, b = mgr.IndexToNode(idx), mgr.IndexToNode(nxt)
        dist += D[a][b]; idx = nxt
        if b != 0:
            seq += 1; load += demand[b]; path.append(b)
            rows.append(dict(vehicle=v+1, seq=seq, lat=lats[b], lng=lngs[b], demand=demand[b]))
    path.append(0); total += dist
    ax.plot(lngs[path], lats[path], "-o", ms=4, c=colors[v],
            label=f"veh{v+1}: {load} bikes, {dist/1000:.1f} km")
dropped = [mgr.IndexToNode(i) for i in range(rt.Size()) if rt.IsStart(i)==False and rt.IsEnd(i)==False and sol.Value(rt.NextVar(i))==i]
print(f"TOTAL distance: {total/1000:.1f} km, collected={sum(demand)-sum(demand[d] for d in dropped)}/{sum(demand)}, deferred stops={len(dropped)}")
pd.DataFrame(rows).to_csv("routes.csv", index=False)
ax.set_title("CVRP collection routes (3 vehicles, cap 60) - top-40 Gi* hotspots")
ax.set_xlabel("lng"); ax.set_ylabel("lat"); ax.legend()
fig.tight_layout(); fig.savefig("vrp_routes.png", dpi=130); plt.close(fig)
print("saved routes.csv, vrp_routes.png")
