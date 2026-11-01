import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/regions.dart';
import '../../state_management/providers.dart';
import 'location_picker_screen.dart';

/// The chosen result: coordinates and address
class DepotPick {
  final double lat;
  final double lng;
  final String address;
  const DepotPick(this.lat, this.lng, this.address);
}

/// Depot picker for the start and return points, added with nationwide coverage (2026-08-12)
///
/// With 17 regions, a one-line "change" link was no longer usable, so this became a
/// screen of its own. The user can pick a provincial or city office, or drop a pin on
/// the map to use a depot address of their own.
class DepotPickerScreen extends ConsumerStatefulWidget {
  /// Screen title (start point or return point)
  final String title;

  /// The currently configured address, used to show the check mark
  final String currentAddress;

  /// Starting coordinates for the map picker
  final double initialLat;
  final double initialLng;

  const DepotPickerScreen({
    super.key,
    required this.title,
    required this.currentAddress,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  ConsumerState<DepotPickerScreen> createState() => _DepotPickerScreenState();
}

class _DepotPickerScreenState extends ConsumerState<DepotPickerScreen> {
  final _query = TextEditingController();
  String _filter = '';
  bool _busy = false;

  List<RegionDepot> get _list {
    if (_filter.isEmpty) return kRegions;
    final q = _filter.trim();
    return kRegions
        .where((r) =>
            r.name.contains(q) ||
            r.short.contains(q) ||
            r.depotName.contains(q) ||
            r.depotAddress.contains(q))
        .toList();
  }

  /// Office address -> coordinates via server search, falling back to the built-in values
  Future<void> _pickRegion(RegionDepot r) async {
    setState(() => _busy = true);
    final resolved =
        await ref.read(settingsServiceProvider).resolveAddress(r.depotAddress);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.pop(
      context,
      DepotPick(
        resolved?.$1 ?? r.lat,
        resolved?.$2 ?? r.lng,
        r.depotAddress,
      ),
    );
  }

  /// Pick directly on the map, for places that are not government offices
  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: widget.initialLat,
          initialLng: widget.initialLng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final addr = await ref
        .read(reportServiceProvider)
        .reverseGeocode(result.latitude, result.longitude);
    if (!mounted) return;
    Navigator.pop(
      context,
      DepotPick(result.latitude, result.longitude,
          addr ?? '${result.latitude}, ${result.longitude}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _query,
              onChanged: (v) => setState(() => _filter = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20),
                hintText: 'Search a region',
              ),
            ),
          ),
          // Pick on the map
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pickOnMap,
              icon: const Icon(Icons.place_outlined, size: 18),
              label: const Text('Pick on the map (depot yard)'),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46)),
            ),
          ),
          const Divider(height: 1),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 60),
              itemBuilder: (context, i) {
                final r = list[i];
                final isCurrent = widget.currentAddress == r.depotAddress;
                return ListTile(
                  enabled: !_busy,
                  leading: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.primary
                          : AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(r.short,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isCurrent
                                ? Colors.white
                                : AppColors.primary)),
                  ),
                  title: Text(r.depotName,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  subtitle: Text(r.depotAddress,
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.muted)),
                  trailing: isCurrent
                      ? const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 22)
                      : const Icon(Icons.chevron_right,
                          color: AppColors.chevron, size: 20),
                  onTap: () => _pickRegion(r),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
