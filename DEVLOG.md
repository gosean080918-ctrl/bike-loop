# Engineering log

This is the project's single source of truth. It records what was built, what was decided and
why, and what broke along the way. Read this file and you should be able to pick the project up
without reading anything else.

Maintained by Gosean.

---

## Summary

A resident or student reports an abandoned bicycle with a photo and a location. An
administrator approves, rejects or marks it as a duplicate. The system generates an optimized
collection route that respects the vehicle's real constraints. After collection, each bicycle
is registered as inventory and tracked, and a dashboard reports output and the effect of the
optimization.

The core goal is to unify report data spatially, then compute collection priority and vehicle
routing automatically.

Problems it addresses: unstructured handling of reports, duplicate reports, unnecessary travel
distance, no visibility into progress, and no way to prepare for the surge at graduation and
moving season.

The project was conceived as an app and a research paper together. Methods were validated first
on New York City 311 open data, then applied to Korean data.

---

## 1. Technology stack

**Principle: no server for CRUD.** The app talks to Supabase directly by default.

| Layer | Choice | Notes |
|---|---|---|
| Client | Flutter + `supabase_flutter`, Riverpod for state | Sign-in, report CRUD and photo upload all go through the Supabase SDK. One app for both roles, branching on `profiles.role`. |
| Database, auth, files | Supabase — PostgreSQL + PostGIS + Auth + Storage | Authorization is enforced by RLS at the database level, so no separate API auth layer is needed. |
| Duplicate search | A single PostgreSQL function (RPC) | `ST_DWithin` radius plus a status filter. No server; the app calls `supabase.rpc()`. |
| Optimization server | A minimal FastAPI service, one real endpoint (`POST /optimize`) | Runs the OR-Tools CVRP — the only part that genuinely needs Python. Constraints: capacity, working time, priority, mandatory stops, start and return points. |
| Travel time | Haversine approximation inside the solver | Kakao's car routing matrix is used for road display; folding it into the solver is still open. |
| Map display | Kakao Maps (`kakao_map_plugin`, JavaScript key) | |
| Navigation | Hand off to the Kakao Map app by URL | No key required. |
| Place search | Kakao Local API, proxied through the server | |

Shape of the system: `[Flutter app] <-> [Supabase] + [one FastAPI /optimize]`. The server was
deliberately kept to a handful of files.

### Security rules — non-negotiable

- Keys that may ship inside the app: the Supabase anon key (safe because RLS enforces access)
  and the Kakao Maps JavaScript key (restricted to registered domains).
- Forbidden in the app: the Supabase `service_role` key and the Kakao REST key. Those live in
  server environment variables only.
- Every write is validated by an RLS policy — a report can only be created in one's own name,
  only an admin can approve.

---

## 2. User roles

- **user** — students and residents. File reports with a photo and location, check status, see
  the distribution of abandoned bicycles on the map.
- **admin** — the operations team. Review reports (approve, reject, duplicate), select stops,
  generate routes, collect on site, register completion photos, manage inventory.

An earlier design had a third "collector" role; it was folded into admin. Roles live in
`profiles.role` and are enforced by RLS.

---

## 3. Feature list

`[x]` done · `[~]` in progress · `[ ]` not started

### Common / authentication

- `[x]` **AUTH-01** splash and initialization
- `[x]` **AUTH-02** sign-up and sign-in
- `[x]` **AUTH-03** role branching — four admin tabs appear after promotion

### Reporter features

- `[x]` **RPT-01** take and upload a photo
- `[x]` **RPT-02** automatic GPS plus a centre-pin map adjustment
- `[x]` **RPT-03** five condition types as choice chips, plus a description
- `[x]` **RPT-04** submit (Storage + insert, under RLS), with a 30 m duplicate dialog
- `[x]` **RPT-05** distribution on the map
- `[x]` **RPT-06** the user's own report history, with signed-URL thumbnails and status chips

