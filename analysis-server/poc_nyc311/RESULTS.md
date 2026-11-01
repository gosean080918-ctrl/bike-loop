# Proof-of-concept results — validating the method on NYC 311 derelict-bicycle data

Run on 2026-07-14 | Data: NYC 311 (Socrata `erm2-nwe9`), `complaint_type = 'Derelict Bicycle'`

## The data

New York ran 'Derelict Bicycle' as its own complaint type from 2020-01 to 2021-09. Of the
2,930 records, the 2,743 that carry coordinates were used. Context and network limits ruled
out downloading individual points, so the data was aggregated server-side with Socrata SoQL
into 1,651 grid cells of roughly 111 m (0.001°) and downloaded as `grid.csv`. By borough:
Manhattan 1,205, Brooklyn 1,188, Queens 304, Bronx 151, Staten Island 9.

## 1. Hotspot analysis (`hotspot_analysis.py`)

A weighted KDE (Gaussian, bw = 0.08) and Getis-Ord Gi\* (KNN with k = 8, row-standardized,
999 permutations).

Result: 7 cells significant at 99%, 7 more at 95%. The strongest hotspot is near Port Morris
in the Bronx (40.8315, -73.9285) — 94 reports in a single cell, z = 4.04. The KDE additionally
shows high density on the Upper West Side, from the East Village through lower Manhattan, and
around Park Slope and Prospect Heights.

Outputs: `kde_heatmap.png`, `gistar_map.png`, `hotspots_top.csv` (top 60 cells)

## 2. Collection route optimization (`vrp_routing.py`)

The top 40 Gi\* cells became collection stops. A CVRP with three vehicles of capacity 60 and a
haversine distance matrix was solved with OR-Tools (guided local search, 10 s). Stops above
vehicle capacity were split across visits (at most 30 bicycles per visit), and because total
demand (224) exceeded total capacity (180), the remainder was carried over through
demand-weighted penalty disjunctions.

Result: all three vehicles full (60/60), 82.1 km travelled in total (27.4 / 26.5 / 28.2 km per
vehicle), 180 of 224 bicycles collected, 22 visits carried over.

Outputs: `routes.csv`, `vrp_routes.png`

## 3. Time-series exploration (`timeseries_check.py`)

Monthly report volume across the 21 months shows clear seasonality: a summer peak (June
averaging 187 reports) and a winter trough (December averaging 81). With only 21 observations,
a monthly profile was examined rather than fitting SARIMA — but the existence of seasonality is
itself the argument for including a graduation-season event regressor in the Korean deployment.

Output: `monthly_trend.png`

## Conclusions and limitations

All three methods — KDE/Gi\* hotspots, CVRP routing, and seasonality — produced meaningful
results on real public data, and transferred directly into the app's analysis pipeline.

Limitations:

1. Because the data is grid-aggregated, a combined space-time hotspot analysis was not
   possible. Production uses raw coordinates.
2. The distance matrix approximates road distance with straight lines. Production uses the
   Kakao Mobility distance matrix.
3. Gi\* is conservative on sparse cells, of which there were many with n = 1 or 2. A smaller
   service area needs its cell size re-tuned.
4. New York's summer peak reflects the cycling season, whereas a campus area's cycle is
   graduation and move-out. The patterns may differ, which is why event-based features matter
   most.

## Reproducing it

```
pip install numpy pandas matplotlib scipy libpysal esda ortools
python3 hotspot_analysis.py   # needs grid.csv
python3 vrp_routing.py        # needs hotspots_top.csv
python3 timeseries_check.py   # needs monthly.csv
```
