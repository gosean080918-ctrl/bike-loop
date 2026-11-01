# BIKE LOOP app — setup guide

The app talks to Supabase directly and uses Kakao Maps. The backend is applied separately;
see `../supabase/README.md`.

## 1. Create the Flutter platform folders

```bash
cd BikeReclaim/app
flutter create --org com.bikereclaim --project-name bike_reclaim .
flutter pub get
```

## 2. Fill in the keys — `lib/const/value/constants.dart`

- `kSupabaseUrl` — your Supabase project URL
- `kSupabaseAnonKey` — Supabase dashboard > Settings > API Keys: the `anon public` key
  (`eyJ...`) or the publishable key (`sb_publishable_...`)
- `kKakaoJsKey` — the JavaScript key from Kakao Developers
  (developers.kakao.com > create an app > register the Web platform, including
  `http://localhost`, and turn on Kakao Map)
- `kServerBase` — the optimization server's URL

All three of these are client-side keys that are meant to be public. The Kakao **REST** key and
the Supabase `service_role` key must never appear here — see the security section of the root
`README.md`.

## 3. Platform permissions

**android/app/src/main/AndroidManifest.xml**, inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.CAMERA" />
```

Add `android:usesCleartextTraffic="true"` to `<application>` (required by
`kakao_map_plugin`), and check that `minSdkVersion` is 21 or higher.

**ios/Runner/Info.plist**:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location access is needed to record where an abandoned bicycle is.</string>
<key>NSCameraUsageDescription</key>
<string>Camera access is needed to photograph an abandoned bicycle.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Photo library access is needed to choose an existing photo.</string>
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSAllowsArbitraryLoads</key><true/>
  <key>NSAllowsArbitraryLoadsInWebContent</key><true/>
</dict>
<key>io.flutter.embedded_views_preview</key><true/>
```

## 4. Run it

```bash
flutter run                       # development
flutter build apk --release       # Android release build
```

## Email confirmation (development convenience)

Supabase requires email confirmation on sign-up by default, which is awkward while developing.
To turn it off: dashboard > Authentication > Sign In / Up > Email > disable "Confirm email".
Turn it back on before a public launch.

## Creating an administrator

Sign up in the app first, then run this in the SQL Editor:

```sql
update public.profiles set role = 'admin'
where id = (select id from auth.users where email = '<admin email>');
```

## Implementation status

| Feature | Status |
|---|---|
| AUTH-01/02 splash, sign-in and sign-up | done |
| RPT-01 take and upload a photo | done |
| RPT-02 automatic GPS plus adjusting the location on the map | done (centre-pin style) |
| RPT-03 pick one of five condition types, plus a description | done |
| RPT-04 submit, with a 30 m duplicate-check dialog | done |
| RPT-05 map distribution with clustering | done |
| RPT-06 the user's own report history and status | done |
| ADM-01/02 review: approve, reject, mark duplicate | done |
| ADM-03/04 generate an optimized collection route | done |
| ADM-05/06/07 navigation, completing stops, inventory registration | done |
| ADM-08 inventory management | done |
| ADM-09 dashboard | done |
| ADM-10 report detail view | done |
| Nationwide coverage: region filter, 17 regional depots | done |

Verified on physical Android devices.