### Administrator features

- `[x]` **ADM-01** list new reports with photo and description for review
- `[x]` **ADM-02** approve / reject / mark duplicate, choosing the original from nearby reports
- `[x]` **ADM-03** select collection targets by checkbox
- `[x]` **ADM-04** call `/optimize`, save the job and its stops
- `[x]` **ADM-05** show the visit order, hand off to Kakao Map for navigation
- `[x]` **ADM-06** mark each stop collected
- `[x]` **ADM-07** register a collected bicycle into inventory automatically
- `[x]` **ADM-08** inventory tab — ID number, photo, report location, report and collection
  dates, storage location, state; filter by state, search by ID number, change state or
  location from a bottom sheet
- `[x]` **ADM-09** dashboard — four headline metrics, reuse rate with a ratio bar, inventory
  status, report status, type distribution, operating efficiency
- `[x]` **ADM-10** report detail view
- `[x]` **NAT-01** nationwide coverage

### Backend

- `[x]` **BE-01** Supabase schema and RLS
- `[x]` **BE-02** duplicate-search RPC (`find_nearby_reports`) and map-bounds RPC
- `[x]` **BE-03** FastAPI `/optimize`
- `[x]` **BE-04** three statistics views
- `[x]` **BE-05** road routes — Kakao Mobility multi-waypoint directions, with a haversine
  fallback when the key is absent
- `[x]` **BE-07** ported the optimization framework — hotspot clustering, urgency tiers,
  partial-collection alternatives, joint optimization
- `[ ]` **BE-06** connect a hotspot prediction model

### Analysis / research track

- `[x]` **ANL-06** the NYC 311 validation pipeline (`analysis-server/poc_nyc311/`)
- `[ ]` **ANL-01** port hotspot analysis (KDE + Getis-Ord Gi\*) into production
- `[ ]` **ANL-02** time-series forecasting with a graduation/moving-season event regressor
- `[ ]` **ANL-03** port the CVRP work, carrying over the proof-of-concept lessons

### Infrastructure

- `[x]` **INF-01** Supabase project, with the `report-photos` bucket (10 MB, `image/*`)
- `[x]` **INF-02** server deployed on Google Cloud Run, region `asia-northeast3` (Seoul)
- `[x]` **INF-03** Flutter key configuration, emulator build and run
- `[x]` **INF-04** Git repository. `.gitignore` blocks `server/.env`, which holds the Kakao
  REST key — never force-commit it. `server/.env.example` documents the variables instead.

---

## 4. Data model

```
profiles                       -- 1:1 with Supabase auth.users
  id uuid PK (references auth.users), role text ('user' | 'admin'),
  display_name, email, created_at

reports
  id uuid PK, reporter_id uuid FK,
  photo_url text, geom geometry(Point,4326), address text,
  region_1 text, region_2 text,
  condition text   -- long_term | damaged | obstruction | parts_missing | other
  description text,
  status text      -- submitted -> approved | rejected | duplicate
                   --           -> scheduled -> collected
  duplicate_of uuid FK(reports),   -- the original, when marked duplicate
  priority int DEFAULT 0,
  reported_at, reviewed_at, collected_at, job_id FK

collection_jobs                -- a collection run (ADM-03 to 06)
  id uuid PK, admin_id FK, vehicle_capacity int, depot_geom, return_geom,
  work_minutes int, status ('planned' | 'in_progress' | 'done'),
  total_distance_m, total_duration_s, route_polyline, created_at

job_stops                      -- visit order, as solved by OR-Tools
  job_id FK, seq int, report_id FK, eta, done bool, done_photo_url

bikes                          -- inventory (ADM-07/08)
  id uuid PK, report_id FK, collected_at, code text, storage_location text,
  state text ('storage' | 'repair' | 'donation' | 'reuse' | 'disposal'),
  state_updated_at, note
```

Statistics are computed from views and aggregate queries: daily reports and collections,
before-and-after distance comparisons, and so on.

