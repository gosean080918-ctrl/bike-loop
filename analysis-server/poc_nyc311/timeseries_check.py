"""
PoC 3 — 시계열 탐색 (월별 신고량, 2020-01 ~ 2021-09)
21개월뿐이라 SARIMA 적합 대신 계절 프로파일(월별 평균) 확인.
결론 도출용: 계절성 존재 여부 + 제주 적용 시 '졸업 시즌' 이벤트 회귀변수 근거.
출력: monthly_trend.png
"""
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

df = pd.read_csv("monthly.csv")
df["month"] = pd.to_datetime(df["month"])
df["moy"] = df["month"].dt.month
prof = df.groupby("moy")["n"].mean()

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 7))
ax1.plot(df["month"], df["n"], "-o")
ax1.set_title("Monthly Derelict Bicycle reports (NYC 311)")
ax2.bar(prof.index, prof.values, color="tab:orange")
ax2.set_title("Month-of-year mean profile (seasonality)")
ax2.set_xticks(range(1, 13))
fig.tight_layout(); fig.savefig("monthly_trend.png", dpi=130); plt.close(fig)
peak = prof.idxmax(); trough = prof.idxmin()
print(f"peak month={peak} (mean {prof.max():.0f}), trough month={trough} (mean {prof.min():.0f})")
print("saved monthly_trend.png")
