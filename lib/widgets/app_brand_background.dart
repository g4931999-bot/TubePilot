import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// The shared "off-white base + faint play-icon watermark" background
/// (same look as Splash) — factored out so Onboarding, Login/Signup, and
/// Profile Setup can all share exactly one implementation instead of
/// copy-pasted per screen. Splash screen itself is untouched and keeps
/// its own inline version.
///
/// Festival support: when ThemeProvider's festival mode is on, eligible
/// screens show the festival image instead of the watermark background.
/// Per-screen control:
///  * [excludeFromFestival]  — always keep the normal background.
///  * [backgroundAsset]      — use this image instead (screen-specific design).
///  * [customBackground]     — use this widget as the background.
///  * [foreground]           — decorations drawn above [child] (never block taps).
///  * [watermarkWhenNormal]  — set false for screens that have their own opaque
///                             Scaffold: in normal mode nothing extra is drawn
///                             behind them; in festival mode the image shows.
class AppBrandBackground extends StatelessWidget {
  final Widget child;
  final bool excludeFromFestival;
  final String? backgroundAsset;
  final Widget? customBackground;
  final Widget? foreground;
  final bool watermarkWhenNormal;

  const AppBrandBackground({
    super.key,
    required this.child,
    this.excludeFromFestival = false,
    this.backgroundAsset,
    this.customBackground,
    this.foreground,
    this.watermarkWhenNormal = true,
  });

  Widget _watermarkPattern() {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.07,
        child: GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 40),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 30,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
          ),
          itemCount: 32,
          itemBuilder: (context, index) => Icon(
            Icons.play_circle_outline_rounded,
            color: AppColors.purple,
            size: 42,
          ),
        ),
      ),
    );
  }

  Widget _imageBackground(BuildContext context, String asset) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Image.asset(
          asset,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          // Decode at screen resolution only, not the full source size.
          cacheWidth: (size.width * dpr).round(),
          // Missing/corrupt asset → quietly fall back to the normal look.
          errorBuilder: (context, error, stackTrace) => _watermarkPattern(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the festival asset actually changes.
    final festivalAsset = context.select<ThemeProvider, String?>(
      (p) => p.festivalBackgroundAsset,
    );

    Widget? background;
    if (customBackground != null) {
      background = customBackground;
    } else if (backgroundAsset != null) {
      background = _imageBackground(context, backgroundAsset!);
    } else if (!excludeFromFestival && festivalAsset != null) {
      background = _imageBackground(context, festivalAsset);
    }

    final usesImageBackground = background != null;
    final baseTheme = Theme.of(context);

    return Container(
      color: usesImageBackground
          ? AppColors.festivalIvory
          : const Color(0xFFFAF7FC),
      child: Stack(
        children: [
          Positioned.fill(
            child: background ??
                (watermarkWhenNormal ? _watermarkPattern() : const SizedBox.shrink()),
          ),
          // Theme wrapper is always present so toggling festival mode does
          // not change the widget structure (screen state is preserved).
          Theme(
            data: usesImageBackground
                ? AppTheme.withTransparentSurfaces(baseTheme)
                : baseTheme,
            child: child,
          ),
          if (foreground != null)
            Positioned.fill(child: IgnorePointer(child: foreground!)),
        ],
      ),
    );
  }
}