**What PostGIS is for**

- Duplicate detection: `ST_DWithin(geom, <new report>, 30)` plus a time window and status filter
- Map distribution: bounding-box queries
- Future hotspots: grid aggregation then Gi\*, following the proof-of-concept method

---

## 5. Division of labour between map and solver

- **What to visit, in what order** — FastAPI and the OR-Tools CVRP, under capacity, working
  time, priority, mandatory-stop and start/return constraints.
- **The distance and duration matrix** — haversine today; Kakao's routing API for road display,
  and the intended replacement inside the solver.
- **Actual turn-by-turn navigation** — handed off to the Kakao Map app, not in-app.
- **Map rendering** — Kakao Maps with the JavaScript key.

Two lessons from the proof of concept, both now in production code:

- When a stop's demand exceeds vehicle capacity, split it across visits.
- When total demand exceeds total capacity, carry the remainder over through a demand-weighted
  penalty disjunction rather than failing.

---

## 6. Definition of done for the MVP

All ten steps had to work end to end:

1. a user files a report with a photo and location
2. the user can see its status
3. an administrator approves, rejects or marks it duplicate
4. the administrator selects several targets
5. the system generates an optimized route under the vehicle's constraints
6. the administrator collects in the given order
7. results and completion photos are recorded
8. collected bicycles are registered as inventory
9. inventory storage and processing state are managed
10. the dashboard reports output and the effect of the optimization

All ten are implemented and verified on physical devices.

---

## 7. Repository layout

```
BikeReclaim/
  DEVLOG.md                      <- this file
  README.md
  app/                           <- Flutter app
    lib/
      const/{model,value}/  service/  state_management/
      ui/{route,tab,component,dialog}/  utils/
  server/                        <- minimal FastAPI
  supabase/                      <- schema SQL, RLS policies, RPC functions
  analysis-server/poc_nyc311/    <- the validation proof of concept
  docs/                          <- illustrated product guide (HTML)
```

---

## 8. Roadmap

- `[x]` **Stage 0 — proof of concept**: validate KDE, Getis-Ord and VRP on NYC 311
- `[x]` **Stage 1 — reporter MVP**: sign-up, report, map, history, end to end
- `[x]` **Stage 2 — backend**: Supabase applied (5 tables, 3 views, 2 RPCs, RLS)
- `[x]` **Stage 3 — administrator**: review, approve, route, collect, inventory, end to end
- `[x]` **Stage 4 — inventory and dashboard**: all ten MVP steps implemented
- `[ ]` **Stage 5 — prediction**: connect the hotspot and time-series models
- `[ ]` **Stage 6 — write-up**: method and performance validation report

---

## 9. Cold-start strategy

With little data at launch:

1. **Substitute open data** — NYC 311 (validated), plus Korean municipal open data
2. **Rule-based fallback** — heuristics around graduation season and dormitory proximity until
   real data accumulates
3. **Encourage reporting** — rewards and public status to accelerate early collection
4. Once report volume is sufficient, transition naturally to statistical and time-series models

---

## 10. Risks

- Securing real local data (cold start) — cushioned by open data and rules
- Kakao API policy, pricing and quota changes — check the console before each integration
- The Kakao routing matrix costs N² calls for N stops — needs caching, or the haversine
  approximation as a fallback
- Secret-key exposure — everything goes through the FastAPI server and environment variables
- GPS inaccuracy — manual correction on the map, included in the MVP
- Privacy: people and licence plates visible in photos — guidance on upload, blurring if needed
- Wrong duplicate judgements — the radius and time heuristic only assists; the administrator
  decides

---

## 11. Decision log

**2026-07-14 — Kakao Maps, not Google.** Korean law restricts the export of national map data,
so Google Maps cannot provide car navigation inside Korea. This single constraint determines the
entire geospatial stack.

**2026-07-14 — Heavy computation goes to a Python server,** not the client.

