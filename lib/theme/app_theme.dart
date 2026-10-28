import 'package:flutter/material.dart';

class AppColors {
  // ---------------- PLUM BRANDING (v2) ----------------
  // Replaces the earlier Neon Dusk (cyan) palette. Property names kept
  // identical to before (purple/purpleLight/pink/diamond etc.) so every
  // existing screen referencing AppColors.purple continues to work
  // unchanged — only the underlying hex values moved to Plum.
  static const purple = Color(0xFF4B1D3F);       // PRIMARY BRAND — Plum
  static const purpleLight = Color(0xFF7A3A67);  // lighter plum tint (hover/active/glow)
  static const pink = Color(0xFF2A0F22);         // secondary / gradient end — near-black plum
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const diamond = Color(0xFFD4A017);      // warm gold — kept distinct from plum so the
                                                  // diamond/currency icon doesn't blend into
                                                  // primary-colored UI chrome around it.

  // ---------------- FESTIVAL ACCENTS (additive) ----------------
  // Used by the festival background system. Approximate values — tune to
  // match the final festival artwork. Existing screens don't reference these.
  static const festivalIvory = Color(0xFFFFF8EC);    // warm ivory base behind festival image
  static const festivalGold = Color(0xFFE2C275);     // soft gold accent
  static const festivalMagenta = Color(0xFF8A1F62);  // dark magenta accent

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, pink],
  );

  // Light theme surface colors — pure white background, pure black text,
  // per spec. Cards stay white too (not a separate tint) so the "pure
  // white background" requirement holds everywhere; hierarchy comes from
  // the plum-tinted border instead of a background-color difference.
  static const lightBg = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightCard2 = Color(0xFFF7F0F5);   // faint plum-white tint, used only for
                                                  // secondary "sunken" surfaces (chip backgrounds,
                                                  // input fill) — never the scaffold/card itself.
  static const lightBorder = Color(0xFFE3CBDA);  // subtle plum-tinted border
  static const lightText = Color(0xFF000000);    // pure black, per spec
  static const lightTextDim = Color(0xFF54494F);

  // Dark theme surface colors. ⚠️ CONTRAST FIX: background/card colors
  // updated to the exact values requested (#121212 / #1E1B2E) since the
  // previous plum-tinted dark values (#190711/#2A0F22) were reported as
  // low-contrast against secondary text and icons in practice. Secondary
  // text now uses literal Colors.white70 (not a custom tinted hex) so
  // contrast is guaranteed by definition rather than tuned by eye.
  static const darkBg = Color(0xFF121212);
  static const darkCard = Color(0xFF1E1B2E);
  static const darkCard2 = Color(0xFF2A263D);    // slightly lighter "sunken" surface
  static const darkBorder = Color(0xFF3D3854);   // visible against #1E1B2E without being loud
  static const darkText = Colors.white;          // pure white, per spec
  static const darkTextDim = Colors.white70;     // exact literal per spec (was a custom tint)
}

class AppTheme {
  static ThemeData light = _build(
    brightness: Brightness.light,
    bg: AppColors.lightBg,
    card: AppColors.lightCard,
    card2: AppColors.lightCard2,
    border: AppColors.lightBorder,
    text: AppColors.lightText,
    textDim: AppColors.lightTextDim,
  );

  static ThemeData dark = _build(
    brightness: Brightness.dark,
    bg: AppColors.darkBg,
    card: AppColors.darkCard,
    card2: AppColors.darkCard2,
    border: AppColors.darkBorder,
    text: AppColors.darkText,
    textDim: AppColors.darkTextDim,
  );

