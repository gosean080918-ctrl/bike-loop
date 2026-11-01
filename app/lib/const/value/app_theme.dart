import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// BIKE LOOP design system v2, ported from the design mockup (BikeReclaim UI.html)
/// Tokens come from the mockup's inline styles: color, radius, shadow, typography
class AppColors {
  // Brand
  static const brandTeal = Color(0xFF05A1A2); // BIKE LOOP wordmark color
  static const primary = Color(0xFF1B7742);
  static const primaryPressed = Color(0xFF166438);
  static const primarySoft = Color(0xFFE9F3ED);
  static const accentOrange = Color(0xFFE8590C);

  // Neutrals, exactly as in the mockup
  static const bg = Color(0xFFF7F9F7); // screen background
  static const card = Colors.white;
  static const border = Color(0xFFE3E8E4);
  static const ink = Color(0xFF17261D); // headings and body text
  static const sub = Color(0xFF4A554E); // secondary text
  static const muted = Color(0xFF8B958E); // dimmed text
  static const faint = Color(0xFF9AA69E); // placeholder
  static const dateGray = Color(0xFFB0B9B3);
  static const chevron = Color(0xFFC6CEC9);

  // Status badges (mockup: in-progress = orange, done = green)
  static const pendingBg = Color(0xFFFFF3E4);
  static const pendingFg = Color(0xFFC2620A);
  static const doneBg = Color(0xFFE9F3ED);
  static const doneFg = Color(0xFF166438);
  static const grayBg = Color(0xFFEEF1EE);
  static const grayFg = Color(0xFF6B7671);

  // Shadow
  static const shadowCard = Color(0x0F14281E); // roughly rgba(20,40,30,0.06)
  static const shadowCta = Color(0x471B7742); // rgba(27,119,66,0.28)

  // Backwards-compatible aliases for older screen code
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

    // Mockup card: no border, very soft shadow, radius 20
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

    // Mockup CTA: radius 18, 18px bold text, green shadow
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

    // Mockup chip: pill (100px); selected = green on white, unselected = white with a thin border
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

/// Status -> (background, foreground), from the mockup's badge palette
(Color, Color) statusColors(String status) => switch (status) {
      'collected' => (AppColors.doneBg, AppColors.doneFg),
      'rejected' || 'duplicate' => (AppColors.grayBg, AppColors.grayFg),
      // submitted / approved / scheduled are the "in progress" family (orange)
      _ => (AppColors.pendingBg, AppColors.pendingFg),
    };

/// Status badge (mockup: pill, 12px w700)
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

/// BIKE LOOP wordmark (Varela Round, #05A1A2)
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  final String? suffix; // e.g. 'Admin'
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

/// Section heading (mockup: 15px w700 with a green asterisk)
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