**2026-07-15 — Firebase → Supabase + Python FastAPI.** Spatial queries are central to this
product (duplicate detection, distribution, hotspots), which makes PostGIS the right foundation;
and once routing and inventory logic grew, a real backend beat a document store.

**2026-07-15 — Three roles collapsed to two.** The administrator reviews, collects and manages
inventory.

**2026-07-15 — Condition input changed** from sliders (lock, damage, dust) to one of five
explicit types plus a free-text description.

**2026-07-15 — Navigation simplified** to handing off to the Kakao Map app rather than
implementing turn-by-turn in the app. The Kakao routing API is used for the distance and
duration matrix instead.

**2026-07-15 — Inventory management is in MVP scope** (storage, repair, donation, reuse,
disposal).

**2026-07-15 — Stack minimized.** The general-purpose API layer was removed: the app talks to
Supabase directly with RLS for authorization, duplicate search is a PostGIS RPC, and the server
keeps exactly one endpoint. Rationale: MVP speed, simplicity, and near-zero running cost.

---

## 12. Work log

Newest first.

**2026-11-01 — Everything converted to English.** README rewritten, every comment in Dart,
Python and SQL translated, this log replacing the Korean `blueprint.txt`. The Korean strings that
remain are data, not prose: the place names in `regions.dart`, `romanize.dart` and
`06_nationwide.sql` are matched against the address strings Kakao returns, so translating them
would break region matching. They are transliterated at display time instead.

**2026-10-26 — Every map in the app went blank. Cause: the Kakao app had vanished.**
Symptoms: the map tab, the location picker and the route map were all white, while data such as
the report list loaded fine — so it was not the network. The first suspicion was the WebView and
its layout, and relayout hardening was added to `map_tab`; it changed nothing.

The real cause: the Kakao app that owned the JavaScript key compiled into the build no longer
existed in the console account. Either deleted, or owned by a different Kakao account. An invalid
key makes the Maps SDK refuse to load.

Fix: create a new Kakao app, swap the JavaScript key, register `http://localhost` as a JS SDK
domain, and switch Kakao Map on under the product settings.

Notes worth keeping: the new console moved platform registration to *App > Platform keys >
register a domain per key*, and the Kakao Map settings page is at `/product/kakao-map`
(`/product/map` is a 404).

**Lesson:** when a map does not render, check that the app still exists in the console *before*
suspecting the WebView. Whether a key actually made it into a build can be confirmed by string
-searching `libapp.so` inside the APK, which is a zip.

**2026-09-15 — Hardening for a public launch (SEC-01).** The decision was to open the app to
the public, with anything dangerous removed first. Three holes were closed.

1. **An unauthenticated server — the worst of them.** Cloud Run was open to all users, so
   anyone who knew the repository or the app's server URL could call `/address` and `/search`
   and burn the client's Kakao REST quota, and their bill.
   Fix: `server/auth.py` verifies the Supabase access token the app sends by calling
   `/auth/v1/user`, which works regardless of the project's token signing scheme. Results are
   cached for five minutes and each user is limited to 60 calls a minute. Only `/health` stays
   public, and missing configuration fails closed with a 500 rather than letting everyone
   through. On the client, `service/api_client.dart` attaches the token to every server call,
   and the report, settings, location-picker and admin services were all routed through it,
   with messages for 401 and 429.
2. **Photo visibility.** Any signed-in user could read anyone's report photos. Fixed in
   `07_public_hardening.sql`: uploader and administrators only.
3. **Report flooding.** A trigger blocks more than 20 reports from one user in five minutes.

All three have to land together — the SQL, a server redeploy with `SUPABASE_URL` and
`SUPABASE_ANON_KEY`, and an app rebuild. Miss any one and either the app cannot reach the
server or the server stays open.

**2026-08-12 — Field feedback on nationwide coverage.** Three fixes.

