import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../const/value/regions.dart';
import '../../state_management/providers.dart';
import '../../utils/romanize.dart';
import '../route/location_picker_screen.dart';

/// RPT-01 to 04: photo -> automatic current location, adjustable on the map -> one of five
/// condition types plus a description -> duplicate check -> submit
class ReportTab extends ConsumerStatefulWidget {
  const ReportTab({super.key});

  @override
  ConsumerState<ReportTab> createState() => _ReportTabState();
}

class _ReportTabState extends ConsumerState<ReportTab> {
  final _picker = ImagePicker();
  final _description = TextEditingController();
  File? _photo;
  double? _lat, _lng;
  String? _address; // reverse-geocoding result: shown on screen and stored with the report
  String? _condition; // a kConditionLabels key
  bool _busy = false;
  bool _locating = false;

  /// Guard against a GPS race. This bug once caused GPS to be removed entirely (2026-07-21).
  /// Becomes true as soon as the user confirms a location on the map or by search.
  /// After that, a late GPS response must never overwrite it.
  bool _userPickedLocation = false;

  @override
  void initState() {
    super.initState();
    // Nationwide (2026-08-12): capture the reporter's current position up front.
    // This is only a starting suggestion; the user can change it freely on the map.
    WidgetsBinding.instance.addPostFrameCallback((_) => _locateMe());
  }

  /// Current position -> coordinates and address. Failures pass silently; manual picking still works.
  Future<void> _locateMe({bool force = false}) async {
    if (_locating) return;
    if (!force && _userPickedLocation) return; // protect a location the user confirmed
    setState(() => _locating = true);
    try {
      final pos = await ref.read(locationServiceProvider).getCurrentPosition();
      // If the user picked a location while this was in flight, do not overwrite it
      if (!mounted || (!force && _userPickedLocation)) return;
      if (pos == null || !isInKorea(pos.latitude, pos.longitude)) {
        if (mounted && force) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Could not get your location. Please pick it on the map.')));
        }
        return;
      }
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _address = null;
      });
      await _fillAddress(pos.latitude, pos.longitude);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Coordinates -> address via the server proxy; on failure the coordinates are shown as-is.
  Future<void> _fillAddress(double lat, double lng) async {
    final addr =
        await ref.read(reportServiceProvider).reverseGeocode(lat, lng);
    if (!mounted) return;
    // Ignore the result if the location changed again meanwhile
    if (_lat != lat || _lng != lng) return;
    setState(() => _address = addr);
  }

  Future<void> _takePhoto(ImageSource source) async {
    final img = await _picker.pickImage(
        source: source, maxWidth: 1600, imageQuality: 85);
    if (img == null) return;
    setState(() => _photo = File(img.path));
  }

  /// RPT-02: fine-tune the location on the map
  Future<void> _adjustLocation() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialLat: _lat ?? kDefaultLat,
          initialLng: _lng ?? kDefaultLng,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _lat = result.latitude;
        _lng = result.longitude;
        _address = null;
        _userPickedLocation = true; // lock it so GPS cannot overwrite it
      });
      await _fillAddress(result.latitude, result.longitude);
    }
  }

  Future<void> _submit() async {
    final user = ref.read(currentUserProvider);
    if (user == null || _photo == null || _lat == null || _condition == null) {
      return;
    }
    // Reports outside the service area are not accepted
    if (!isInKorea(_lat!, _lng!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('$kOutOfServiceMsg — please pick a location in Korea')));
      return;
    }
    setState(() => _busy = true);
    final service = ref.read(reportServiceProvider);
    try {
      // Duplicate check before submitting (30 m radius)
      final nearby = await service.findNearby(_lat!, _lng!);
      if (nearby.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Already reported nearby'),
            content: Text(
                '${nearby.length} open report(s) exist within '
                '${nearby.first.distanceM.round()}m.\n'
                'If it is the same bicycle this would be a duplicate. Continue?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Report anyway')),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }

      await service.submitReport(
        reporterId: user.id,
        photo: _photo!,
        lat: _lat!,
        lng: _lng!,
        condition: _condition!,
        description: _description.text.trim(),
        address: _address, // reuse the address already resolved, avoiding another lookup
      );
      ref.invalidate(myReportsProvider);
      ref.invalidate(activeReportsProvider);
      ref.invalidate(pendingReportsProvider); // refresh the admin review tab
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted. Thank you!')));
        setState(() {
          _photo = null;
          _lat = null;
          _lng = null;
          _address = null;
          _condition = null;
          _userPickedLocation = false;
          _description.clear();
        });
        _locateMe(); // re-acquire the position, ready for the next report
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Submit failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _photo != null && _lat != null && _condition != null && !_busy;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Photo (RPT-01) — mockup: dashed-border tile with a preview
          const SectionTitle('Photo', required: true),
          const SizedBox(height: 10),
          _photo == null
              ? Row(
                  children: [
                    GestureDetector(
                      onTap: () => _takePhoto(ImageSource.camera),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFB9C4BC), width: 1.4),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('+',
                                style: TextStyle(
                                    fontSize: 24,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w300)),
                            Text('Camera',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _takePhoto(ImageSource.gallery),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFB9C4BC), width: 1.4),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_library_outlined,
                                size: 22, color: AppColors.primary),
                            SizedBox(height: 4),
                            Text('Gallery',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(_photo!, fit: BoxFit.cover),
                  ),
                ),
          if (_photo != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _takePhoto(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _takePhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),

          // 2. Location — mockup: white card, green dot, "edit" link
          const SectionTitle('Location'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowCard,
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_locating)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    else
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _locating && _lat == null
                            ? 'Getting your location…'
                            : _lat == null
                                ? 'Pick the bicycle location on the map'
                                : (_address == null
                                    ? '${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}'
                                    : romanizeAddress(_address)),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color:
                              _lat == null ? AppColors.faint : AppColors.ink,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _adjustLocation,
                      child: Text(_lat == null ? 'Select' : 'Edit',
                          style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Region badge: shows in advance which authority will handle this
                    if (regionOf(_address) != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(romanizeRegion(regionOf(_address)),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _locating ? null : () => _locateMe(force: true),
                      icon: const Icon(Icons.my_location, size: 15),
                      label: const Text('My location'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 3. Condition type (RPT-03; the five types from the plan)
          const SectionTitle('Condition', required: true),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: kConditionLabels.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _condition == e.key,
                      onSelected: (_) => setState(() => _condition = e.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),

          // 4. A short description (RPT-03)
          const SectionTitle('Description', hint: '(optional)'),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText:
                  'e.g. The wheels are rusted and the saddle is gone. '
                  'It has been in the same spot for over a month.',
            ),
          ),
          const SizedBox(height: 14),

          // 5. Submit (RPT-04 plus the duplicate check) — the mockup's CTA
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: canSubmit
                  ? const [
                      BoxShadow(
                          color: AppColors.shadowCta,
                          blurRadius: 20,
                          offset: Offset(0, 8)),
                    ]
                  : null,
            ),
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Submit report'),
            ),
          ),
        ],
      ),
    );
  }
}
