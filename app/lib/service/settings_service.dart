import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../const/value/constants.dart';

/// 출발지/복귀지(보관소) 설정
class DepotConfig {
  final double lat;
  final double lng;
  final String address;
  final double returnLat;
  final double returnLng;
  final String returnAddress;

  const DepotConfig({
    required this.lat,
    required this.lng,
    required this.address,
    required this.returnLat,
    required this.returnLng,
    required this.returnAddress,
  });

  bool get returnSameAsDepot =>
      (lat - returnLat).abs() < 1e-9 && (lng - returnLng).abs() < 1e-9;
}

/// 출발지/복귀지 저장 (기기 로컬 저장소)
/// 최초 실행 시 기본 주소(글로벌에듀로304번길 10)를 검색 API로 좌표 해석.
class SettingsService {
  static const _kDepotLat = 'depot_lat';
  static const _kDepotLng = 'depot_lng';
  static const _kDepotAddr = 'depot_addr';
  static const _kRetLat = 'return_lat';
  static const _kRetLng = 'return_lng';
  static const _kRetAddr = 'return_addr';

  Future<DepotConfig> load() async {
    final p = await SharedPreferences.getInstance();
    var lat = p.getDouble(_kDepotLat);
    var lng = p.getDouble(_kDepotLng);
    var addr = p.getString(_kDepotAddr);

    if (lat == null || lng == null) {
      // 최초 1회: 기본 보관소 주소를 좌표로 해석
      final resolved = await _resolveAddress(kDefaultDepotAddress);
      lat = resolved.$1;
      lng = resolved.$2;
      addr = resolved.$3;
      await saveDepot(lat, lng, addr);
    }

    final rLat = p.getDouble(_kRetLat) ?? lat;
    final rLng = p.getDouble(_kRetLng) ?? lng;
    final rAddr = p.getString(_kRetAddr) ?? addr ?? '';

    return DepotConfig(
      lat: lat,
      lng: lng,
      address: addr ?? '',
      returnLat: rLat,
      returnLng: rLng,
      returnAddress: rAddr,
    );
  }

  Future<void> saveDepot(double lat, double lng, String? address) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kDepotLat, lat);
    await p.setDouble(_kDepotLng, lng);
    await p.setString(_kDepotAddr, address ?? '');
  }

  Future<void> saveReturn(double lat, double lng, String? address) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kRetLat, lat);
    await p.setDouble(_kRetLng, lng);
    await p.setString(_kRetAddr, address ?? '');
  }

  /// 복귀지를 출발지와 동일하게 초기화
  Future<void> clearReturn() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRetLat);
    await p.remove(_kRetLng);
    await p.remove(_kRetAddr);
  }

  /// 주소 → 좌표 (서버 /search 경유). 실패하면 null.
  /// 지역별 기본 보관소(도청/시청) 좌표를 얻을 때 사용.
  Future<(double, double, String)?> resolveAddress(String query) async {
    try {
      final res = await http
          .get(Uri.parse('$kSearchUrl?q=${Uri.encodeComponent(query)}'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final places = jsonDecode(res.body)['places'] as List;
        if (places.isNotEmpty) {
          final p = places.first as Map<String, dynamic>;
          return (
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
            (p['address'] as String?) ?? query,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  /// 주소 → 좌표 (실패 시 전국 중심 좌표로 폴백)
  Future<(double, double, String)> _resolveAddress(String query) async {
    final r = await resolveAddress(query);
    // 서버가 꺼져 있으면 전국 중심으로 폴백 (관리자가 지도에서 바꾸면 됨)
    return r ?? (kDefaultLat, kDefaultLng, query);
  }
}