  /// Used by AppBrandBackground (only while a background image is showing)
  /// so the Scaffold/AppBar inside it don't paint an opaque colour over the
  /// image. Applied to that subtree only — the app-wide theme is untouched.
  static ThemeData withTransparentSurfaces(ThemeData base) {
    return base.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
      ),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color card,
    required Color card2,
    required Color border,
    required Color text,
    required Color textDim,
  }) {
    final isDark = brightness == Brightness.dark;

    // Plum (0xFF4B1D3F) is dark enough that white text on top of it reads
    // cleanly in both modes — unlike the old bright-cyan palette, no
    // special-cased dark-text-on-accent override is needed here.
    const onPrimaryForPlum = Colors.white;

    final base = ColorScheme(
      brightness: brightness,
      primary: AppColors.purple,
      onPrimary: onPrimaryForPlum,
      primaryContainer: AppColors.purple.withValues(alpha: isDark ? 0.28 : 0.10),
      onPrimaryContainer: isDark ? AppColors.purpleLight : AppColors.purple,
      secondary: isDark ? AppColors.purpleLight : AppColors.pink,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.pink.withValues(alpha: isDark ? 0.24 : 0.10),
      onSecondaryContainer: text,
      tertiary: AppColors.diamond,
      onTertiary: Colors.white,
      error: AppColors.red,
      onError: Colors.white,
      errorContainer: AppColors.red.withValues(alpha: isDark ? 0.20 : 0.10),
      onErrorContainer: AppColors.red,
      surface: card,
      onSurface: text,
      surfaceContainerHighest: card2,
      outline: border,
      outlineVariant: border.withValues(alpha: 0.6),
      shadow: Colors.black,
    );

    final splash = InkSparkle.splashFactory;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: base,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Roboto',
      splashFactory: splash,
      visualDensity: VisualDensity.standard,
      splashColor: AppColors.purple.withValues(alpha: 0.08),
      highlightColor: Colors.transparent,

      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        iconTheme: IconThemeData(color: text),
      ),

      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.5 : 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.purple, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red, width: 1.6),
        ),
        labelStyle: TextStyle(color: textDim, fontSize: 13),
        floatingLabelStyle: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: textDim.withValues(alpha: 0.7)),
        counterStyle: TextStyle(color: textDim.withValues(alpha: 0.7), fontSize: 11),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: onPrimaryForPlum,
          disabledBackgroundColor: AppColors.purple.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: onPrimaryForPlum,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.purple,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: text),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: card2,
        selectedColor: AppColors.purple.withValues(alpha: 0.16),
        disabledColor: card2.withValues(alpha: 0.5),
        labelStyle: TextStyle(color: text, fontSize: 12.5, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: AppColors.purple, fontSize: 12.5, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(color: border),
        ),
        side: BorderSide.none,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? Colors.white70 : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.purple;
          return border;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.purple;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: border, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.purple;
          return textDim;
        }),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.purple,
        linearTrackColor: border,
        circularTrackColor: border,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: isDark ? 0.6 : 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: textDim, fontSize: 13.5, height: 1.4),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        dragHandleColor: border,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkCard2 : text,
        contentTextStyle: TextStyle(color: isDark ? text : Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.purple,
        unselectedLabelColor: textDim,
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        indicatorColor: AppColors.purple,
        dividerColor: border,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard2 : text,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: isDark ? text : Colors.white, fontSize: 12),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border),
        ),
        textStyle: TextStyle(color: text, fontSize: 13.5),
      ),

      listTileTheme: ListTileThemeData(
        iconColor: textDim,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      textTheme: TextTheme(
        displayLarge: TextStyle(color: text, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        displayMedium: TextStyle(color: text, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        headlineLarge: TextStyle(color: text, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        headlineMedium: TextStyle(color: text, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        headlineSmall: TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleLarge: TextStyle(color: text, fontSize: 17, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: text, fontSize: 15, fontWeight: FontWeight.w700),
        titleSmall: TextStyle(color: text, fontSize: 13.5, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(color: text, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: text, fontSize: 13.5, height: 1.45),
        bodySmall: TextStyle(color: textDim, fontSize: 12, height: 1.4),
        labelLarge: TextStyle(color: text, fontSize: 14, fontWeight: FontWeight.w600),
        labelMedium: TextStyle(color: textDim, fontSize: 12, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(color: textDim, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),

      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),

      extensions: [
        AppSurfaceColors(card2: card2, textDim: textDim, border: border),
      ],
    );
  }
}

/// Extra theme colors not covered by ColorScheme (card2 background, dim text, border)
class AppSurfaceColors extends ThemeExtension<AppSurfaceColors> {
  final Color card2;
  final Color textDim;
  final Color border;

  const AppSurfaceColors({required this.card2, required this.textDim, required this.border});

  @override
  AppSurfaceColors copyWith({Color? card2, Color? textDim, Color? border}) {
    return AppSurfaceColors(
      card2: card2 ?? this.card2,
      textDim: textDim ?? this.textDim,
      border: border ?? this.border,
    );
  }

  @override
  AppSurfaceColors lerp(ThemeExtension<AppSurfaceColors>? other, double t) {
    if (other is! AppSurfaceColors) return this;
    return AppSurfaceColors(
      card2: Color.lerp(card2, other.card2, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}

extension AppThemeExt on BuildContext {
  AppSurfaceColors get surfaces => Theme.of(this).extension<AppSurfaceColors>()!;
}