1. *The map tab would not move to my location.* Calling `setCenter` before the Kakao WebView is
   ready is silently ignored. Fix: retry every 300 ms up to ten times until the controller
   exists; move roughly to `getLastKnownPosition()` first so it feels fast; give
   `getCurrentPosition()` an 8-second limit with the last known position as fallback; and add a
   "my location" button as a manual path.
2. *Changing the start and return point needed its own screen.* A one-line link could not
   present 17 regional offices, and addresses were truncated. New
   `ui/route/depot_picker_screen.dart`: the list of offices, search, and "pick on the map" for
   a depot of one's own.
3. **A Jeju depot was being paired with a Seoul pickup.** `_checkRegions()` now warns when the
   selected reports span regions, and when the depot's region differs from the targets' it
   offers three choices: switch the depot to that region's office and continue, keep it, or
   cancel. This came from a real case — a Jeju start point with a pickup in Gangdong-gu, Seoul,
   producing a 69.2 km route.

**2026-08-12 — Nationwide coverage (NAT-01).** The Jeju-only limit was lifted. Three decisions:
a region *filter* rather than per-region admin accounts; depots defaulting to the 17 regional
offices with manual override; and ID numbers of the form
`{province}_{district}_{date}_{sequence}`.

New: `app/lib/const/value/regions.dart` (office address and coordinates for all 17 regions,
plus `regionOf` / `districtOf` / `depotOf` / `nearestRegion`) and `supabase/06_nationwide.sql`
(`norm_region1` and `short_region1`, `reports.region_1/2` with a trigger and backfill, and
`gen_bike_code` redefined with existing codes re-issued).

Changed: `constants.dart` (`isInJeju` became `isInKorea`, national centre coordinates, map
levels 12 nationwide and 4 near), `report_tab` (GPS in `initState`, `_fillAddress`, a region
badge, a "my location" button), `map_tab` (move to my location through the controller),
`location_picker` (nationwide, with the initial zoom branching), `settings_service`
(`resolveAddress` made public, to resolve office coordinates) and `admin_jobs_tab` (region
dropdown, `_filtered`, `_useRegionDepot`).

Also: camera, photo and location usage strings were added to the iOS `Info.plist` — without
them iOS kills the app instantly and App Store review rejects it — and the display name was set
to BIKE LOOP.

*Known limitation:* in a large province such as Gyeonggi or Gyeongbuk, anchoring to a single
provincial office makes the round trip long enough that a route may be refused or run out of
working time. The administrator should re-anchor to a nearer depot.

**2026-08-12 — ADM-10, the report detail view.** Asked for directly: tapping a review-tab tile
should show the photo and all the text enlarged on one screen. New
`ui/route/report_detail_screen.dart` — a 4:3 photo that opens fullscreen in an
`InteractiveViewer` with pinch and double-tap zoom, then type, status chip, report time,
address, coordinates and the full untruncated description.

Structure worth noting: the detail screen returns only an action *string* via `pop`, and the
review tab's existing `_act` / `_duplicate` handlers do the work. No duplicated logic.

Same day, a build error of my own making: `admin_dashboard_tab` referenced `AppColors.blueBg`
and `blueFg`, which do not exist in theme v2. Replaced with `primarySoft` and `primary`.

**2026-08-12 — Showing the reporter's email.** The decision was to show the full email and drop
the report ID entirely. New `supabase/05_profile_email.sql`: a `profiles.email` column, a
backfill of existing users, a replacement `handle_new_user` trigger, and a trigger that syncs
when `auth.users.email` changes. The detail screen gained a reporter card — display name and
email, tap to copy, a button for `mailto` — and the identifier card was removed.

Privacy reasoning: an email address is personal data, but this is use *within* the purpose for
which it was collected (processing the report), and the `profiles_select` RLS policy restricts
it to the person themselves and administrators. For a real deployment the privacy policy must
state that administrators can see it. Screenshots and presentation material must mask it.

