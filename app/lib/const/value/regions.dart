/// 전국 확장 — 시도(광역자치단체) 17곳과 지역별 기본 보관소.
///
/// [설계 배경]
/// - 서비스 지역을 제주 → 전국으로 확대(2026-08-12).
/// - 수거 차량의 출발지(보관소) 기본값은 **도청 / 특별·광역시청**.
///   실제 운영에서는 시군구 차고지가 맞지만, 전국 표준 좌표가 필요해
///   우선 시도 대표 청사를 기본값으로 둔다. 관리자가 지도에서 바꿀 수 있다.
/// - ⚠ 경기·경북처럼 넓은 도는 도청 한 곳만으로는 왕복 거리가 커서
///   경로 생성이 거부되거나 작업시간 초과가 날 수 있다.
///   → 그 경우 관리자가 작업 탭에서 가까운 차고지로 출발지를 바꿔야 한다.
library;

class RegionDepot {
  /// 표준 시도명 (DB 저장값). 예: '경기도', '서울특별시'
  final String name;

  /// 화면 표시용 짧은 이름. 예: '경기', '서울'
  final String short;

  /// 기본 보관소 이름. 예: '경기도청'
  final String depotName;

  /// 기본 보관소 주소 (주소 검색으로 좌표 재확인 가능)
  final String depotAddress;

  /// 기본 보관소 좌표 (근사값 — 앱은 우선 서버 검색으로 정확한 좌표를 얻고,
  /// 서버가 응답하지 않을 때 이 값으로 폴백한다)
  final double lat;
  final double lng;

  const RegionDepot({
    required this.name,
    required this.short,
    required this.depotName,
    required this.depotAddress,
    required this.lat,
    required this.lng,
  });
}

/// 시도 17곳 (특별시 1 · 광역시 6 · 특별자치시 1 · 도 6 · 특별자치도 3)
const List<RegionDepot> kRegions = [
  RegionDepot(
      name: '서울특별시',
      short: '서울',
      depotName: '서울특별시청',
      depotAddress: '서울특별시 중구 세종대로 110',
      lat: 37.5663,
      lng: 126.9779),
  RegionDepot(
      name: '부산광역시',
      short: '부산',
      depotName: '부산광역시청',
      depotAddress: '부산광역시 연제구 중앙대로 1001',
      lat: 35.1798,
      lng: 129.0750),
  RegionDepot(
      name: '대구광역시',
      short: '대구',
      depotName: '대구광역시청',
      depotAddress: '대구광역시 중구 공평로 88',
      lat: 35.8714,
      lng: 128.6014),
  RegionDepot(
      name: '인천광역시',
      short: '인천',
      depotName: '인천광역시청',
      depotAddress: '인천광역시 남동구 정각로 29',
      lat: 37.4563,
      lng: 126.7052),
  RegionDepot(
      name: '광주광역시',
      short: '광주',
      depotName: '광주광역시청',
      depotAddress: '광주광역시 서구 내방로 111',
      lat: 35.1595,
      lng: 126.8526),
  RegionDepot(
      name: '대전광역시',
      short: '대전',
      depotName: '대전광역시청',
      depotAddress: '대전광역시 서구 둔산로 100',
      lat: 36.3504,
      lng: 127.3845),
  RegionDepot(
      name: '울산광역시',
      short: '울산',
      depotName: '울산광역시청',
      depotAddress: '울산광역시 남구 중앙로 201',
      lat: 35.5384,
      lng: 129.3114),
  RegionDepot(
      name: '세종특별자치시',
      short: '세종',
      depotName: '세종특별자치시청',
      depotAddress: '세종특별자치시 한누리대로 2130',
      lat: 36.4800,
      lng: 127.2890),
  RegionDepot(
      name: '경기도',
      short: '경기',
      depotName: '경기도청',
      depotAddress: '경기도 수원시 영통구 도청로 30',
      lat: 37.2893,
      lng: 127.0537),
  RegionDepot(
      name: '강원특별자치도',
      short: '강원',
      depotName: '강원특별자치도청',
      depotAddress: '강원특별자치도 춘천시 중앙로 1',
      lat: 37.8813,
      lng: 127.7300),
  RegionDepot(
      name: '충청북도',
      short: '충북',
      depotName: '충청북도청',
      depotAddress: '충청북도 청주시 상당구 상당로 82',
      lat: 36.6357,
      lng: 127.4914),
  RegionDepot(
      name: '충청남도',
      short: '충남',
      depotName: '충청남도청',
      depotAddress: '충청남도 홍성군 홍북읍 충남대로 21',
      lat: 36.6588,
      lng: 126.6728),
  RegionDepot(
      name: '전북특별자치도',
      short: '전북',
      depotName: '전북특별자치도청',
      depotAddress: '전북특별자치도 전주시 완산구 효자로 225',
      lat: 35.8203,
      lng: 127.1088),
  RegionDepot(
      name: '전라남도',
      short: '전남',
      depotName: '전라남도청',
      depotAddress: '전라남도 무안군 삼향읍 오룡길 1',
      lat: 34.8161,
      lng: 126.4630),
  RegionDepot(
      name: '경상북도',
      short: '경북',
      depotName: '경상북도청',
      depotAddress: '경상북도 안동시 풍천면 도청대로 455',
      lat: 36.5760,
      lng: 128.5056),
  RegionDepot(
      name: '경상남도',
      short: '경남',
      depotName: '경상남도청',
      depotAddress: '경상남도 창원시 의창구 중앙대로 300',
      lat: 35.2383,
      lng: 128.6924),
  RegionDepot(
      name: '제주특별자치도',
      short: '제주',
      depotName: '제주특별자치도청',
      depotAddress: '제주특별자치도 제주시 문연로 6',
      lat: 33.4890,
      lng: 126.4983),
];

