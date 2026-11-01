import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../const/model/report.dart';
import '../../const/value/app_theme.dart';
import '../../const/value/constants.dart';
import '../../utils/romanize.dart';

/// ADM-10: report detail view
///
/// Opened by tapping a card on the review tab. It shows the photo large (pinch to zoom)
/// along with the full description, address and coordinates, and lets the admin approve,
/// reject or mark as duplicate right there.
///
/// This screen performs no action itself; it returns a string via
/// `Navigator.pop(context, 'approve')` so the calling tab reuses its existing handlers.
/// (marking a duplicate needs a candidate-picker dialog, which is cleaner left in the tab)
class ReportDetailScreen extends StatelessWidget {
  final Report report;

  /// The bottom action bar appears only for reports still awaiting review
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
        title: const Text('Report detail', style: TextStyle(fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // -- Photo; tap to open fullscreen --
          _Photo(path: r.photoPath),
          const SizedBox(height: 16),

          // -- Condition and status --
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

          // -- Basic details --
          _card(
            title: 'Report',
            child: Column(
              children: [
                _row('Reported', fmt.format(r.reportedAt)),
                _row('Address', romanizeAddress(r.address).isEmpty ? '(no address)' : romanizeAddress(r.address)),
                _row('Coordinates', coord, copyable: true, context: context),
                if (r.priority > 0) _row('Priority', '${r.priority}'),
                if (r.collectedAt != null)
                  _row('Collected', fmt.format(r.collectedAt!)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // -- Reporter; readable by admins only, enforced by RLS on profiles --
          _card(
            title: 'Reporter',
            child: _Reporter(reporterId: r.reporterId),
          ),
          const SizedBox(height: 12),

          // -- Description --
          _card(
            title: 'Description',
            child: Text(
              r.description.isEmpty ? '(no description)' : r.description,
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

      // -- Bottom action bar --
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
                        child: const Text('Approve'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, 'reject'),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pop(context, 'duplicate'),
                        child: const Text('Duplicate'),
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
                          const SnackBar(content: Text('Copied')));
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

/// Reporter details: email and display name, read from profiles.
///
/// Privacy note: the profiles_select policy allows only "self or admin", so an ordinary
/// user never receives this at all — it is blocked at the database level.
/// The email column is populated once supabase/05_profile_email.sql has been applied.
class _Reporter extends StatelessWidget {
  final String reporterId;
  const _Reporter({required this.reporterId});

  @override
  Widget build(BuildContext context) {
    if (reporterId.isEmpty) return const _ReporterText('(no reporter info)');

    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('profiles')
          .select('email, display_name')
          .eq('id', reporterId)
          .maybeSingle(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _ReporterText('Loading…');
        }
        if (snap.hasError || snap.data == null) {
          // 05_profile_email.sql not applied, or no permission
          return const _ReporterText('(unavailable)');
        }

        final email = (snap.data!['email'] as String?)?.trim() ?? '';
        final name = (snap.data!['display_name'] as String?)?.trim() ?? '';

        if (email.isEmpty) return _ReporterText(name.isEmpty ? '(no email)' : name);

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
                          const SnackBar(content: Text('Email copied')));
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
                  label: const Text('Mail'),
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

/// Creates the signed URL once and reuses it for both the inline image and the fullscreen view
class _Photo extends StatelessWidget {
  final String path;
  const _Photo({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return _placeholder('No photo');

    return FutureBuilder<String>(
      future: Supabase.instance.client.storage
          .from(kPhotoBucket)
          .createSignedUrl(path, 3600),
      builder: (context, snap) {
        if (snap.hasError) return _placeholder('Could not load photo');
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
                          _placeholder('Could not load photo')),
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
                      Text('Tap to zoom',
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

/// Fullscreen photo viewer: pinch zoom, double-tap zoom, drag to pan
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
        title: const Text('Photo',
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
              errorBuilder: (_, __, ___) => const Text('Could not load photo',
                  style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }
}
