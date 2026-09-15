"""
PoC 1 — 핫스팟 분석: NYC 311 'Derelict Bicycle' (2020-01 ~ 2021-09, n=2,743)
방법: ~111m 그리드 셀 집계 데이터에 대해
  (a) KDE(가우시안 커널 밀도) 히트맵
  (b) Getis-Ord Gi* (KNN 공간가중, 유의 핫스팟 z>1.96 / z>2.58)
출력: kde_heatmap.png, gistar_map.png, hotspots_top.csv
"""
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from scipy.stats import gaussian_kde
from libpysal.weights import KNN
from esda.getisord import G_Local

df = pd.read_csv("grid.csv")
df["lat"] = df["a"] / 1000 + 0.0005   # 셀 중심
df["lng"] = df["b"] / 1000 + 0.0005
# 외곽 이상치(스태튼섬 끝 등) 제거 없이 전체 사용
coords = df[["lng", "lat"]].to_numpy()
n = df["n"].to_numpy(dtype=float)
print(f"cells={len(df)}, reports={int(n.sum())}")

# ---------- (a) KDE ----------
kde = gaussian_kde(coords.T, weights=n, bw_method=0.08)
gx = np.linspace(-74.10, -73.75, 300)
gy = np.linspace(40.55, 40.92, 300)
XX, YY = np.meshgrid(gx, gy)
Z = kde(np.vstack([XX.ravel(), YY.ravel()])).reshape(XX.shape)

fig, ax = plt.subplots(figsize=(8, 9))
im = ax.imshow(Z, origin="lower", extent=[gx[0], gx[-1], gy[0], gy[-1]],
               cmap="hot_r", aspect="auto")
ax.scatter(coords[:, 0], coords[:, 1], s=1, c="steelblue", alpha=0.3)
ax.set_title("KDE — NYC Derelict Bicycle reports (2020-2021)")
ax.set_xlabel("lng"); ax.set_ylabel("lat")
fig.colorbar(im, ax=ax, label="density")
fig.tight_layout(); fig.savefig("kde_heatmap.png", dpi=130); plt.close(fig)
print("saved kde_heatmap.png")

# ---------- (b) Getis-Ord Gi* ----------
w = KNN.from_array(coords, k=8)
w.transform = "R"
np.random.seed(42)
g = G_Local(n, w, star=True, permutations=999)
df["gi_z"] = g.Zs
df["gi_p"] = g.p_sim
hot99 = df[(df.gi_z > 2.58) & (df.gi_p < 0.01)]
hot95 = df[(df.gi_z > 1.96) & (df.gi_p < 0.05)]
print(f"hotspot cells: 99%={len(hot99)}, 95%={len(hot95)}")

fig, ax = plt.subplots(figsize=(8, 9))
cold = df[df.gi_z <= 1.96]
ax.scatter(cold.lng, cold.lat, s=3, c="lightgray", label="n.s.")
h95 = df[(df.gi_z > 1.96) & (df.gi_z <= 2.58)]
ax.scatter(h95.lng, h95.lat, s=12, c="orange", label="hot (95%)")
ax.scatter(hot99.lng, hot99.lat, s=20, c="red", label="hot (99%)")
ax.set_title("Getis-Ord Gi* hotspots — Derelict Bicycle")
ax.set_xlabel("lng"); ax.set_ylabel("lat"); ax.legend()
fig.tight_layout(); fig.savefig("gistar_map.png", dpi=130); plt.close(fig)
print("saved gistar_map.png")

top = df.sort_values("gi_z", ascending=False).head(60)
top[["lat", "lng", "n", "gi_z", "gi_p"]].to_csv("hotspots_top.csv", index=False)
print("saved hotspots_top.csv")
print(top.head(10)[["lat", "lng", "n", "gi_z"]].to_string(index=False))
