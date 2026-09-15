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

/// 카카오맵 JavaScript 키 (앱: BikeReclaim, ID 1514725)
/// ※ 카카오 콘솔에서 Web 플랫폼(http://localhost) 등록 + 카카오맵 활성화 필요
const String kKakaoJsKey = '69c16e042a28b0f92bdd91e61421c3cc';

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

/// 기본 지도 중심: 대한민국 중심부 (전국 서비스, 2026-08-12)
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

const String kOutOfServiceMsg = '서비스 지역(대한민국)이 아닙니다';

/// 기본 출발지/보관소 — 지역별 기본값은 const/value/regions.dart 참조.
/// 최초 실행 시(지역 미선택) 사용할 폴백 주소.
const String kDefaultDepotAddress = '세종특별자치시 한누리대로 2130';

/// 자전거 상태 유형 (기획안 4.1 — DB condition 값 ↔ 한글 라벨)
const Map<String, String> kConditionLabels = {
  'long_term': '장기 방치 의심',
  'damaged': '파손',
  'obstruction': '통행 방해',
  'parts_missing': '부품 분실',
  'other': '기타',
};

/// 재고 상태 (bikes.state ↔ 한글 라벨)
const Map<String, String> kBikeStateLabels = {
  'storage': '보관',
  'repair': '수리',
  'donation': '기부',
  'reuse': '재사용',
  'disposal': '폐기',
};

/// 신고 처리 상태 (DB status 값 ↔ 한글 라벨)
const Map<String, String> kStatusLabels = {
  'submitted': '접수됨',
  'approved': '승인됨',
  'rejected': '반려',
  'duplicate': '중복 신고',
  'scheduled': '수거 예정',
  'collected': '수거 완료',
};
