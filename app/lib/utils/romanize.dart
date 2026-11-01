/// Transliterates Korean addresses and ID numbers into Roman letters, for display only.
///
/// [Why this exists]
/// Addresses come from the Kakao API and ID numbers from a database trigger. Both are in
/// Korean, so translating the app's own labels still leaves Korean on screen. Changing the
/// database or the external API is not an option, so the conversion happens **at display
/// time only**.
///
/// [Scope]
/// This is not a complete romanizer. It covers the 17 regional names, Jeju's districts, and
/// the administrative suffixes (-si, -gun, -gu, -eup, -myeon, -dong, -ri, -ro, -gil).
/// Anything not in the table is left as it is, which beats inventing a wrong spelling.
library;

/// Longer names must be replaced first
/// (so a full city name is matched whole, before its suffix is split off)
const Map<String, String> _places = {
  // ---- The 17 regions ----
  '제주특별자치도': 'Jeju',
  '서울특별시': 'Seoul',
  '부산광역시': 'Busan',
  '대구광역시': 'Daegu',
  '인천광역시': 'Incheon',
  '광주광역시': 'Gwangju',
  '대전광역시': 'Daejeon',
  '울산광역시': 'Ulsan',
  '세종특별자치시': 'Sejong',
  '강원특별자치도': 'Gangwon',
  '전북특별자치도': 'Jeonbuk',
  '경기도': 'Gyeonggi',
  '충청북도': 'Chungbuk',
  '충청남도': 'Chungnam',
  '전라남도': 'Jeonnam',
  '경상북도': 'Gyeongbuk',
  '경상남도': 'Gyeongnam',

  // ---- Jeju's cities ----
  '서귀포시': 'Seogwipo-si',
  '제주시': 'Jeju-si',

  // ---- Jeju's towns, townships and neighbourhoods ----
  '대정읍': 'Daejeong-eup',
  '한림읍': 'Hallim-eup',
  '애월읍': 'Aewol-eup',
  '구좌읍': 'Gujwa-eup',
  '조천읍': 'Jocheon-eup',
  '성산읍': 'Seongsan-eup',
  '남원읍': 'Namwon-eup',
  '표선면': 'Pyoseon-myeon',
  '안덕면': 'Andeok-myeon',
  '한경면': 'Hangyeong-myeon',
  '우도면': 'Udo-myeon',
  '추자면': 'Chuja-myeon',
  '동일리': 'Dongil-ri',
  '상대리': 'Sangdae-ri',
  '월림리': 'Wollim-ri',
  '명월리': 'Myeongwol-ri',
  '저지리': 'Jeoji-ri',
  '서광리': 'Seogwang-ri',
  '색달동': 'Saekdal-dong',
  '하원동': 'Hawon-dong',
  '중문동': 'Jungmun-dong',
  '서홍동': 'Seohong-dong',
  '연동': 'Yeon-dong',
  '노형동': 'Nohyeong-dong',
  '이도동': 'Ido-dong',
  '일도동': 'Ildo-dong',
  '삼도동': 'Samdo-dong',
  '화북동': 'Hwabuk-dong',
  '아라동': 'Ara-dong',
  '오라동': 'Ora-dong',

  // ---- Roads and facilities ----
  '글로벌에듀로': 'Global Edu-ro',
  '제주특별자치도청': 'Jeju Provincial Office',
  '제주국제공항': 'Jeju International Airport',
  '제주공항': 'Jeju Airport',
  '번길': 'beon-gil ',
  '문연로': 'Munyeon-ro',
};

/// Secondary pass for suffixes the table above did not catch
const Map<String, String> _suffixes = {
  '특별자치도': '',
  '광역시': '',
  '특별시': '',
  '시': '-si',
  '군': '-gun',
  '구': '-gu',
  '읍': '-eup',
  '면': '-myeon',
  '동': '-dong',
  '리': '-ri',
  '로': '-ro',
  '길': '-gil',
};

/// Whether the string still contains Hangul
bool hasHangul(String s) => RegExp(r'[가-힣]').hasMatch(s);

/// Romanizes an address. Hangul that is not in the table is left untouched.
///
/// e.g. a Jeju address becomes
///   'Jeju Seogwipo-si Daejeong-eup Dongil-ri 2855-2'
String romanizeAddress(String? address) {
  if (address == null || address.isEmpty) return '';
  var out = address;

  // Longest keys first
  final keys = _places.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    out = out.replaceAll(k, _places[k]!);
  }

  // Tidy up remaining suffixes, but skip the case where the stem could not be converted
  // (leaving whole Hangul words mixed in with Roman letters reads worse)
  if (!hasHangul(out)) {
    for (final e in _suffixes.entries) {
      out = out.replaceAll(e.key, e.value);
    }
  }

  // Collapse whitespace
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Romanizes an ID number.
/// e.g. a Jeju code becomes 'Jeju_Seogwipo-si_20260812_001'
String romanizeCode(String? code) {
  if (code == null || code.isEmpty) return '';
  return code
      .split('_')
      .map((part) => hasHangul(part) ? romanizeAddress(part) : part)
      .join('_');
}

/// Canonical region name -> English, for the region dropdown
/// e.g. the full name of Jeju province becomes 'Jeju'
String romanizeRegion(String? region) {
  if (region == null || region.isEmpty) return '';
  return _places[region] ?? romanizeAddress(region);
}