/// 주소 앞부분에 나타날 수 있는 표기 → 표준 시도명
/// 카카오 API는 '서울특별시'로 주는 경우와 '서울'로 주는 경우가 모두 있고,
/// 강원/전북은 2023~2024년에 '특별자치도'로 바뀌어 옛 표기도 함께 받아준다.
const Map<String, String> kRegionAliases = {
  '서울': '서울특별시',
  '서울특별시': '서울특별시',
  '부산': '부산광역시',
  '부산광역시': '부산광역시',
  '대구': '대구광역시',
  '대구광역시': '대구광역시',
  '인천': '인천광역시',
  '인천광역시': '인천광역시',
  '광주': '광주광역시',
  '광주광역시': '광주광역시',
  '대전': '대전광역시',
  '대전광역시': '대전광역시',
  '울산': '울산광역시',
  '울산광역시': '울산광역시',
  '세종': '세종특별자치시',
  '세종시': '세종특별자치시',
  '세종특별자치시': '세종특별자치시',
  '경기': '경기도',
  '경기도': '경기도',
  '강원': '강원특별자치도',
  '강원도': '강원특별자치도',
  '강원특별자치도': '강원특별자치도',
  '충북': '충청북도',
  '충청북도': '충청북도',
  '충남': '충청남도',
  '충청남도': '충청남도',
  '전북': '전북특별자치도',
  '전라북도': '전북특별자치도',
  '전북특별자치도': '전북특별자치도',
  '전남': '전라남도',
  '전라남도': '전라남도',
  '경북': '경상북도',
  '경상북도': '경상북도',
  '경남': '경상남도',
  '경상남도': '경상남도',
  '제주': '제주특별자치도',
  '제주도': '제주특별자치도',
  '제주특별자치도': '제주특별자치도',
};

/// 주소 문자열 → 표준 시도명. 알 수 없으면 null.
/// 예) '제주특별자치도 서귀포시 대정읍 동일리 2855-2' → '제주특별자치도'
///     '경기 수원시 팔달구 ...'                      → '경기도'
String? regionOf(String? address) {
  if (address == null) return null;
  final first = address.trim().split(RegExp(r'\s+')).firstOrNull;
  if (first == null || first.isEmpty) return null;
  return kRegionAliases[first];
}

/// 주소 문자열 → 시군구(두 번째 토큰). 예) '수원시', '강남구', '무안군'
/// 관리번호와 통계 집계에 쓴다.
String? districtOf(String? address) {
  if (address == null) return null;
  final parts = address.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts[1];
}

/// 표준 시도명 → 기본 보관소 정보
RegionDepot? depotOf(String? regionName) {
  if (regionName == null) return null;
  for (final r in kRegions) {
    if (r.name == regionName) return r;
  }
  return null;
}

/// 좌표 → 가장 가까운 시도 대표 청사 (주소를 못 얻었을 때의 폴백)
RegionDepot nearestRegion(double lat, double lng) {
  var best = kRegions.first;
  var bestD = double.infinity;
  for (final r in kRegions) {
    final d = (r.lat - lat) * (r.lat - lat) + (r.lng - lng) * (r.lng - lng);
    if (d < bestD) {
      bestD = d;
      best = r;
    }
  }
  return best;
}
