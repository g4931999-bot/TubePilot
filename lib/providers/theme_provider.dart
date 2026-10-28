import 'package:flutter/material.dart';

/// Festival backgrounds available to the app. Each entry carries the asset
/// path of its background image. Add a new festival here (one line) and it
/// becomes selectable through [ThemeProvider.setActiveFestival].
enum FestivalTheme {
  none(null),
  diwali('assets/images/diwali_bg.png');

  const FestivalTheme(this.backgroundAsset);

  /// Asset path of the full-screen background, or null for [none].
  final String? backgroundAsset;
}

/// ⚠️ Dark mode removed per request — the app is light-only now. Kept as a
/// (much simpler) ChangeNotifier, rather than deleting the class outright,
/// since main.dart's MultiProvider and MaterialApp.themeMode still
/// reference it — this way neither of those needed touching, and if dark
/// mode ever comes back, this is the one place to restore it.
///
/// Festival theme: a single switch here controls the background for every
/// screen that is wrapped in AppBrandBackground. Turning it off restores
/// the normal background everywhere; no screen code needs to change.
class ThemeProvider extends ChangeNotifier {
  /// Central switches — change these two lines when a festival starts/ends.
  static const bool kFestivalEnabledByDefault = true;
  static const FestivalTheme kDefaultFestival = FestivalTheme.diwali;

  bool get isDark => false;
  ThemeMode get themeMode => ThemeMode.light;

  bool _festivalEnabled = kFestivalEnabledByDefault;
  FestivalTheme _activeFestival = kDefaultFestival;

  bool get festivalEnabled => _festivalEnabled;
  FestivalTheme get activeFestival => _activeFestival;

  /// Asset path of the active festival background, or null when festival
  /// mode is off (or no festival is selected). AppBrandBackground treats
  /// null as "use the normal background".
  String? get festivalBackgroundAsset =>
      _festivalEnabled ? _activeFestival.backgroundAsset : null;

  void setFestivalEnabled(bool value) {
    if (_festivalEnabled == value) return;
    _festivalEnabled = value;
    notifyListeners();
  }

  void toggleFestival() => setFestivalEnabled(!_festivalEnabled);

  void setActiveFestival(FestivalTheme festival) {
    if (_activeFestival == festival) return;
    _activeFestival = festival;
    notifyListeners();
  }
}