**2026-08-06 — Mandatory stops plus road routes, verified on device.**

1. *Mandatory stops.* The app now sends `required=true` for stops the admin picked, the
   optimizer turns those into `required_nodes`, and the engine adds a constraint that exactly
   one alternative covering the required node is active. This fixed routes being refused
   outright: previously the engine's own cost-benefit judgement returned `collected=0` — a
   recent report scores Normal tier with no bonus, against a 20-60 km round trip. Capacity and
   time constraints still apply, so a 422 with a readable message (adjust capacity or working
   time) is now the only failure mode.
   The engine's cost-benefit logic is deliberately left intact, for a future feature that
   recommends stops the admin did *not* select.
2. *Road routes.* `KAKAO_MOBILITY_KEY` turned out to be the same Kakao REST key, with no
   separate registration. Confirmed on a device following real provincial roads.
3. *UX.* A modal while the route is being computed, a light-to-dark green gradient per leg, and
   a legend. The server splits the response's sections into segments, stored in
   `route_polyline`.
4. *GCP permissions.* Source-based deployment needs Owner-level rights (Artifact Registry,
   Cloud Build, `serviceaccounts.actAs`). A permission invitation only takes effect once it is
   accepted by email.

**2026-08-06 — ADM-09 dashboard complete; all ten MVP steps implemented.** The statistics tab
covers the headline metrics, reuse rate, distribution bars for inventory, reports and types, and
operating efficiency, aggregated in `admin_service.fetchDashboard()`. Filing a report moved to a
FAB on the map tab to keep the tab count at five. The two numbers that make the case best: the
reuse rate, and travel distance per bicycle collected.

**2026-08-06 — Inventory dashboard and layout fixes.** A "total held" figure plus per-state
counts at the top of the inventory tab, computed over everything regardless of the filter.
Overlapping text in the cards was fixed by wrapping the ID number and collection date and
stacking the state chip and delete button vertically.

**2026-08-06 — Delete, carefully.** Individual collection jobs can be deleted: `job_stops`
cascade, reports still `scheduled` revert to `approved`, and already-collected reports are left
alone. Deleting an inventory item removes only the `bikes` row and preserves the report as
collected — the agreed principle being that history is kept. Per-item deletion only; no
delete-all, to prevent mistakes.

**2026-08-02 — Server deployed to Cloud Run,** on the client's own GCP account after being
invited as Editor and Cloud Run Admin. `/health` OK, and `kServerBase` switched to the Cloud Run
URL, so route generation, reverse geocoding and place search now work on a real device over
mobile data with no local server.
Learned: the Editor role alone cannot call `setIamPolicy`, so making a service public takes
either the owner doing it in the console or Cloud Run Admin.

**2026-08-02 — Branding settled.** The name BIKE LOOP, a logo combining a cycle arrow with a
bicycle, and a Varela Round wordmark in `#05A1A2`, wrapped in a `BrandWordmark` widget and
applied to the app bar, splash, sign-in screen and Android label.

**2026-07-21 — Ported the optimization framework; road routes; inventory tab; GPS removed.**

1. `server/engine.py` — the original turned into a server module: visualization and samples
   stripped, a global-variable bug in `build_pickup_options` fixed, numpy dropped, and callbacks
   forced to integers. **Returning a float from an OR-Tools callback fails silently** rather
   than raising, which cost real debugging time. `optimizer.py` was rewritten around `OPT_*`
   environment variables, deriving urgency from the report date. Five tests pass.
2. Road routes: the server's `road_path` calls Kakao Mobility with multiple waypoints behind an
   environment-variable gate, stores the result in `collection_jobs.route_polyline`, and the
   route map draws it as a solid line.
3. The inventory tab (ADM-08), with `bikes.code` and `storage_location`.
4. Automatic GPS tagging on reports was removed by decision of the meeting — location was to be
   set only by map or search. *(This was reversed on 2026-08-12 with the race-condition guard
   that made it safe.)*

