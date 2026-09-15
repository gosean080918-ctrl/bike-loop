import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/value/app_theme.dart';

/// 수거 동선 (Claude Design 시안 ④):
/// 번호 원형 핀(초록, 흰 테두리) + 점선 경로 + 하단 방문 순서 카드
class RouteMapScreen extends StatefulWidget {
  final double depotLat;
  final double depotLng;

  /// [{seq, lat, lng, label}] — seq 오름차순
  final List<Map<String, dynamic>> stops;

  /// 카카오모빌리티 도로 경로.
  /// ① 구간별: [[[lat,lng],...], [[lat,lng],...]]  ← 구간마다 색 다름
  /// ② 단일: [[lat,lng], ...]                     ← 하위호환
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

  /// 시안 핀: 원형 + 흰 테두리 + 그림자, SVG를 data URI로 마커 이미지에 주입
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
        markerImageSrc: _pinDataUri('출발', '#17261D', '#FFFFFF',
            fontSize: 11),
        width: 48,
        height: 48,
        offsetX: 24,
        offsetY: 24,
      ),
    };
    for (final s in widget.stops) {
      final short = ((s['label'] as String?) ?? '')
          .replaceFirst('제주특별자치도 ', '')
          .replaceFirst('제주시 ', '')
          .replaceFirst('서귀포시 ', '');
      markers.add(Marker(
        markerId: 'stop${s['seq']}',
        latLng: LatLng(s['lat'] as double, s['lng'] as double),
        markerImageSrc: _pinDataUri('${s['seq']}', '#1B7742', '#FFFFFF'),
        width: 48,
        height: 48,
        offsetX: 24,
        offsetY: 24,
        // 핀 옆 주소 라벨 (말풍선 상시 표시)
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

  /// 구간별 색 (출발→① 연한색 → 마지막 구간 진한색으로 그라데이션)
  static const List<Color> _segColors = [
    Color(0xFF6FCF97), // 1구간 — 연한 초록
    Color(0xFF3BAF6B), //
    Color(0xFF1B7742), // 브랜드 그린
    Color(0xFF11603A), //
    Color(0xFF0B4A2C), // 마지막 — 진한 초록
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
      // 도로 경로 없음 — 순서만 점선으로
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

    // 구간별 형식인지(중첩 리스트) 판별
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
          strokeOpacity: 0.85, // 겹치는 구간은 색이 섮여 보임
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
      appBar: AppBar(title: const Text('수거 동선')),
      body: Column(
        children: [
          if (segCount > 1)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Text('구간',
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
                          ? '출발→①'
                          : (i == segCount - 1
                              ? '→복귀'
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
          // 시안: 하단 방문 순서 영역
          Container(
            color: AppColors.bg,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            alignment: Alignment.centerLeft,
            child: const Text('방문 순서',
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
                final label = ((s['label'] as String?) ?? '')
                    .replaceFirst('제주특별자치도 ', '');
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
