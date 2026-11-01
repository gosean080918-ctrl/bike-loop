# BIKE LOOP

**Report → review → optimized collection route → pickup → inventory → impact metrics.**
A full pipeline for clearing abandoned bicycles, built for Korean local governments.

> **LOOP means two things here**
> ① the **circular route** a collection vehicle drives — depot → stops → depot — which this
> project makes as short as possible, and ② the **loop of resources**: a bicycle headed for scrap
> is repaired, donated and ridden again.

---

> **🇰🇷 Service area: South Korea only.**
> BIKE LOOP runs **nationwide within South Korea** and does not work abroad. This is a deliberate
> constraint, not an unfinished feature.
>
> **Why:** Korean law restricts the export of national map data, so Google Maps cannot provide car
> navigation inside South Korea. Every geospatial feature here — map tiles, address lookup, place
> search and road routing — therefore runs on **Kakao**, whose coverage ends at the border. The app
> rejects out-of-country coordinates on purpose (`isInKorea()`), because Kakao returns blank tiles
> there. Supporting other countries would mean running a second provider in parallel and keeping
> both stacks alive, since Kakao remains mandatory for routing inside Korea.

---

## The problem

Abandoned bicycles pile up around schools, apartment blocks and tourist car parks — especially
after graduation and moving season. They occupy the racks people actually need, fall across
footpaths, and are eventually scrapped even when a repair would have kept them on the road.

Clearing them is harder than it sounds:

| How it is done today | What goes wrong |
|---|---|
| Phone calls and complaint boards | "Near the elementary school" is not a location; staff hunt for the bike |
| Several people report the same bicycle | Nobody can tell one bike from three; crews are dispatched twice |
| Collection in the order reports arrive | A poor visiting order adds tens of kilometres to a single day |
| Bikes go into a warehouse | With no record of what is there or what is repairable, they are scrapped |
| No measurement | Nobody can show the programme is working |

**BIKE LOOP** addresses each: exact coordinates and addresses on intake, automatic duplicate
detection, a solver that computes the visiting order, per-bicycle tracking with generated ID
numbers, and a dashboard that reports how many bikes were brought back into use.

---

## Architecture

```
[Flutter app]  ──  [Supabase]                 data · photos · auth · permissions
      │             PostgreSQL + PostGIS
      │             + Auth + Storage + RLS
      │
      ├─────────  [FastAPI on Cloud Run]      route optimization only
      │             Python + Google OR-Tools
      │
      └─────────  [Kakao]                     maps · geocoding · road routing
```

**Design rule: no server for CRUD.** Reads and writes go straight from the app to Supabase, and
authorization is enforced by Row Level Security inside the database rather than by an API layer.
A server exists only for the one thing that genuinely needs Python — the optimizer. That keeps the
backend to a handful of files and near-zero running cost (Cloud Run scales to zero when idle).

---

## Repository layout

```
app/                    Flutter application
  lib/const/            models and constants (regions.dart = 17 provincial depots)
  lib/service/          auth · report · admin · location · settings · api client
  lib/ui/route|tab/     screens
server/                 FastAPI (/optimize · /address · /search)
  engine.py             hotspot clustering + urgency tiers + CVRP
  auth.py               Supabase token verification + per-user rate limiting
supabase/               schema · RLS · RPC · migrations (apply 01 → 07 in order)
analysis-server/        proof-of-concept validated on NYC 311 open data
DEVLOG.md               engineering log — decisions, incidents, what broke and why
```

---

## Core logic

**Route optimization.** Google OR-Tools solves a capacitated vehicle routing problem under real
constraints: vehicle capacity, available working hours, depot and return point, and sites the
administrator marked as mandatory. The combinatorics are the point — five stops have 120 possible
orders, ten have 362,880, fifteen have 87 billion. Hand-planning loses distance every single day.

**Clustering.** Bicycles within 30 m are treated as one stop, because a crew that parks once can
load all of them.

