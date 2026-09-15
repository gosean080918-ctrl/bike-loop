import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/report.dart';
import '../const/value/constants.dart';

/// 관리자 기능 (ADM-01~07): 검토, 수거 작업 생성/진행, 재고 등록
class AdminService {
  final _client = Supabase.instance.client;

  // ---------- ADM-01/02: 신고 검토 ----------

  Future<List<Report>> fetchByStatus(String status, {int limit = 100}) async {
    final rows = await _client
        .from('reports')
        .select()
        .eq('status', status)
        .order('reported_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => Report.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> approve(String reportId) => _client.from('reports').update({
        'status': 'approved',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);

  Future<void> reject(String reportId) => _client.from('reports').update({
        'status': 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);

  Future<void> markDuplicate(String reportId, String originalId) =>
      _client.from('reports').update({
        'status': 'duplicate',
        'duplicate_of': originalId,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', reportId);

  /// 중복 후보: 해당 신고 주변의 다른 활성 신고
  Future<List<NearbyReport>> duplicateCandidates(Report r) async {
    final rows = await _client.rpc('find_nearby_reports', params: {
      'p_lat': r.lat,
      'p_lng': r.lng,
      'p_radius_m': 50,
    }) as List;
    return rows
        .map((m) => NearbyReport.fromMap(m as Map<String, dynamic>))
        .where((n) => n.id != r.id)
        .toList();
  }

  // ---------- ADM-03/04: 수거 작업 생성 ----------

  /// /optimize 호출 → collection_jobs + job_stops 저장 → 신고 상태 scheduled
  /// 반환: jobId
  Future<String> createJob({
    required List<Report> targets,
    required double depotLat,
    required double depotLng,
    double? returnLat,
    double? returnLng,
    required int vehicleCapacity,
    required int workMinutes,
  }) async {
    // 1) 최적화 서버 호출
    final res = await http
        .post(
          Uri.parse(kOptimizeUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'depot': {'lat': depotLat, 'lng': depotLng},
            if (returnLat != null && returnLng != null)
              'return_to': {'lat': returnLat, 'lng': returnLng},
            'vehicle_count': 1,
            'vehicle_capacity': vehicleCapacity,
            'work_minutes': workMinutes,
            'stops': targets
                .map((r) => {
                      'report_id': r.id,
                      'lat': r.lat,
                      'lng': r.lng,
                      'demand': 1,
                      'priority': r.priority,
                      // 관리자가 직접 고른 지점은 반드시 방문(A안)
                      'required': true,
                      // v2 엔진: 신고일로 경과일/긴급도 계산
                      'reported_at':
                          r.reportedAt.toUtc().toIso8601String(),
                    })
                .toList(),
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      // 서버가 설명을 준 경우 그대로 보여준다(예: 용량/시간 초과 안내)
      String msg = '서버 오류(${res.statusCode})';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
        if (d is String && d.isNotEmpty) msg = d;
      } catch (_) {}
      throw Exception(msg);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List;
    if (routes.isEmpty) throw Exception('생성된 경로가 없습니다');
    final route = routes.first as Map<String, dynamic>;

    // 2) 작업 저장 (도로 경로가 있으면 폴리라인도 함께)
    final roadPath = body['road_path'] as Map<String, dynamic>?;
    final uid = _client.auth.currentUser!.id;
    final job = await _client
        .from('collection_jobs')
        .insert({
          'admin_id': uid,
          // 구간별 색상을 위해 segments를 우선 저장(없으면 전체 polyline)
          if (roadPath != null)
            'route_polyline': roadPath['segments'] ?? roadPath['polyline'],
          'vehicle_capacity': vehicleCapacity,
          'work_minutes': workMinutes,
          'depot_lat': depotLat,
          'depot_lng': depotLng,
          'return_lat': returnLat,
          'return_lng': returnLng,
          'total_distance_m': body['total_distance_m'],
          'total_duration_s':
              (body['total_duration_minutes'] as num).toInt() * 60,
        })
        .select('id')
        .single();
    final jobId = job['id'] as String;

    // 3) 방문 순서 저장 + 신고 상태 변경
    final stops = (route['stops'] as List).cast<Map<String, dynamic>>();
    await _client.from('job_stops').insert([
      for (final s in stops)
        {
          'job_id': jobId,
          'seq': s['seq'],
          'report_id': s['report_id'],
        }
    ]);
    final scheduledIds = stops.map((s) => s['report_id'] as String).toList();
    await _client
        .from('reports')
        .update({'status': 'scheduled', 'job_id': jobId})
        .inFilter('id', scheduledIds);

    return jobId;
  }

  // ---------- ADM-05/06/07: 작업 진행 ----------

  /// 진행할 작업 + 방문 순서(신고 정보 포함)
  Future<List<Map<String, dynamic>>> fetchJobs({int limit = 20}) async {
    final rows = await _client
        .from('collection_jobs')
        .select('*, job_stops(*, reports(*))')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 지점 수거 완료: stop done + 신고 collected + 재고 등록(ADM-07)
  Future<void> completeStop({
    required String jobId,
    required int seq,
    required String reportId,
  }) async {
    await _client
        .from('job_stops')
        .update({'done': true})
        .eq('job_id', jobId)
        .eq('seq', seq);
    await _client.from('reports').update({
      'status': 'collected',
      'collected_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);
    await _client.from('bikes').upsert(
        {'report_id': reportId}, onConflict: 'report_id');
  }

  Future<void> finishJob(String jobId) => _client
      .from('collection_jobs')
      .update({'status': 'done'}).eq('id', jobId);

  /// 신고 영구 삭제 (RLS: admin만 허용. 테스트/오입력 정리용)
  /// ※ 사진 파일은 Storage에 남음 — 운영 전환 시 정리 배치 필요
  Future<void> deleteReport(String reportId) =>
      _client.from('reports').delete().eq('id', reportId);

  // ---------- ADM-08: 재고 관리 ----------

  /// 수거 완료 재고 목록 (신고 정보 조인).
  /// [state] 필터, [query] 관리번호 검색, 수거일 내림차순.
  Future<List<Map<String, dynamic>>> fetchBikes({
    String? state,
    String? query,
    int limit = 100,
  }) async {
    var q = _client.from('bikes').select('*, reports(*)');
    if (state != null) q = q.eq('state', state);
    if (query != null && query.trim().isNotEmpty) {
      q = q.ilike('code', '%${query.trim()}%');
    }
    final rows =
        await q.order('collected_at', ascending: false).limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// 재고 상태 변경 (보관/수리/기부/재사용/폐기)
  Future<void> updateBikeState(String bikeId, String state) =>
      _client.from('bikes').update({'state': state}).eq('id', bikeId);

  /// 보관 장소 변경
  Future<void> updateBikeStorage(String bikeId, String location) =>
      _client
          .from('bikes')
          .update({'storage_location': location}).eq('id', bikeId);

  /// 재고 항목 삭제 — 신고 기록은 '수거 완료'로 보존한다.
  /// (신고자 화면·이력 추적을 위해 reports는 건드리지 않음)
  Future<void> deleteBike(String bikeId) =>
      _client.from('bikes').delete().eq('id', bikeId);

  // ---------- ADM-09: 대시보드 통계 ----------

  /// 전체 집계 — 신고/수거/재고/최적화 효과
  /// (Supabase 무료티어 기준 데이터량이 작아 앱에서 집계)
  Future<Map<String, dynamic>> fetchDashboard() async {
    final reports = await _client
        .from('reports')
        .select('status, condition, reported_at, collected_at')
        .limit(2000);
    final bikes =
        await _client.from('bikes').select('state').limit(2000);
    final jobs = await _client
        .from('collection_jobs')
        .select('total_distance_m, total_duration_s, created_at')
        .limit(500);

    final byStatus = <String, int>{};
    final byCondition = <String, int>{};
    var leadDays = 0.0;
    var leadCount = 0;
    for (final r in (reports as List).cast<Map<String, dynamic>>()) {
      final s = r['status'] as String? ?? 'submitted';
      byStatus[s] = (byStatus[s] ?? 0) + 1;
      final c = r['condition'] as String? ?? 'other';
      byCondition[c] = (byCondition[c] ?? 0) + 1;
      // 신고→수거 소요일수
      final ca = r['collected_at'];
      if (ca != null) {
        final d = DateTime.parse(ca as String)
            .difference(DateTime.parse(r['reported_at'] as String))
            .inHours /
            24.0;
        if (d >= 0) {
          leadDays += d;
          leadCount++;
        }
      }
    }

    final byState = <String, int>{};
    for (final b in (bikes as List).cast<Map<String, dynamic>>()) {
      final s = b['state'] as String? ?? 'storage';
      byState[s] = (byState[s] ?? 0) + 1;
    }

    var totalDistanceM = 0;
    var totalDurationS = 0;
    for (final j in (jobs as List).cast<Map<String, dynamic>>()) {
      totalDistanceM += (j['total_distance_m'] as num?)?.toInt() ?? 0;
      totalDurationS += (j['total_duration_s'] as num?)?.toInt() ?? 0;
    }

    final collected = byStatus['collected'] ?? 0;
    final recycled = (byState['donation'] ?? 0) +
        (byState['reuse'] ?? 0) +
        (byState['repair'] ?? 0);
    final disposed = byState['disposal'] ?? 0;

    return {
      'reportTotal': (reports).length,
      'byStatus': byStatus,
      'byCondition': byCondition,
      'byState': byState,
      'bikeTotal': (bikes).length,
      'jobCount': (jobs).length,
      'totalDistanceKm': totalDistanceM / 1000.0,
      'totalDurationMin': totalDurationS / 60.0,
      'collected': collected,
      'recycled': recycled,
      'disposed': disposed,
      // 재생률 = (수리+기부+재사용) / (그것 + 폐기)
      'recycleRate': (recycled + disposed) == 0
          ? 0.0
          : recycled / (recycled + disposed) * 100,
      'avgLeadDays': leadCount == 0 ? 0.0 : leadDays / leadCount,
    };
  }

  /// 수거 작업 삭제.
  /// - job_stops는 FK cascade로 함께 삭제
  /// - 아직 수거되지 않은(scheduled) 신고는 승인 상태로 되돌려
  ///   다시 수거 대상으로 골라질 수 있게 한다
  /// - 이미 수거 완료된 신고는 그대로 둔다(이력 보존)
  Future<void> deleteJob(String jobId) async {
    await _client
        .from('reports')
        .update({'status': 'approved', 'job_id': null})
        .eq('job_id', jobId)
        .eq('status', 'scheduled');
    await _client
        .from('reports')
        .update({'job_id': null})
        .eq('job_id', jobId);
    await _client.from('collection_jobs').delete().eq('id', jobId);
  }
}
