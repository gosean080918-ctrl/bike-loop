import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/report.dart';
import '../const/value/constants.dart';
import 'api_client.dart';

/// Admin features (ADM-01 to 07): review, create and run collection jobs, register inventory
class AdminService {
  final _client = Supabase.instance.client;

  // ---------- ADM-01/02: report review ----------

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

  /// Duplicate candidates: other active reports near this one
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

  // ---------- ADM-03/04: creating a collection job ----------

  /// Call /optimize, save collection_jobs and job_stops, then set the reports to scheduled
  /// Returns the jobId
  Future<String> createJob({
    required List<Report> targets,
    required double depotLat,
    required double depotLng,
    double? returnLat,
    double? returnLng,
    required int vehicleCapacity,
    required int workMinutes,
  }) async {
    // 1) Call the optimization server, attaching the access token it requires
    final res = await ApiClient.postJson(
      Uri.parse(kOptimizeUrl),
      jsonEncode({
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
                      // Stops the admin picked explicitly are mandatory visits
                      'required': true,
                      // v2 engine: derives days elapsed and urgency from the report date
                      'reported_at':
                          r.reportedAt.toUtc().toIso8601String(),
                    })
                .toList(),
      }),
      timeout: const Duration(seconds: 30),
    );
    if (res.statusCode == 401) throw Exception(ApiClient.authErrorMessage);
    if (res.statusCode == 429) {
      throw Exception('Too many requests. Please try again shortly.');
    }
    if (res.statusCode != 200) {
      // If the server explained the failure, show it as-is (e.g. over capacity or time)
      String msg = 'Server error (${res.statusCode})';
      try {
        final d = jsonDecode(utf8.decode(res.bodyBytes))['detail'];
        if (d is String && d.isNotEmpty) msg = d;
      } catch (_) {}
      throw Exception(msg);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final routes = body['routes'] as List;
    if (routes.isEmpty) throw Exception('No route was generated');
    final route = routes.first as Map<String, dynamic>;

    // 2) Save the job, including the road polyline when one is available
    final roadPath = body['road_path'] as Map<String, dynamic>?;
    final uid = _client.auth.currentUser!.id;
    final job = await _client
        .from('collection_jobs')
        .insert({
          'admin_id': uid,
          // Prefer segments so each leg can be coloured; fall back to the whole polyline
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

    // 3) Save the visit order and update the report states
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

  // ---------- ADM-05/06/07: running a job ----------

  /// The job to run, with its visit order and the underlying reports
  Future<List<Map<String, dynamic>>> fetchJobs({int limit = 20}) async {
    final rows = await _client
        .from('collection_jobs')
        .select('*, job_stops(*, reports(*))')
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Mark a stop collected: stop done, report collected, inventory registered (ADM-07)
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

  /// Permanently delete a report (RLS: admins only; for clearing test or mistaken entries)
  /// NOTE: the photo file stays in Storage — a cleanup job is needed before going live
  Future<void> deleteReport(String reportId) =>
      _client.from('reports').delete().eq('id', reportId);

  // ---------- ADM-08: inventory ----------

  /// Collected inventory, joined with the report data.
  /// [state] filters by state, [query] searches the ID number; newest collection first.
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

  /// Change inventory state (storage / repair / donation / reuse / disposal)
  Future<void> updateBikeState(String bikeId, String state) =>
      _client.from('bikes').update({'state': state}).eq('id', bikeId);

  /// Change the storage location
  Future<void> updateBikeStorage(String bikeId, String location) =>
      _client
          .from('bikes')
          .update({'storage_location': location}).eq('id', bikeId);

  /// Delete an inventory item; the report stays on record as collected.
  /// (reports are untouched so the reporter's history stays intact)
  Future<void> deleteBike(String bikeId) =>
      _client.from('bikes').delete().eq('id', bikeId);

  // ---------- ADM-09: dashboard statistics ----------

  /// Overall totals: reports, collections, inventory, and the effect of optimization
  /// (data volumes on the Supabase free tier are small enough to aggregate in the app)
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
      // Days from report to collection
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
      // Reuse rate = (repair + donation + reuse) / (that + disposal)
      'recycleRate': (recycled + disposed) == 0
          ? 0.0
          : recycled / (recycled + disposed) * 100,
      'avgLeadDays': leadCount == 0 ? 0.0 : leadDays / leadCount,
    };
  }

  /// Delete a collection job.
  /// - job_stops are removed by the foreign-key cascade
  /// - reports still scheduled go back to approved so they can be
  ///   selected for collection again
  /// - reports already collected are left alone, preserving the record
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
