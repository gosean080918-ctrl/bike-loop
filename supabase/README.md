# Supabase setup guide

These SQL files are the entire backend, apart from the `/optimize` route-optimization
server. Verified against the PostgreSQL 16 parser.

## Order of application

1. Create a new project at https://supabase.com (region: Northeast Asia recommended)
2. **Storage → New bucket**: name it `report-photos`, leave **Public unchecked**
3. In the **SQL Editor**, run the files in order:
   - `01_schema.sql` — PostGIS, the five tables, triggers
   - `02_rls.sql` — Row Level Security policies and Storage policies
   - `03_functions.sql` — duplicate-search RPC, map-bounds RPC, three statistics views
   - `04_road_and_inventory.sql` — road polylines on jobs, inventory, ID numbering
   - `05_profile_email.sql` — mirrors the reporter's email into `profiles`
   - `06_nationwide.sql` — province/district columns and nationwide ID numbers
   - `07_public_hardening.sql` — photo access limits and report flood protection
4. Promote an administrator (sign up in the app first, then run this in the SQL Editor):
   ```sql
   update public.profiles set role = 'admin' where id = '<that user's uuid>';
   ```

## Keys the app uses (Settings → API)

- `Project URL` and the `anon public` key go into the Flutter app — safe, because RLS,
  not secrecy, is what enforces authorization
- The `service_role` key must **never** be placed in the app

## Permission model

| Action | user | admin |
|---|---|---|
| Read reports (map) | yes | yes |
| Create a report | own name, `submitted` only | yes |
| Change report state (approve / reject / duplicate / assign) | no | yes |
| Collection jobs, visit order, inventory | no | yes |
| Upload a photo | own folder (`{uid}/...`) only | same |
| Change a profile's `role` | no (blocked at column level) | no — `service_role` only |

## Calling it from the app (supabase_flutter)

```dart
// Submit a report
await supabase.from('reports').insert({
  'reporter_id': supabase.auth.currentUser!.id,
  'photo_url': url, 'lat': lat, 'lng': lng,
  'condition': 'long_term', 'description': desc,
});

// Check for duplicates before submitting (30 m radius)
final dup = await supabase.rpc('find_nearby_reports',
    params: {'p_lat': lat, 'p_lng': lng, 'p_radius_m': 30});

// Fetch what is inside the current map bounds
final list = await supabase.rpc('reports_in_bounds', params: {
  'p_min_lat': sw.lat, 'p_min_lng': sw.lng,
  'p_max_lat': ne.lat, 'p_max_lng': ne.lng});

// Dashboard
final stats = await supabase.from('v_stats_daily').select().limit(30);
```

## condition / state codes

- `condition`: `long_term` = suspected long-abandoned, `damaged`, `obstruction`
  (blocking a footpath), `parts_missing`, `other`
- `bikes.state`: `storage`, `repair`, `donation`, `reuse`, `disposal`

## A note on the Korean text that remains

`06_nationwide.sql` still contains Korean province and district names, and
`04_road_and_inventory.sql` keeps a Korean fallback value. These are **data, not
comments**: they are compared against the address strings the Kakao API returns, so
translating them would break region matching. Everything else in this directory is
English.
