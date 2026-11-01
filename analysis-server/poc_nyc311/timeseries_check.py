"""
PoC 3 — time-series exploration of monthly report volume (2020-01 to 2021-09)
With only 21 months available, a seasonal profile (monthly means) is examined instead of fitting SARIMA.
Purpose: establish whether seasonality exists, and whether a graduation-season event regressor would be justified.
Output: monthly_trend.png
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
