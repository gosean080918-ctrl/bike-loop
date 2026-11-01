import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../const/model/report.dart';
import '../const/value/constants.dart';
import 'api_client.dart';

/// RPT-04 submit a report, RPT-05/06 read reports, and the duplicate-check RPC
class ReportService {
  final _client = Supabase.instance.client;

  /// Uploads a photo and returns its Storage path (the bucket is private, so only the path is stored)
  Future<String> uploadPhoto(String uid, File photo) async {
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(kPhotoBucket).upload(path, photo);
    return path;
  }

  /// A signed URL for display, valid for one hour
  Future<String> signedPhotoUrl(String path) =>
      _client.storage.from(kPhotoBucket).createSignedUrl(path, 3600);

  /// Duplicate check before submitting (30 m radius, BE-02 RPC)
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

  /// Coordinates -> address, via the server proxy; null on failure, and the UI falls back to coordinates
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
      return null; // reporting must keep working even when the server is down
    }
  }

  /// Submit a report (RLS allows only one's own name and the submitted state)
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
    address ??= await reverseGeocode(lat, lng); // record the address automatically
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

  /// For the map: live reports, newest 500, via the map-bounds BE-02 RPC
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

  /// Initial map load: all active reports (simple version)
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

  /// The user's own report history (RPT-06)
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
