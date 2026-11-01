/// 한글 주소·관리번호를 화면 표시용 로마자로 바꾼다 (영어 시연판 전용).
///
/// [왜 필요한가]
/// 주소는 카카오 API가, 관리번호는 DB 트리거가 만들어 준다. 둘 다 한글이라
/// 앱 문구만 영어로 바꿔서는 화면에 한글이 남는다. 그렇다고 DB나 외부 API를
/// 건드릴 수는 없으니, **보여줄 때만** 로마자로 변환한다.
///
/// [범위]
/// 완전한 로마자 변환기가 아니다. 시연에 나오는 제주 지역과 전국 시도 이름,
/// 그리고 행정구역 접미사(시/군/구/읍/면/동/리/로/길)만 처리한다.
/// 매핑에 없는 글자는 그대로 둔다 — 틀린 로마자를 지어내는 것보다 낫다.
library;

/// 긴 이름부터 치환해야 한다.
/// (예: '서귀포시'를 '서귀포'+'시'로 쪼개기 전에 통째로 잡는다)
const Map<String, String> _places = {
  // ---- 시도 17곳 ----
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

  // ---- 제주 시군구 ----
  '서귀포시': 'Seogwipo-si',
  '제주시': 'Jeju-si',

  // ---- 제주 읍면동 (시연에 나오는 곳 위주) ----
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

  // ---- 시연에 쓰는 도로·시설명 ----
  '글로벌에듀로': 'Global Edu-ro',
  '제주특별자치도청': 'Jeju Provincial Office',
  '제주국제공항': 'Jeju International Airport',
  '제주공항': 'Jeju Airport',
  '번길': 'beon-gil ',
  '문연로': 'Munyeon-ro',
};

/// 접미사만 남은 경우를 위한 보조 치환 (위 표에서 못 잡은 것들)
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

/// 한글이 포함되어 있는지
bool hasHangul(String s) => RegExp(r'[가-힣]').hasMatch(s);

/// 주소 문자열을 로마자로. 매핑에 없는 한글은 그대로 남는다.
///
/// 예) '제주특별자치도 서귀포시 대정읍 동일리 2855-2'
///   → 'Jeju Seogwipo-si Daejeong-eup Dongil-ri 2855-2'
String romanizeAddress(String? address) {
  if (address == null || address.isEmpty) return '';
  var out = address;

  // 긴 이름 먼저 (키 길이 내림차순)
  final keys = _places.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final k in keys) {
    out = out.replaceAll(k, _places[k]!);
  }

  // 남은 접미사 정리 — '○○시'처럼 앞말을 못 바꾼 경우는 건드리지 않는다
  // (한글이 통째로 남아 있으면 로마자와 섞여 더 어색해지므로)
  if (!hasHangul(out)) {
    for (final e in _suffixes.entries) {
      out = out.replaceAll(e.key, e.value);
    }
  }

  // 공백 정리
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 관리번호를 로마자로.
/// 예) '제주_서귀포시_20260812_001' → 'Jeju_Seogwipo-si_20260812_001'
String romanizeCode(String? code) {
  if (code == null || code.isEmpty) return '';
  return code
      .split('_')
      .map((part) => hasHangul(part) ? romanizeAddress(part) : part)
      .join('_');
}

/// 시도 표준명 → 영문 (지역 드롭다운용)
/// 예) '제주특별자치도' → 'Jeju'
String romanizeRegion(String? region) {
  if (region == null || region.isEmpty) return '';
  return _places[region] ?? romanizeAddress(region);
}
