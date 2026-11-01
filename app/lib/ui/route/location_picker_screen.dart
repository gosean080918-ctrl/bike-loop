import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kakao_map_plugin/kakao_map_plugin.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../service/api_client.dart';

/// RPT-02: adjust the report location on the map, with place search
/// Pan the map under the centre pin, or search to jump straight to a place, then confirm.
class LocationPickerScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const LocationPickerScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _Place {
  final String name;
  final String address;
  final double lat;
  final double lng;
  _Place(this.name, this.address, this.lat, this.lng);
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  KakaoMapController? _controller;
  final _query = TextEditingController();
  List<_Place> _results = [];
  bool _searching = false;

  // Kakao Maps has no tiles outside Korea, so foreign coordinates (such as an emulator's
  // default GPS) render blank; fall back to the national centre instead
  late double _centerLat = isInKorea(widget.initialLat, widget.initialLng)
      ? widget.initialLat
      : kDefaultLat;
  late double _centerLng = isInKorea(widget.initialLat, widget.initialLng)
      ? widget.initialLng
      : kDefaultLng;

  /// Start at neighbourhood zoom when the reporter's position is known, nationwide otherwise
  late final int _initialLevel =
      isInKorea(widget.initialLat, widget.initialLng)
          ? kNearMapLevel
          : kDefaultMapLevel;

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final res = await ApiClient.get(
        Uri.parse('$kSearchUrl?q=${Uri.encodeComponent(q)}'),
        timeout: const Duration(seconds: 6),
      );
      if (res.statusCode == 401) throw Exception(ApiClient.authErrorMessage);
      if (res.statusCode != 200) throw Exception('Search failed');
      final places = (jsonDecode(res.body)['places'] as List)
          .map((p) => _Place(
                p['name'] as String? ?? '',
                p['address'] as String? ?? '',
                (p['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble(),
              ))
          .toList();
      if (mounted) setState(() => _results = places);
      if (places.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No results')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Search failed — check that the server is running')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _moveTo(_Place p) {
    // Block the move entirely if it leaves the service area
    if (!isInKorea(p.lat, p.lng)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOutOfServiceMsg)));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _centerLat = p.lat;
      _centerLng = p.lng;
      _results = [];
      _query.text = p.name;
    });
    // Move via the controller rather than rebuilding the map
    _controller?.setCenter(LatLng(p.lat, p.lng));
    _controller?.setLevel(3);
  }

  Future<void> _confirm() async {
    LatLng? center;
    if (_controller != null) {
      center = await _controller!.getCenter();
    }
    center ??= LatLng(_centerLat, _centerLng);
    if (!mounted) return;
    // Cannot confirm a point outside the service area
    if (!isInKorea(center.latitude, center.longitude)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(kOutOfServiceMsg)));
      return;
    }
    Navigator.of(context).pop(center);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust location')),
      body: Stack(
        children: [
          // Force the map to fill the screen; an unsized box renders blank
          Positioned.fill(
            child: KakaoMap(
              center: LatLng(_centerLat, _centerLng),
              currentLevel: _initialLevel,
              onMapCreated: (c) {
                _controller = c;
                // Re-apply layout and centre right after creation, to fix a blank map
                Future.delayed(const Duration(milliseconds: 600), () {
                  _controller?.relayout();
                  _controller?.setCenter(
                      LatLng(_centerLat, _centerLng));
                });
              },
            ),
          ),
          // Pin fixed at the centre of the screen
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 36),
                  child: Icon(Icons.place,
                      size: 44, color: Color(0xFFD32F2F)),
                ),
              ),
            ),
          ),
          // Search bar and result list at the top
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x2214281E),
                          blurRadius: 16,
                          offset: Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.search,
                          size: 20, color: AppColors.faint),
                      Expanded(
                        child: TextField(
                          controller: _query,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _search(),
                          decoration: const InputDecoration(
                            hintText: 'Search a place (e.g. Jeju Airport)',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 14),
                          ),
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.only(right: 14),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2)),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.arrow_forward,
                              size: 20, color: AppColors.primary),
                          onPressed: _search,
                        ),
                    ],
                  ),
                ),
                if (_results.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                            color: Color(0x2214281E),
                            blurRadius: 16,
                            offset: Offset(0, 4)),
                      ],
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, i) {
                        final p = _results[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined,
                              size: 20, color: AppColors.primary),
                          title: Text(p.name,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(p.address,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.muted)),
                          onTap: () => _moveTo(p),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check),
            label: const Text('Use this location'),
          ),
        ),
      ),
    );
  }
}
