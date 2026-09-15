import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../state_management/providers.dart';
import '../component/signed_photo.dart';

/// RPT-06: 내 신고 이력 — Claude Design 시안 ③ 레이아웃
class MyReportsTab extends ConsumerWidget {
  const MyReportsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);
    final fmt = DateFormat('MM.dd');

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myReportsProvider),
      child: reports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          final done =
              list.where((r) => r.status == 'collected').length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              // 시안 헤더: 큰 제목 + 요약
              const Text('내 신고',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: AppColors.ink)),
              const SizedBox(height: 4),
              Text('총 ${list.length}건 · 수거 완료 $done건',
                  style: const TextStyle(
                      fontSize: 14, color: AppColors.muted)),
              const SizedBox(height: 16),

              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Center(
                      child: Text('아직 신고 내역이 없습니다.',
                          style: TextStyle(color: AppColors.muted))),
                ),

              // 시안 카드: 사진72 + [배지·날짜 / 주소 / 유형] + ›
              ...list.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                              color: AppColors.shadowCard,
                              blurRadius: 12,
                              offset: Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SignedPhoto(
                                path: r.photoPath, size: 72),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusChip(
                                      label: kStatusLabels[r.status] ??
                                          r.status,
                                      status: r.status,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(fmt.format(r.reportedAt),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.dateGray)),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  r.address ??
                                      '${r.lat.toStringAsFixed(4)}, ${r.lng.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: AppColors.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  kConditionLabels[r.condition] ??
                                      r.condition,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              color: AppColors.chevron, size: 22),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
