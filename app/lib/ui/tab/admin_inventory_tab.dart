import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';
import '../../utils/romanize.dart';
import '../component/signed_photo.dart';

/// ADM-08: collected inventory — ID number, photo, report location, report date,
/// collection date, storage location and state. Filter by state, search by ID number,
/// and change state or storage location from the detail sheet.
class AdminInventoryTab extends ConsumerStatefulWidget {
  const AdminInventoryTab({super.key});

  @override
  ConsumerState<AdminInventoryTab> createState() =>
      _AdminInventoryTabState();
}

class _AdminInventoryTabState extends ConsumerState<AdminInventoryTab> {
  String? _stateFilter; // null = all
  final _search = TextEditingController();
  List<Map<String, dynamic>> _bikes = [];
  Map<String, int> _summary = {}; // counts per state, always over everything, ignoring the filter
  int _total = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final admin = ref.read(adminServiceProvider);
      final rows = await admin.fetchBikes(
        state: _stateFilter,
        query: _search.text,
      );
      // The summary is computed over everything, regardless of the filter
      final all = await admin.fetchBikes(limit: 1000);
      final counts = <String, int>{};
      for (final b in all) {
        final s = b['state'] as String? ?? 'storage';
        counts[s] = (counts[s] ?? 0) + 1;
      }
      if (mounted) {
        setState(() {
          _bikes = rows;
          _summary = counts;
          _total = all.length;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load inventory: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Delete an inventory item; the report record is preserved
  Future<void> _deleteBike(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete from inventory'),
        content: Text('Remove ${romanizeCode(b['code'] as String?)} '
            'from the inventory list?\n'
            'The report stays recorded as collected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref
          .read(adminServiceProvider)
          .deleteBike(b['id'] as String);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from inventory')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _openDetail(Map<String, dynamic> b) async {
    final report = b['reports'] as Map<String, dynamic>?;
    final storageCtl =
        TextEditingController(text: b['storage_location'] as String? ?? '');
    final fmt = DateFormat('yyyy-MM-dd');

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SignedPhoto(
                    path: report?['photo_url'] as String? ?? '', size: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(romanizeCode(b['code'] as String?).isEmpty ? '(no code)' : romanizeCode(b['code'] as String?),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(
                        report?['address'] as String? ?? 'No address',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Reported ${fmt.format(DateTime.parse(report?['reported_at'] as String? ?? b['collected_at'] as String))}'
                        ' · collected ${fmt.format(DateTime.parse(b['collected_at'] as String))}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.dateGray),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Change state',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in kBikeStateLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: b['state'] == e.key,
                    onSelected: (_) async {
                      await ref
                          .read(adminServiceProvider)
                          .updateBikeState(b['id'] as String, e.key);
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('Storage location',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: storageCtl,
                    decoration: const InputDecoration(
                        hintText: 'e.g. Warehouse A, rack 3'),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(72, 48)),
                  onPressed: () async {
                    await ref.read(adminServiceProvider).updateBikeStorage(
                        b['id'] as String, storageCtl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Summary panel at the top: total held, plus a count per state
  Widget _summaryCard() {
    (Color, Color) colorOf(String key) => switch (key) {
          'storage' => (AppColors.pendingBg, AppColors.pendingFg),
          'disposal' => (AppColors.grayBg, AppColors.grayFg),
          _ => (AppColors.doneBg, AppColors.doneFg),
        };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadowCard,
              blurRadius: 12,
              offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('In stock',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.muted)),
              const SizedBox(width: 8),
              Text('$_total',
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final e in kBikeStateLabels.entries) ...[
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 7, horizontal: 4),
                        decoration: BoxDecoration(
                          color: colorOf(e.key).$1,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text('${_summary[e.key] ?? 0}',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: colorOf(e.key).$2)),
                      ),
                      const SizedBox(height: 5),
                      Text(e.value,
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.sub)),
                    ],
                  ),
                ),
                if (e.key != kBikeStateLabels.keys.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MM.dd');

    return Column(
      children: [
        // Summary panel
        if (!_loading) _summaryCard(),
        // Search and filter
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search by code (e.g. Jeju_Seogwipo-si)',
              prefixIcon:
                  const Icon(Icons.search, color: AppColors.faint),
              suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward,
                      color: AppColors.primary),
                  onPressed: _load),
            ),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _stateFilter == null,
                onSelected: (_) {
                  setState(() => _stateFilter = null);
                  _load();
                },
              ),
              const SizedBox(width: 8),
              for (final e in kBikeStateLabels.entries) ...[
                ChoiceChip(
                  label: Text(e.value),
                  selected: _stateFilter == e.key,
                  onSelected: (_) {
                    setState(() => _stateFilter = e.key);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _bikes.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(
                              child: Text('No collected bicycles yet.',
                                  style: TextStyle(
                                      color: AppColors.muted))),
                        ])
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _bikes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final b = _bikes[i];
                            final r =
                                b['reports'] as Map<String, dynamic>?;
                            final state = b['state'] as String? ?? '';
                            return GestureDetector(
                              onTap: () => _openDetail(b),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(18),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: AppColors.shadowCard,
                                        blurRadius: 10,
                                        offset: Offset(0, 2)),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    SignedPhoto(
                                        path: r?['photo_url']
                                                as String? ??
                                            '',
                                        size: 60),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              b['code'] as String? ??
                                                  '-',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w800,
                                                  fontSize: 14.5),
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Collected ${fmt.format(DateTime.parse(b['collected_at'] as String))}',
                                            style: const TextStyle(
                                                fontSize: 11.5,
                                                color: AppColors
                                                    .dateGray),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            romanizeAddress(r?['address'] as String?).isEmpty
                                                ? 'No address'
                                                : romanizeAddress(r?['address'] as String?),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                color: AppColors.sub),
                                            maxLines: 1,
                                            overflow:
                                                TextOverflow.ellipsis,
                                          ),
                                          if ((b['storage_location']
                                                      as String? ??
                                                  '')
                                              .isNotEmpty)
                                            Text(
                                              '📍 ${b['storage_location']}',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.muted),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        StatusChip(
                                          label:
                                              kBikeStateLabels[state] ??
                                                  state,
                                          status: state == 'disposal'
                                              ? 'rejected'
                                              : (state == 'storage'
                                                  ? 'scheduled'
                                                  : 'collected'),
                                        ),
                                        const SizedBox(height: 2),
                                        GestureDetector(
                                          onTap: () => _deleteBike(b),
                                          behavior: HitTestBehavior
                                              .opaque,
                                          child: const Padding(
                                            padding: EdgeInsets.only(
                                                top: 4,
                                                left: 8,
                                                right: 2),
                                            child: Icon(
                                                Icons.delete_outline,
                                                size: 19,
                                                color:
                                                    AppColors.chevron),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}
