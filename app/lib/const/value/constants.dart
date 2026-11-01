/// 앱 전역 상수.
///
/// [보안 원칙 - blueprint 섹션1]
/// 여기 넣어도 되는 키: Supabase anon key(RLS 전제), 카카오맵 JS 키(번들 제한).
/// service_role 키, 카카오 REST 키는 절대 금지.
library;

/// Supabase (프로젝트: bikereclaim1, Seoul)
const String kSupabaseUrl = 'https://xpkifseyiphyvoppcsui.supabase.co';

/// Publishable key (anon 역할, RLS 전제 — 앱에 포함 가능)
const String kSupabaseAnonKey = 'sb_publishable_JNTxRVuSMHQV1-aoL7tOLg_gc6e8Cn-';

/// 카카오맵 JavaScript 키 (앱: Bike Loop, ID 1622635 — 2026-10-26 재발급)
/// ※ 이전 앱(ID 1514725)이 콘솔에서 사라져 모든 화면에서 지도가 뜨지 않았다.
///   새 앱을 만들고 키를 교체함. Web 플랫폼(http://localhost) 등록과
///   카카오맵 활성화가 되어 있어야 지도가 로드된다.
const String kKakaoJsKey = 'f143629fbc328db1b57a03365760a430';

/// 사진 버킷 이름
const String kPhotoBucket = 'report-photos';

/// 백엔드 서버 — Google Cloud Run 배포본 (2026-08-02)
/// 프로젝트: bikeloop-504502 / 리전: asia-northeast3(서울)
/// 재배포: server/ 폴더에서
///   gcloud run deploy bikeloop-server --source . --region asia-northeast3 ...
/// ※ 로컬 서버로 개발할 땐 아래 주석을 바꿔 쓴다
///   (에뮬레이터는 10.0.2.2 = PC의 localhost)
const String kServerBase =
    'https://bikeloop-server-775952432199.asia-northeast3.run.app';
// const String kServerBase = 'http://10.0.2.2:8000'; // 로컬 개발용
const String kOptimizeUrl = '$kServerBase/optimize';
const String kAddressUrl = '$kServerBase/address';
const String kSearchUrl = '$kServerBase/search';

/// ⚠ demo-en 브랜치 — 영어 시연 영상 전용 설정
/// 기능·서비스 범위는 main과 동일한 '전국'이고, 화면 문구만 영어다.
/// 시연이 끝나면 main 브랜치로 돌아갈 것.

/// 기본 지도 중심: 대한민국 중심부 (전국 서비스)
/// GPS를 얻으면 그 위치로, 못 얻으면 이 좌표로 지도를 연다.
const double kDefaultLat = 36.3400;
const double kDefaultLng = 127.7700;

/// 지도 축척: 낮을수록 확대. 내 위치가 있으면 kNearMapLevel, 없으면 전국 뷰
const int kDefaultMapLevel = 12; // 전국이 한 화면에 들어오는 수준
const int kNearMapLevel = 4; // 내 위치 주변 (동네 수준)

/// 서비스 지역: 대한민국 전역
/// (카카오맵은 국외 타일이 없어 해외 좌표는 흰 화면이 되므로 경계로 막는다)
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

/// 기본 출발지/보관소 — 지역별 기본값은 const/value/regions.dart 참조.
/// ※ 주소 문자열은 카카오 검색 질의에 그대로 쓰이므로 한글이어야 한다.
///   화면에 보일 때는 romanize.dart가 로마자로 바꿔준다.
const String kDefaultDepotAddress = '세종특별자치시 한누리대로 2130';

/// 자전거 상태 유형 (DB condition 값 ↔ 표시 라벨)
const Map<String, String> kConditionLabels = {
  'long_term': 'Long-abandoned',
  'damaged': 'Damaged',
  'obstruction': 'Blocking path',
  'parts_missing': 'Missing parts',
  'other': 'Other',
};

/// 재고 상태 (bikes.state ↔ 표시 라벨)
const Map<String, String> kBikeStateLabels = {
  'storage': 'Stored',
  'repair': 'Repair',
  'donation': 'Donated',
  'reuse': 'Reused',
  'disposal': 'Disposed',
};

/// 신고 처리 상태 (DB status 값 ↔ 표시 라벨)
const Map<String, String> kStatusLabels = {
  'submitted': 'Submitted',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'duplicate': 'Duplicate',
  'scheduled': 'Scheduled',
  'collected': 'Collected',
};
