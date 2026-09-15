import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';

/// ADM-10: 신고 상세 보기
///
/// 검토 탭에서 카드를 탭하면 열린다. 사진을 크게 보고(핀치 확대 지원),
/// 잘려 보이던 설명·주소·좌표를 전부 확인한 뒤 그 자리에서 승인/반려/중복 처리.
///
/// 액션은 이 화면이 직접 수행하지 않고 `Navigator.pop(context, 'approve')`처럼
/// 문자열을 돌려준다 → 호출한 탭이 기존 처리 로직을 그대로 재사용한다.
/// (중복 처리는 후보 선택 다이얼로그가 필요해서 탭 쪽에 남겨두는 게 깔끔함)
class ReportDetailScreen extends StatelessWidget {
  final Report report;

  /// 검토 대기(submitted) 건에서만 하단 액션 바를 노출
  final bool showActions;

  const ReportDetailScreen({
    super.key,
    required this.report,
    this.showActions = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = report;
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final coord =
        '${r.lat.toStringAsFixed(6)}, ${r.lng.toStringAsFixed(6)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('신고 상세', style: TextStyle(fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // ── 사진 (탭하면 전체화면 확대) ──
          _Photo(path: r.photoPath),
          const SizedBox(height: 16),

          // ── 유형 + 상태 ──
          Row(
            children: [
              Expanded(
                child: Text(
                  kConditionLabels[r.condition] ?? r.condition,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.ink,
                  ),
                ),
              ),
              StatusChip(
                label: kStatusLabels[r.status] ?? r.status,
                status: r.status,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── 기본 정보 ──
          _card(
            title: '신고 정보',
            child: Column(
              children: [
                _row('신고 일시', fmt.format(r.reportedAt)),
                _row('주소', r.address ?? '(주소 정보 없음)'),
                _row('좌표', coord, copyable: true, context: context),
                if (r.priority > 0) _row('우선순위', '${r.priority}'),
                if (r.collectedAt != null)
                  _row('수거 완료', fmt.format(r.collectedAt!)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── 신고자 (관리자만 조회 가능 — profiles RLS) ──
          _card(
            title: '신고자',
            child: _Reporter(reporterId: r.reporterId),
          ),
          const SizedBox(height: 12),

          // ── 상세 설명 ──
          _card(
            title: '상세 설명',
            child: Text(
              r.description.isEmpty ? '(작성된 설명이 없습니다)' : r.description,
              style: TextStyle(
                fontSize: 15,
                height: 1.55,
                color: r.description.isEmpty
                    ? AppColors.muted
                    : AppColors.ink,
              ),
            ),
          ),
        ],
      ),

      // ── 하단 액션 바 ──
      bottomNavigationBar: !showActions
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, 'approve'),
                        child: const Text('승인'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, 'reject'),
                        child: const Text('반려'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, 'duplicate'),
                        child: const Text('중복'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card({required String title, required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            Text(title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );

  Widget _row(String k, String v,
      {bool copyable = false, BuildContext? context}) {
    final text = Text(
      v,
      style: const TextStyle(
          fontSize: 14, height: 1.4, color: AppColors.ink),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 13.5, color: AppColors.muted)),
          ),
          Expanded(
            child: copyable && context != null
                ? InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: v));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('복사했습니다')));
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 6),
                        const Icon(Icons.copy_rounded,
                            size: 15, color: AppColors.chevron),
                      ],
                    ),
                  )
                : text,
          ),
        ],
      ),
    );
  }
}

/// 신고자 정보 — profiles에서 이메일/닉네임 조회.
///
/// 개인정보 메모: profiles_select 정책이 "본인 또는 관리자"만
/// 허용하므로 일반 사용자에겐 애초에 내려오지 않는다(DB 레벨 차단).
/// email 컴럼은 supabase/05_profile_email.sql 적용 후부터 채워진다.
class _Reporter extends StatelessWidget {
  final String reporterId;
  const _Reporter({required this.reporterId});

  @override
  Widget build(BuildContext context) {
    if (reporterId.isEmpty) return const _ReporterText('(신고자 정보 없음)');

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('profiles')
          .select('email, display_name')
          .eq('id', reporterId)
          .maybeSingle(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ReporterText('불러오는 중…');
        }
        if (snap.hasError || snap.data == null) {
          // 05_profile_email.sql 미적용이거나 권한 없음
          return const _ReporterText('(조회 불가 — 05_profile_email.sql 확인)');
        }

        final email = (snap.data!['email'] as String?)?.trim() ?? '';
        final name = (snap.data!['display_name'] as String?)?.trim() ?? '';

        if (email.isEmpty) return _ReporterText(name.isEmpty ? '(이메일 없음)' : name);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: email));
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('이메일을 복사했습니다')));
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(email,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  color: AppColors.ink)),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.copy_rounded,
                            size: 15, color: AppColors.chevron),
                      ],
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                    Uri(scheme: 'mailto', path: email),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('메일'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ReporterText extends StatelessWidget {
  final String text;
  const _ReporterText(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 14, color: AppColors.muted));
}

/// 서명 URL을 한 번만 만들어서 인라인 표시 + 전체화면 확대에 함께 쓴다
class _Photo extends StatelessWidget {
  final String path;
  const _Photo({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return _placeholder('사진 없음');

    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from(kPhotoBucket)
          .createSignedUrl(path, 3600),
      builder: (context, snap) {
        if (snap.hasError) return _placeholder('사진을 불러오지 못했습니다');
        if (!snap.hasData) {
          return _placeholder(null, spinner: true);
        }
        final url = snap.data!;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => _FullScreenPhoto(url: url),
            ),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _placeholder('사진을 불러오지 못했습니다')),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_out_map_rounded,
                          size: 14, color: Colors.white),
                      SizedBox(width: 5),
                      Text('탭하면 확대',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _placeholder(String? msg, {bool spinner = false}) => AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.grayBg,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Center(
            child: spinner
                ? const CircularProgressIndicator(strokeWidth: 2)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.pedal_bike,
                          size: 44, color: AppColors.chevron),
                      const SizedBox(height: 6),
                      Text(msg ?? '',
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.muted)),
                    ],
                  ),
          ),
        ),
      );
}

/// 전체화면 사진 뷰어 — 핀치 줌 / 더블탭 줌 / 드래그
class _FullScreenPhoto extends StatefulWidget {
  final String url;
  const _FullScreenPhoto({required this.url});

  @override
  State<_FullScreenPhoto> createState() => _FullScreenPhotoState();
}

class _FullScreenPhotoState extends State<_FullScreenPhoto> {
  final _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleZoom(TapDownDetails d) {
    if (_ctrl.value != Matrix4.identity()) {
      _ctrl.value = Matrix4.identity();
    } else {
      final p = d.localPosition;
      _ctrl.value = Matrix4.identity()
        ..translate(-p.dx * 1.5, -p.dy * 1.5)
        ..scale(2.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('사진 크게 보기',
            style: TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: GestureDetector(
        onDoubleTapDown: _toggleZoom,
        onDoubleTap: () {},
        child: InteractiveViewer(
          transformationController: _ctrl,
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text('사진을 불러오지 못했습니다',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
