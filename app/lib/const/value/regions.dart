/// Nationwide coverage: the 17 first-level administrative regions and each one's default depot.
///
/// [Background]
/// - The service area was extended from Jeju to the whole country (2026-08-12).
/// - The collection vehicle's default start point is the **provincial office**, or the
///   **city hall** for a metropolitan city. In real operation a municipal depot would be
///   more accurate, but a standard nationwide coordinate was needed, so the regional
///   office is the default. An administrator can change it on the map.
/// - NOTE: in large provinces such as Gyeonggi or Gyeongbuk, a single provincial office
///   can make the round trip long enough that route generation is refused or the working
///   time is exceeded. In that case the administrator should move the start point to a
///   nearer depot from the jobs tab.
library;

class RegionDepot {
  /// Canonical region name, as stored in the database
  final String name;

  /// Short name for display
  final String short;

  /// Name of the default depot, e.g. the provincial office
  final String depotName;

  /// Address of the default depot; its coordinates can be re-resolved by address search
  final String depotAddress;

  /// Approximate coordinates of the default depot. The app resolves exact ones by server
  /// search first and falls back to these when the server does not respond.
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

/// All 17 regions: 1 special city, 6 metropolitan cities, 1 special self-governing city,
/// 6 provinces, 3 special self-governing provinces
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

/// Variant spellings that can appear at the start of an address, mapped to the canonical name.
/// The Kakao API returns both the full and the short form, and Gangwon and Jeonbuk were
/// renamed in 2023-2024, so their older spellings are accepted too.
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

/// Address string -> canonical region name; null when it cannot be determined.
/// (The Korean literals below are matched against addresses returned by Kakao and must
///  stay in Korean; they are transliterated only for display, in utils/romanize.dart.)
String? regionOf(String? address) {
  if (address == null) return null;
  final first = address.trim().split(RegExp(r'\s+')).firstOrNull;
  if (first == null || first.isEmpty) return null;
  return kRegionAliases[first];
}

/// Address string -> the city, county or district (its second token).
/// Used in ID numbers and in statistics.
String? districtOf(String? address) {
  if (address == null) return null;
  final parts = address.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  return parts[1];
}

/// Canonical region name -> that region's default depot
RegionDepot? depotOf(String? regionName) {
  if (regionName == null) return null;
  for (final r in kRegions) {
    if (r.name == regionName) return r;
  }
  return null;
}

/// Coordinates -> the nearest regional office; the fallback when no address is available
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
