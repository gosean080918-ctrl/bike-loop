import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/value/app_theme.dart';
import '../../utils/romanize.dart';

/// Collection route (mockup screen 4):
/// numbered round pins (green, white border), a dashed path, and a visit-order card below
class RouteMapScreen extends StatefulWidget {
  final double depotLat;
  final double depotLng;

  /// [{seq, lat, lng, label}], ordered by ascending seq
  final List<Map<String, dynamic>> stops;

  /// Road route from Kakao Mobility.
  /// (a) per leg: [[[lat,lng],...], [[lat,lng],...]]  <- each leg gets its own colour
  /// (b) single:  [[lat,lng], ...]                   <- kept for backwards compatibility
  final List<dynamic>? roadPolyline;

  const RouteMapScreen({
    super.key,
    required this.depotLat,
    required this.depotLng,
    required this.stops,
    this.roadPolyline,
  });

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  Set<Marker> _markers = {};
  List<Polyline> _polylines = [];

  List<LatLng> get _points => [
        LatLng(widget.depotLat, widget.depotLng),
        ...widget.stops
            .map((s) => LatLng(s['lat'] as double, s['lng'] as double)),
        LatLng(widget.depotLat, widget.depotLng),
      ];

  LatLng get _center {
    final ps = _points;
    return LatLng(
      ps.map((p) => p.latitude).reduce((a, b) => a + b) / ps.length,
      ps.map((p) => p.longitude).reduce((a, b) => a + b) / ps.length,
    );
  }

  int get _level {
    final ps = _points;
    var maxKm = 0.0;
    for (final a in ps) {
      for (final b in ps) {
        final dLat = (a.latitude - b.latitude) * 111;
        final dLng = (a.longitude - b.longitude) * 92;
        maxKm = math.max(maxKm, math.sqrt(dLat * dLat + dLng * dLng));
      }
    }
    if (maxKm < 0.6) return 4;
    if (maxKm < 1.2) return 5;
    if (maxKm < 2.5) return 6;
    if (maxKm < 5) return 7;
    if (maxKm < 10) return 8;
    return 9;
  }

  /// Mockup pin: circle, white border, shadow; the SVG is injected as a data URI marker image
  String _pinDataUri(String text, String bg, String fg,
      {double fontSize = 17}) {
    final svg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">
  <circle cx="24" cy="24" r="19" fill="$bg" stroke="#FFFFFF" stroke-width="3"/>
  <text x="24" y="24" text-anchor="middle" dominant-baseline="central"
        font-family="sans-serif" font-size="$fontSize" font-weight="800"
        fill="$fg">$text</text>
</svg>''';
    return 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
  }

  void _draw() {
    final markers = <Marker>{
      Marker(
        markerId: 'depot',
        latLng: LatLng(widget.depotLat, widget.depotLng),
        markerImageSrc: _pinDataUri('Depot', '#17261D', '#FFFFFF',
            fontSize: 11),
        width: 48,
        height: 48,
        offsetX: 24,
        offsetY: 24,
      ),
    };
    for (final s in widget.stops) {
      // Pin labels must be short: drop the province and city, then transliterate
      final short = romanizeAddress(((s['label'] as String?) ?? '')
          .replaceFirst('제주특별자치도 ', '')
          .replaceFirst('제주시 ', '')
          .replaceFirst('서귀포시 ', ''));
      markers.add(Marker(
        markerId: 'stop${s['seq']}',
        latLng: LatLng(s['lat'] as double, s['lng'] as double),
        markerImageSrc: _pinDataUri('${s['seq']}', '#1B7742', '#FFFFFF'),
        width: 48,
        height: 48,
        offsetX: 24,
        offsetY: 24,
        // Address label beside the pin, as an always-visible info window
        infoWindowContent:
            '<div style="padding:3px 8px;font-size:12px;font-weight:600;'
            'color:#17261D;white-space:nowrap;">$short</div>',
        infoWindowFirstShow: true,
        infoWindowRemovable: false,
      ));
    }
    setState(() {
      _markers = markers;
      _polylines = _buildPolylines();
    });
  }

  /// Per-leg colours, shading from light on the first leg to dark on the last
  static const List<Color> _segColors = [
    Color(0xFF6FCF97), // leg 1 — light green
    Color(0xFF3BAF6B), //
    Color(0xFF1B7742), // brand green
    Color(0xFF11603A), //
    Color(0xFF0B4A2C), // last — dark green
  ];

  Color _segColor(int i, int total) {
    if (total <= 1) return AppColors.primary;
    final t = i / (total - 1); // 0.0 ~ 1.0
    final idx = (t * (_segColors.length - 1)).round();
    return _segColors[idx];
  }

  List<Polyline> _buildPolylines() {
    final road = widget.roadPolyline;
    if (road == null || road.isEmpty) {
      // No road route available: draw the visit order as a dashed line
      return [
        Polyline(
          polylineId: 'route',
          points: _points,
          strokeColor: AppColors.primary,
          strokeWidth: 4,
          strokeOpacity: 0.9,
          strokeStyle: StrokeStyle.shortDash,
        ),
      ];
    }

    // Detect the per-leg format (a nested list)
    final first = road.first;
    final isSegmented = first is List && first.isNotEmpty && first.first is List;

    if (!isSegmented) {
      return [
        Polyline(
          polylineId: 'road',
          points: [
            for (final p in road)
              LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
          strokeColor: AppColors.primary,
          strokeWidth: 5,
          strokeOpacity: 0.9,
          strokeStyle: StrokeStyle.solid,
        ),
      ];
    }

    return [
      for (var i = 0; i < road.length; i++)
        Polyline(
          polylineId: 'road$i',
          points: [
            for (final p in (road[i] as List))
              LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
          ],
          strokeColor: _segColor(i, road.length),
          strokeWidth: 6,
          strokeOpacity: 0.85, // overlapping legs blend visibly
          strokeStyle: StrokeStyle.solid,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final road = widget.roadPolyline;
    final segCount = (road != null &&
            road.isNotEmpty &&
            road.first is List &&
            (road.first as List).isNotEmpty &&
            (road.first as List).first is List)
        ? road.length
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Collection route')),
      body: Column(
        children: [
          if (segCount > 1)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Text('Legs',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted)),
                  const SizedBox(width: 10),
                  for (var i = 0; i < segCount; i++) ...[
                    Container(
                      width: 22,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _segColor(i, segCount),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      i == 0
                          ? 'Depot→1'
                          : (i == segCount - 1
                              ? '→back'
                              : '→${i + 1}'),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.sub),
                    ),
                    if (i < segCount - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
            ),
          Expanded(
            child: KakaoMap(
              center: _center,
              currentLevel: _level,
              onMapCreated: (_) => _draw(),
              markers: _markers.toList(),
              polylines: _polylines,
            ),
          ),
          // Mockup: the visit-order area at the bottom
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            alignment: Alignment.centerLeft,
            child: const Text('Visit order',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink)),
          ),
          Container(
            color: AppColors.bg,
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              itemCount: widget.stops.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final s = widget.stops[i];
                final label = romanizeAddress(
                    ((s['label'] as String?) ?? '')
                        .replaceFirst('제주특별자치도 ', ''));
                return Container(
                  width: 170,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: AppColors.shadowCard,
                          blurRadius: 10,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle),
                        child: Text('${s['seq']}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                      const SizedBox(height: 7),
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
