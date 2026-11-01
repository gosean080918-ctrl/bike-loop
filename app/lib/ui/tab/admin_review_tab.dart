import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../const/model/report.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';
import '../../utils/romanize.dart';
import '../component/signed_photo.dart';
import '../route/report_detail_screen.dart';

/// ADM-01/02: review new reports — approve, reject, or mark as duplicate
class AdminReviewTab extends ConsumerWidget {
  const AdminReviewTab({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref, Future<void> f,
      String done) async {
    try {
      await f;
      ref.invalidate(pendingReportsProvider);
      ref.invalidate(approvedReportsProvider);
      ref.invalidate(activeReportsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _duplicate(
      BuildContext context, WidgetRef ref, Report r) async {
    final admin = ref.read(adminServiceProvider);
    final candidates = await admin.duplicateCandidates(r);
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No other report within 50m. Approve or reject instead.')));
      return;
    }
    final chosen = await showDialog<NearbyReport>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pick the original report'),
        children: candidates
            .map((c) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, c),
                  child: Text(
                      '${c.distanceM.round()}m · ${kConditionLabels[c.condition] ?? c.condition} · ${kStatusLabels[c.status]}'),
                ))
            .toList(),
      ),
    );
    if (chosen != null && context.mounted) {
      await _act(context, ref, admin.markDuplicate(r.id, chosen.id),
          'Marked as duplicate');
    }
  }

  /// Tapping a card opens the detail screen, which returns the pressed button as a
  /// string so the existing handlers (_act / _duplicate) can be reused as they are.
  Future<void> _openDetail(
      BuildContext context, WidgetRef ref, Report r) async {
    final action = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(report: r, showActions: true),
      ),
    );
    if (action == null || !context.mounted) return;
    final admin = ref.read(adminServiceProvider);
    switch (action) {
      case 'approve':
        await _act(context, ref, admin.approve(r.id), 'Approved');
      case 'reject':
        await _act(context, ref, admin.reject(r.id), 'Rejected');
      case 'duplicate':
        await _duplicate(context, ref, r);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingReportsProvider);
    final admin = ref.read(adminServiceProvider);
    final fmt = DateFormat('MM-dd HH:mm');

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(pendingReportsProvider),
      child: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 120),
              Center(child: Text('No reports waiting for review.')),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final r = list[i];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tapping the top of the card (photo and details) opens the detail screen
                      InkWell(
                        onTap: () => _openDetail(context, ref, r),
                        borderRadius: BorderRadius.circular(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SignedPhoto(path: r.photoPath, size: 72),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      kConditionLabels[r.condition] ??
                                          r.condition,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  Text(fmt.format(r.reportedAt),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey)),
                                  Text(
                                      r.address == null
                                          ? '${r.lat.toStringAsFixed(5)}, ${r.lng.toStringAsFixed(5)}'
                                          : romanizeAddress(r.address),
                                      style:
                                          const TextStyle(fontSize: 12)),
                                  if (r.description.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 4),
                                      child: Text(r.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13)),
                                    ),
                                ],
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 4, top: 22),
                              child: Icon(Icons.chevron_right,
                                  size: 20, color: Color(0xFFC6CEC9)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: () => _act(context, ref,
                                  admin.approve(r.id), 'Approved'),
                              child: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _act(context, ref,
                                  admin.reject(r.id), 'Rejected'),
                              child: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _duplicate(context, ref, r),
                              child: const Text('Duplicate'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
