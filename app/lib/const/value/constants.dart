/// Application-wide constants.
///
/// [Security rule — see the engineering log]
/// Keys that may live here: the Supabase anon key (RLS enforces access) and the
/// Kakao Maps JS key (restricted to registered domains). The service_role key and the
/// Kakao REST key must never appear here.
library;

/// Supabase (project: bikereclaim1, Seoul)
const String kSupabaseUrl = 'https://xpkifseyiphyvoppcsui.supabase.co';

/// Publishable key (anon role; safe to ship because RLS enforces access)
const String kSupabaseAnonKey = 'sb_publishable_JNTxRVuSMHQV1-aoL7tOLg_gc6e8Cn-';

/// Kakao Maps JavaScript key (app: Bike Loop, ID 1622635, reissued 2026-10-26)
/// NOTE: the previous app (ID 1514725) vanished from the Kakao console, and every map
///   in the app went blank. A new app was created and the key replaced. The map only
///   loads if the Web platform (http://localhost) is registered and Kakao Map is enabled.
const String kKakaoJsKey = 'f143629fbc328db1b57a03365760a430';

/// Name of the photo bucket
const String kPhotoBucket = 'report-photos';

/// Backend server, deployed on Google Cloud Run (2026-08-02)
/// Project: bikeloop-504502, region asia-northeast3 (Seoul)
/// To redeploy, run this from the server/ directory:
///   gcloud run deploy bikeloop-server --source . --region asia-northeast3 ...
/// NOTE: when developing against a local server, swap in the commented line below
///   (on the Android emulator, 10.0.2.2 is the host machine's localhost)
const String kServerBase =
    'https://bikeloop-server-775952432199.asia-northeast3.run.app';
// const String kServerBase = 'http://10.0.2.2:8000'; // local development
const String kOptimizeUrl = '$kServerBase/optimize';
const String kAddressUrl = '$kServerBase/address';
const String kSearchUrl = '$kServerBase/search';

/// English build: the UI is in English.
/// Features and service area are unchanged — nationwide within South Korea.
/// Korean place names returned by the API are transliterated for display (utils/romanize.dart).

/// Default map centre: the middle of South Korea (the service covers the whole country)
/// The map opens on the GPS position when one is available, and on this point otherwise.
const double kDefaultLat = 36.3400;
const double kDefaultLng = 127.7700;

/// Map zoom: lower means closer. kNearMapLevel when the user's position is known,
/// the nationwide view otherwise.
const int kDefaultMapLevel = 12; // the whole country fits on screen
const int kNearMapLevel = 4; // around the user, roughly neighbourhood scale

/// Service area: all of South Korea
/// (Kakao Maps has no tiles outside Korea, so foreign coordinates render blank —
/// the bounds check blocks them)
const double kKoreaMinLat = 33.0;
const double kKoreaMaxLat = 38.7;
const double kKoreaMinLng = 124.5;
const double kKoreaMaxLng = 132.0;

bool isInKorea(double lat, double lng) =>
    lat >= kKoreaMinLat &&
    lat <= kKoreaMaxLat &&
    lng >= kKoreaMinLng &&
    lng <= kKoreaMaxLng;

const String kOutOfServiceMsg = 'Outside the service area (South Korea)';

/// Default depot. Per-region defaults live in const/value/regions.dart.
/// NOTE: this address string is sent verbatim to Kakao's search API, so it must stay
///   in Korean. It is transliterated by romanize.dart only when displayed.
const String kDefaultDepotAddress = '세종특별자치시 한누리대로 2130';

/// Bicycle condition types: database `condition` value -> display label
const Map<String, String> kConditionLabels = {
  'long_term': 'Long-abandoned',
  'damaged': 'Damaged',
  'obstruction': 'Blocking path',
  'parts_missing': 'Missing parts',
  'other': 'Other',
};

/// Inventory state: bikes.state -> display label
const Map<String, String> kBikeStateLabels = {
  'storage': 'Stored',
  'repair': 'Repair',
  'donation': 'Donated',
  'reuse': 'Reused',
  'disposal': 'Disposed',
};

/// Report processing state: database `status` value -> display label
const Map<String, String> kStatusLabels = {
  'submitted': 'Submitted',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'duplicate': 'Duplicate',
  'scheduled': 'Scheduled',
  'collected': 'Collected',
};
