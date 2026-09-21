import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/report.dart';
import '../const/value/constants.dart';
import 'api_client.dart';

/// RPT-04 신고 제출, RPT-05/06 조회, 중복 확인 RPC
class ReportService {
  final _client = Supabase.instance.client;

  /// 사진 업로드 → Storage 경로 반환 (버킷 비공개라 경로만 저장)
  Future<String> uploadPhoto(String uid, File photo) async {
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(kPhotoBucket).upload(path, photo);
    return path;
  }

  /// 표시용 서명 URL (1시간 유효)
  Future<String> signedPhotoUrl(String path) =>
      _client.storage.from(kPhotoBucket).createSignedUrl(path, 3600);

  /// 제출 전 중복 확인 (30m 반경, BE-02 RPC)
  Future<List<NearbyReport>> findNearby(double lat, double lng,
      {double radiusM = 30}) async {
    final rows = await _client.rpc('find_nearby_reports', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_m': radiusM,
    }) as List;
    return rows
        .map((r) => NearbyReport.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// 좌표 → 주소 (서버 프록시 경유, 실패 시 null — 표시는 좌표로 폴백)
  Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final res = await ApiClient.get(
        Uri.parse('$kAddressUrl?lat=$lat&lng=$lng'),
        timeout: const Duration(seconds: 5),
      );
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map<String, dynamic>)['address']
          as String?;
    } catch (_) {
      return null; // 서버 꺼져 있어도 신고는 계속 가능해야 함
    }
  }

  /// 신고 제출 (RLS: 본인 명의 + submitted만 허용됨)
  Future<void> submitReport({
    required String reporterId,
    required File photo,
    required double lat,
    required double lng,
    required String condition,
    required String description,
    String? address,
  }) async {
    final path = await uploadPhoto(reporterId, photo);
    address ??= await reverseGeocode(lat, lng); // 주소 자동 기록
    await _client.from('reports').insert(Report.insertMap(
          reporterId: reporterId,
          photoPath: path,
          lat: lat,
          lng: lng,
          condition: condition,
          description: description,
          address: address,
        ));
  }

  /// 지도용: 살아있는 신고 (최신 500건, BE-02 RPC — 지도 범위)
  Future<List<Report>> fetchInBounds({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
  }) async {
    final rows = await _client.rpc('reports_in_bounds', params: {
      'p_min_lat': minLat,
      'p_min_lng': minLng,
      'p_max_lat': maxLat,
      'p_max_lng': maxLng,
    }) as List;
    return rows.map((r) => Report.fromMap(r as Map<String, dynamic>)).toList();
  }

  /// 지도 초기 로드: 전체 활성 신고 (간단 버전)
  Future<List<Report>> fetchActive({int limit = 300}) async {
    final rows = await _client
        .from('reports')
        .select()
        .inFilter('status', ['submitted', 'approved', 'scheduled'])
        .order('reported_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => Report.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// 내 신고 이력 (RPT-06)
  Future<List<Report>> fetchMyReports(String uid) async {
    final rows = await _client
        .from('reports')
        .select()
        .eq('reporter_id', uid)
        .order('reported_at', ascending: false);
    return (rows as List)
        .map((r) => Report.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