**2026-07-19 — Service-area limit and depot settings.** Locations outside the service area were
blocked from search, confirmation and reporting through a bounding-box check. The default depot
was set and resolved to coordinates through `/search`, then cached. The jobs tab gained a UI for
changing the start and return point, reusing the map picker and persisting through
`SharedPreferences`. `/optimize` now receives `return_to`, saved on the job.
Also: five pin colours by type with a legend on the map tab, and always-visible address labels
on route pins.

**2026-07-19 — Blank-map incident, resolved.** The cause was an automatic update to the
emulator's Android System WebView, which broke the Kakao Maps page. The remedy was
`adb uninstall com.google.android.webview` to restore the factory version, scripted into the dev
launcher since it has to run on every boot.

Three things were settled while chasing it:

- Setting `baseUrl` to `localhost` actively blocks the main Maps script. Do not use it.
- The map tab's clusterer risks a load race; plain markers were kept instead.
- Release runs include `--no-enable-impeller`.

On physical devices this problem never existed.

**2026-07-17 — Place search on the location picker.** `GET /search` proxies Kakao's keyword
search; the screen gained a search bar, a result list and move-to-selection. The route map
switched to the mockup's SVG data-URI pins with a dashed path.

**2026-07-17 — Design v2.** Tokens were extracted from a four-screen mockup — ink `#17261D`,
background `#F7F9F7`, pill chips, shadowed cards, badges in orange `#FFF3E4` and green
`#E9F3ED`, CTAs at radius 18 with a green shadow — and `app_theme.dart` was rewritten around
them, then applied to the report screen, the history screen and the job cards.

**2026-07-17 — Stage 3 end to end.** Report, approve, `/optimize` on a local uvicorn, route
card, mark collected, inventory registered. Bugs fixed along the way: the GPS race condition
overwriting a map-confirmed location, and report deletion added.

**2026-07-17 — Stage 3 written.** Admin tab branching in `home_screen`, `admin_service` (review,
job creation calling `/optimize` and saving `job_stops`, completion and inventory upsert),
`admin_review_tab` and `admin_jobs_tab`.

**2026-07-17 — BE-03 complete.** FastAPI `/optimize` in seven files, carrying the
proof-of-concept lessons (visit splitting, carry-over, mandatory stops, working time). Three
tests pass.

**2026-07-17 — First run on a device.** Sign-up, photo upload, report submission and the history
list all worked; Kakao Maps rendered. Stage 1 declared complete.
One environment note: a Korean character in the project path broke the build, so the parent
folder was renamed.

**2026-07-15 — Flutter code moved to Supabase.** `firebase_*` out, `supabase_flutter` in. RPT-02
became `LocationPickerScreen`, RPT-03 was rewritten around the five types plus a description, a
30 m duplicate dialog was added before submission, and `SignedPhoto` was introduced for the
private bucket.

**2026-07-15 — Stage 2 SQL applied.** `01_schema.sql` (five tables and triggers), `02_rls.sql`
(role policies and Storage), `03_functions.sql` (duplicate-search and map-bounds RPCs, three
statistics views). Verified against the PostgreSQL 16 parser, then applied to a new project
along with the `report-photos` bucket.

**2026-07-14 — Stage 0 proof of concept complete.** 2,930 NYC 311 derelict-bicycle records from
2020-01 to 2021-09. KDE and Getis-Ord Gi\* hotspots, with Port Morris in the Bronx ranking
highest at z = 4.04; an OR-Tools CVRP planning three vehicles of capacity 60 to collect 180
bicycles in 82.1 km; and clear monthly seasonality. Code, data and results in
`analysis-server/poc_nyc311/`.
Lessons: carry-over through disjunctions is mandatory when total demand exceeds total capacity,
and oversized stops must be split across visits.

**2026-07-14 — Project started.** Architecture document and this log created.
