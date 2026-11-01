import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';

/// RPT-05: show active reports on the Kakao map
/// Markers use the pattern proven on the route map: inject them with setState after onMapCreated.
class MapTab extends ConsumerStatefulWidget {
  const MapTab({super.key});

  @override
  ConsumerState<MapTab> createState() => _MapTabState();
}

class _MapTabState extends ConsumerState<MapTab> {
  Set<Marker> _markers = {};
  bool _mapReady = false;
  KakaoMapController? _controller;

  bool _movedToMe = false;

  @override
  void initState() {
    super.initState();
    // Nationwide (2026-08-12): open on the national view, then move to the user's
    // neighbourhood once a position arrives — via the controller, without rebuilding the map.
    WidgetsBinding.instance.addPostFrameCallback((_) => _moveToMe());
  }

  /// Move to the user's position.
  /// When [manual], the user pressed the button, so failures are reported on screen.
  ///
  /// NOTE: calling setCenter before the map's WebView is ready is silently ignored,
  ///   so this retries briefly until the controller exists.
  Future<void> _moveToMe({bool manual = false}) async {
    if (_movedToMe && !manual) return;
    final svc = ref.read(locationServiceProvider);

    // If a last known position exists, move there first so the app feels faster
    final last = await svc.getLastKnownPosition();
    if (mounted && last != null && isInKorea(last.latitude, last.longitude)) {
      await _center(last.latitude, last.longitude);
    }

    final pos = await svc.getCurrentPosition();
    if (!mounted) return;
    if (pos == null || !isInKorea(pos.latitude, pos.longitude)) {
      if (manual) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not get your location. Check location permission and GPS.')));
      }
      return;
    }
    await _center(pos.latitude, pos.longitude);
    _movedToMe = true;
  }

  /// Retry centring for up to three seconds, until the controller is ready
  ///
  /// NOTE: Kakao Maps runs inside a WebView. Calling setCenter or setLevel before its
  ///   internal initialization finishes has been seen to leave the map blank, so — as on
  ///   the location picker — relayout() is called first, then the move.
  Future<void> _center(double lat, double lng) async {
    for (var i = 0; i < 10; i++) {
      if (!mounted) return;
      if (_mapReady && _controller != null) {
        try {
          _controller!.relayout();
          await Future.delayed(const Duration(milliseconds: 150));
          if (!mounted || _controller == null) return;
          _controller!.setCenter(LatLng(lat, lng));
          _controller!.setLevel(kNearMapLevel);
        } catch (_) {
          // Not ready yet: retry on the next loop
          await Future.delayed(const Duration(milliseconds: 300));
          continue;
        }
        return;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  /// Pin colour per condition type, shared with the legend
  static const Map<String, Color> kConditionColors = {
    'long_term': Color(0xFF1B7742), // suspected long-abandoned — green
    'damaged': Color(0xFFE8590C), // damaged — orange
    'obstruction': Color(0xFFE24B4A), // blocking a footpath — red
    'parts_missing': Color(0xFF1B5FA5), // parts missing — blue
    'other': Color(0xFF6B7671), // other — grey
  };

  static String _hex(Color c) =>
      '#${c.value.toRadixString(16).substring(2).toUpperCase()}';

  static final Map<String, String> _pinCache = {};

  /// Round pin per type, as a cached SVG data URI
  static String _pinFor(String condition) =>
      _pinCache.putIfAbsent(condition, () {
        final color =
            _hex(kConditionColors[condition] ?? kConditionColors['other']!);
        return 'data:image/svg+xml;base64,'
            '${base64Encode(utf8.encode('''
<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34">
  <circle cx="17" cy="17" r="12" fill="$color" stroke="#FFFFFF" stroke-width="3"/>
  <circle cx="17" cy="17" r="4" fill="#FFFFFF"/>
</svg>'''))}';
      });

  void _rebuildMarkers(List<Report> list) {
    if (!_mapReady || !mounted) return;
    setState(() {
      _markers = {
        for (final r in list)
          Marker(
            markerId: r.id,
            latLng: LatLng(r.lat, r.lng),
            markerImageSrc: _pinFor(r.condition),
            width: 34,
            height: 34,
            offsetX: 17,
            offsetY: 17,
          ),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(activeReportsProvider);

    // Refresh the markers when the data changes
    ref.listen(activeReportsProvider, (_, next) {
      final list = next.value;
      if (list != null) _rebuildMarkers(list);
    });

    return Stack(
      children: [
        Positioned.fill(
          child: KakaoMap(
            center: LatLng(kDefaultLat, kDefaultLng),
            currentLevel: kDefaultMapLevel,
            markers: _markers.toList(),
            onMapCreated: (c) {
              _mapReady = true;
              _controller = c;
              // Blank-map guard: runs unconditionally, whether or not GPS succeeded.
              //   If the WebView is created before it has a layout, no tiles are drawn;
              //   calling relayout() and setCenter() once recovers it.
              //   (the same pattern already proven on the location picker)
              Future.delayed(const Duration(milliseconds: 600), () {
                if (!mounted) return;
                try {
                  c.relayout();
                  c.setCenter(LatLng(kDefaultLat, kDefaultLng));
                  c.setLevel(kDefaultMapLevel);
                } catch (_) {}
                final list = ref.read(activeReportsProvider).value;
                if (list != null) _rebuildMarkers(list);
                _moveToMe();
              });
              // A second pass, for slower devices
              Future.delayed(const Duration(milliseconds: 1800), () {
                if (!mounted) return;
                try {
                  c.relayout();
                } catch (_) {}
              });
            },
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 10,
                    offset: Offset(0, 2)),
              ],
            ),
            child: reports.when(
              data: (list) => Text('${list.length} open reports',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
              loading: () => const Text('Loading…',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.muted)),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              IconButton.filledTonal(
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  // Doubles as a manual recovery when the map looks blank
                  try {
                    _controller?.relayout();
                  } catch (_) {}
                  ref.invalidate(activeReportsProvider);
                },
              ),
              const SizedBox(height: 8),
              // Move to my location — the manual fallback when the automatic move fails
              IconButton.filledTonal(
                tooltip: 'My location',
                icon: const Icon(Icons.my_location),
                onPressed: () => _moveToMe(manual: true),
              ),
            ],
          ),
        ),
        // Colour legend by type
        Positioned(
          left: 12,
          bottom: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
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
                for (final e in kConditionColors.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: e.value, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          kConditionLabels[e.key] ?? e.key,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sub),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