**Urgency tiers.** Priority rises with neglect: Critical (90+ days), High (60+), Medium (30+),
Normal. This stops long-standing reports from being perpetually outranked by fresh ones.

**Duplicate detection.** Before a report is saved, PostGIS `ST_DWithin` measures true ground
distance to existing reports within 30 m — coordinate subtraction does not give metres on a sphere.

**ID numbering.** `{province}_{district}_{YYYYMMDD}_{sequence}`, assigned by a database trigger so
two staff registering simultaneously can never collide.

**Region validation.** If the depot and the selected pickups are in different provinces, the app
blocks route generation and offers to re-anchor the depot — a guard added after a real incident
where a Jeju depot was paired with a Seoul pickup, producing a 69 km route.

---

## Validation on real data

There is no historical abandoned-bicycle dataset for Jeju, so the method was tested first against
**New York City's 311 derelict bicycle reports — 2,930 records from 2020–2021**:

- **Hotspot analysis** (KDE + Getis-Ord Gi\*) confirmed that reports genuinely cluster; Port Morris
  in the Bronx ranked highest (z = 4.04)
- **CVRP** planned three trucks collecting 180 bicycles in 82.1 km total
- **Seasonality** showed clear monthly peaks, consistent with the graduation-and-moving hypothesis

Two lessons went directly into production code: split a site across visits when it exceeds vehicle
capacity, and carry the remainder to the next run instead of failing. Details in
`analysis-server/poc_nyc311/RESULTS.md`.

---

## Security model

This repository is public. **Every key visible in the source is a client-side key that is meant to
be public**, and the keys that would actually cost money are not here — not in the working tree and
not in the commit history.

| Key | Location | Why it is safe / what it risks |
|---|---|---|
| Supabase publishable (anon) | app source | Authorization is enforced by RLS in the database, not by secrecy |
| Kakao **JavaScript** key | app source | Only works from registered domains |
| Kakao **REST** key | server `.env` only (git-ignored) | Would allow billed quota abuse — never committed |
| Supabase `service_role` | not used at all | Would grant full database access — designed out |

**The optimization server rejects anonymous callers.** It verifies the caller's Supabase access
token against Supabase itself, caches the result briefly, and rate-limits per user
(`server/auth.py`). Knowing the server URL is not enough to spend our Kakao quota:

```bash
curl "https://<server>/search?q=jeju"
# {"detail":"Login required (missing token)"}
```

Photos are readable only by their uploader and administrators, and a trigger blocks report flooding
(more than 20 submissions in five minutes).

---

## Running it yourself

Cloning this repository will not connect you to our Supabase project or server — permissions block
that by design. To run your own instance:

**1. Database**

Create a Supabase project, then run the files in `supabase/` **in order, 01 → 07**, in the SQL
editor. (07 is the public-launch hardening pass: photo access limits and flood protection.)

**2. Server** (optional — a deployed instance already exists)

```bash
cd server
pip install -r requirements.txt
cp .env.example .env      # fill in the Kakao REST key and Supabase URL/anon key
uvicorn main:app --reload
```

**3. App**

```bash
cd app
flutter pub get
flutter run                       # development
flutter build apk --release       # Android release build
```

Point `app/lib/const/value/constants.dart` at your own Supabase project, Kakao JavaScript key and
server URL.

Grant administrator rights with SQL:

```sql
update profiles set role = 'admin' where id = '<uuid>';
```

---

## Status

All ten milestones of the MVP are implemented and verified on physical devices. Nationwide coverage
shipped in August 2026; the public-launch security pass shipped in September 2026.

**Next:** multi-vehicle routing · real road distances inside the optimizer (currently used for
display only) · completion photos · a hotspot prediction model · per-municipality administrator
accounts.

---

## Credits

Built by **한정규 (Jeong-Kyu Han)**. Optimization engine adapted from a framework by
**이강혁 (Kang-Hyuk Lee)**, used with permission.

## License

MIT — see [LICENSE](LICENSE). Brand assets (the BIKE LOOP name and logo) and operational data are
not covered by the licence.
