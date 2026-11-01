import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../const/value/constants.dart';
import 'api_client.dart';

/// Depot settings: where a route starts and where it returns
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

/// Stores the start and return points in local device storage
/// On first run, the default address is resolved to coordinates through the search API.
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
      // First run only: resolve the default depot address into coordinates
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

  /// Reset the return point to match the start point
  Future<void> clearReturn() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kRetLat);
    await p.remove(_kRetLng);
    await p.remove(_kRetAddr);
  }

  /// Address -> coordinates via the server's /search endpoint; null on failure.
  /// Used to look up each region's default depot (a provincial or city office).
  Future<(double, double, String)?> resolveAddress(String query) async {
    try {
      final res = await ApiClient.get(
        Uri.parse('$kSearchUrl?q=${Uri.encodeComponent(query)}'),
        timeout: const Duration(seconds: 6),
      );
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

  /// Address -> coordinates, falling back to the centre of the country on failure
  Future<(double, double, String)> _resolveAddress(String query) async {
    final r = await resolveAddress(query);
    // If the server is down, fall back to the national centre; an admin can move it on the map
    return r ?? (kDefaultLat, kDefaultLng, query);
  }
}
