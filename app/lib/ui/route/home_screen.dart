import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../const/value/app_theme.dart';
import '../../state_management/providers.dart';
import '../tab/admin_dashboard_tab.dart';
import '../tab/admin_inventory_tab.dart';
import '../tab/admin_jobs_tab.dart';
import '../tab/admin_review_tab.dart';
import '../tab/map_tab.dart';
import '../tab/my_reports_tab.dart';
import '../tab/report_tab.dart';

/// AUTH-03: 역할에 따라 탭 구성 분기
/// 일반: 지도 / 신고 / 내 신고
/// 관리자: 지도 / 검토 / 작업 (+ 신고도 가능하도록 유지)
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(myProfileProvider);
    final isAdmin = profile.value?.isAdmin ?? false;

    final tabs = isAdmin
        ? const [
            MapTab(),
            AdminReviewTab(),
            AdminJobsTab(),
            AdminInventoryTab(),
            AdminDashboardTab(),
          ]
        : const [MapTab(), ReportTab(), MyReportsTab()];
    final destinations = isAdmin
        ? const [
            NavigationDestination(icon: Icon(Icons.map), label: '지도'),
            NavigationDestination(
                icon: Icon(Icons.fact_check), label: '검토'),
            NavigationDestination(
                icon: Icon(Icons.local_shipping), label: '작업'),
            NavigationDestination(
                icon: Icon(Icons.inventory_2), label: '재고'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart), label: '통계'),
          ]
        : const [
            NavigationDestination(icon: Icon(Icons.map), label: '지도'),
            NavigationDestination(
                icon: Icon(Icons.add_a_photo), label: '신고'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long), label: '내 신고'),
          ];
    if (_index >= tabs.length) _index = 0;

    return Scaffold(
      appBar: AppBar(
        title: BrandWordmark(suffix: isAdmin ? '관리자' : null),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: tabs),
      // 관리자도 직접 신고할 수 있게 — 지도 탭에서만 표시
      floatingActionButton: (isAdmin && _index == 0)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_a_photo),
              label: const Text('신고',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('방치 자전거 신고')),
                    body: const ReportTab(),
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: destinations,
      ),
    );
  }
}
