import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// BikeReclaim 디자인 시스템 v2 — Claude Design 시안(BikeReclaim UI.html) 이식
/// 토큰 출처: 시안의 인라인 스타일 (색/라운드/그림자/타이포)
class AppColors {
  // 브랜드
  static const brandTeal = Color(0xFF05A1A2); // BIKE LOOP 워드마크 색
  static const primary = Color(0xFF1B7742);
  static const primaryPressed = Color(0xFF166438);
  static const primarySoft = Color(0xFFE9F3ED);
  static const accentOrange = Color(0xFFE8590C);

  // 뉴트럴 (시안 그대로)
  static const bg = Color(0xFFF7F9F7); // 화면 배경
  static const card = Colors.white;
  static const border = Color(0xFFE3E8E4);
  static const ink = Color(0xFF17261D); // 제목/본문
  static const sub = Color(0xFF4A554E); // 보조 텍스트
  static const muted = Color(0xFF8B958E); // 흐린 텍스트
  static const faint = Color(0xFF9AA69E); // 플레이스홀더
  static const dateGray = Color(0xFFB0B9B3);
  static const chevron = Color(0xFFC6CEC9);

  // 상태 배지 (시안: 처리중=주황, 완료=초록)
  static const pendingBg = Color(0xFFFFF3E4);
  static const pendingFg = Color(0xFFC2620A);
  static const doneBg = Color(0xFFE9F3ED);
  static const doneFg = Color(0xFF166438);
  static const grayBg = Color(0xFFEEF1EE);
  static const grayFg = Color(0xFF6B7671);

  // 그림자
  static const shadowCard = Color(0x0F14281E); // rgba(20,40,30,0.06)쯤
  static const shadowCta = Color(0x471B7742); // rgba(27,119,66,0.28)

  // 하위 호환 별칭 (기존 화면 코드용)
  static const textMain = ink;
  static const textSub = muted;
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.bg,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      iconTheme: IconThemeData(color: AppColors.sub),
    ),

    // 시안 카드: 보더 없음 + 아주 부드러운 그림자, radius 20
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 3,
      shadowColor: AppColors.shadowCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      margin: EdgeInsets.zero,
    ),

    // 시안 CTA: radius 18, 18px 굵은 글씨, 초록 그림자
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.pressed)
                ? AppColors.primaryPressed
                : AppColors.primary),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(56)),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        )),
        textStyle: const WidgetStatePropertyAll(TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        )),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.sub,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
      hintStyle: const TextStyle(color: AppColors.faint, fontSize: 15),
    ),

    // 시안 칩: pill(100px), 선택=초록/흰, 비선택=흰+얇은 보더
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AppColors.primary,
      side: const BorderSide(color: AppColors.border),
      labelStyle: const TextStyle(
          color: AppColors.sub, fontWeight: FontWeight.w600, fontSize: 14),
      secondaryLabelStyle: const TextStyle(
          color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: AppColors.primarySoft,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primary : AppColors.muted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primary : AppColors.muted,
        );
      }),
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),

    textTheme: base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
  );
}

/// 상태 → (배경, 글자) — 시안 배지 팔레트
(Color, Color) statusColors(String status) => switch (status) {
      'collected' => (AppColors.doneBg, AppColors.doneFg),
      'rejected' || 'duplicate' => (AppColors.grayBg, AppColors.grayFg),
      // submitted/approved/scheduled = "처리중" 계열 (주황)
      _ => (AppColors.pendingBg, AppColors.pendingFg),
    };

/// 상태 배지 (시안: pill, 12px w700)
class StatusChip extends StatelessWidget {
  final String label;
  final String status;
  const StatusChip({super.key, required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// BIKE LOOP 워드마크 (Varela Round + #05A1A2)
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  final String? suffix; // 예: '관리자'
  const BrandWordmark({super.key, this.fontSize = 24, this.suffix});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          'BIKE LOOP',
          style: GoogleFonts.varelaRound(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.brandTeal,
            letterSpacing: 0.5,
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(width: 8),
          Text(suffix!,
              style: TextStyle(
                  fontSize: fontSize * 0.72,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink)),
        ],
      ],
    );
  }
}

/// 섹션 제목 (시안: 15px w700 + 초록 별표)
class SectionTitle extends StatelessWidget {
  final String text;
  final bool required;
  final String? hint;
  const SectionTitle(this.text,
      {super.key, this.required = false, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.ink)),
        if (required)
          const Text(' *',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(hint!,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted)),
        ],
      ],
    );
  }
}
