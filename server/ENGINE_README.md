# Optimization engine — design notes

> These notes describe the Python framework this project's optimizer is built on. They are an
> English translation of the original description by **이강혁 (Kang-Hyuk Lee)**, used with
> permission. The wording is his; the translation is ours.

The code groups reported bicycles into hotspots by location, then decides which bicycles to
collect and in what order, weighing days since the report, the number of bicycles, travel
distance and vehicle capacity together.

The logic runs as follows.

## 1. Building hotspots at a 30 m radius

- Bicycles reported close together are grouped into clusters of 30 m radius.
- Every bicycle in a cluster must lie within 30 m of its anchor bicycle. This prevents the
  chaining problem, where a cluster grows indefinitely by following one connected bicycle to
  the next.
- An isolated bicycle becomes a cluster of size 1.
- Whether two reports are duplicates is hard to verify in practice, so no duplicate detection
  is included here; each report is treated as one independent bicycle.

## 2. Computing cluster information

For each cluster:

- days elapsed for the oldest report
- mean days elapsed for the three oldest
- total bicycles in the cluster
- bicycles past 60 days
- bicycles past 90 days
- estimated collection time
- additional travel distance relative to Start and Storage
- the cluster's actual radius

Days elapsed are banded into urgency tiers:

- **Critical**: 90 days or more
- **High**: 60-89 days
- **Medium**: 30-59 days
- **Normal**: under 30 days

## 3. Per-bicycle priority

Each bicycle receives priority points based on days elapsed and its urgency tier.

Where the data exists, a hazard score (`hazard_score`) and a likelihood that the bicycle is
still on site (`confidence`) can also be factored in; defaults are used when they are absent.

When only part of a cluster can be collected, the higher-priority bicycles are chosen first —
which by default means the oldest reports.

## 4. Generating collection alternatives per cluster

For each cluster, the following alternatives are generated:

- do not visit this cluster
- collect the single oldest bicycle
- collect the two oldest
- ...
- collect the entire cluster

The collect-everything alternative carries a completion bonus, which encourages the solver to
finish any cluster it has travelled to. Full collection is not forced, though, so a cluster can
be partially collected where vehicle capacity or another cluster's priority calls for it.

## 5. Joint optimization with OR-Tools

OR-Tools decides all of the following at once:

- which clusters to visit
- how many bicycles to collect at each
- the visit order from Start, through the selected clusters, to Storage

The objective function accounts for:

- vehicle travel distance
- the cost of on-site collection time
- a priority penalty for bicycles left uncollected

The constraints are:

- maximum vehicle load
- maximum operating time
- exactly one collection-quantity alternative per cluster
- the route starts at Start and ends at Storage

## 6. Output and visualization

A run reports:

- priority information for every cluster
- which clusters and bicycles were actually selected
- whether each cluster was collected fully or in part
- the optimal visit order
- total load collected and remaining capacity
- total travel distance
- estimated operating and collection time
- total priority captured

The map shows every bicycle's position, but rather than annotating each one individually, it
summarizes only the clusters that are actually visited — number to collect, bicycle codes,
urgency tier, and days elapsed.

## Tunable parameters

| Parameter | Meaning |
|---|---|
| `cluster_radius_m` | hotspot radius |
| `vehicle_capacity` | maximum vehicle load |
| `completion_bonus_ratio` | bonus for collecting a whole cluster |
| `max_route_minutes` | maximum operating time |
| `average_speed_kmh` | average vehicle speed |
| `priority_value_m_per_point` | weighting between report priority and travel distance |
| `service_cost_m_per_minute` | cost assigned to on-site collection time |
| `pickup_minutes` | estimated collection time per bicycle |

## Distance

The example uses haversine distance — straight lines between coordinates. In a real deployment,
replacing this with a road distance and duration matrix, from Kakao Mobility or similar, gives
accurate vehicle travel distance and time.
