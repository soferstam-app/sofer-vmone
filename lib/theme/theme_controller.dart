import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/hebrew_clock.dart';
import '../storage_service.dart';
import 'app_theme.dart';

/// Holds which look the app is wearing, and why.
///
/// Two settings feed into one answer:
///
/// * [choice] — the look the writer picked, and the one shown in settings.
/// * [autoNight] — when on, the app wears [AppTheme.layla] between nightfall
///   and dawn whatever was picked, because that is when the bright screen
///   stops being usable.
///
/// [effective] is what actually gets rendered. Keeping the two apart means the
/// settings screen never has to lie about what the writer chose just because
/// the sun has set.
class ThemeController extends ChangeNotifier {
  ThemeController({StorageService? storage})
      : _storage = storage ?? StorageService();

  final StorageService _storage;

  AppTheme _choice = AppTheme.modern;
  bool _autoNight = false;
  Brightness _systemBrightness = Brightness.light;
  Timer? _nightWatch;
  bool _loaded = false;

  AppTheme get choice => _choice;
  bool get autoNight => _autoNight;
  bool get isLoaded => _loaded;

  /// True when the auto switch — not the writer's choice — is what is putting
  /// the app in night dress. The settings screen says so, so the writer is not
  /// left wondering why the app looks different from what they selected.
  bool get nightByClock =>
      _autoNight && _choice != AppTheme.layla && _isAfterNightfall();

  /// Which of the three the app is wearing.
  ///
  /// Night dress means the night version *of the look the writer chose*, not
  /// one particular theme. Layla is the parchment family after dark, so it is
  /// where klaf goes — but modern has a dark mode of its own, and a writer who
  /// picked modern and turned on the automatic switch was handed parchment at
  /// nightfall: a different app, not a darker one.
  AppTheme get effective {
    if (!nightByClock) return _choice;
    return _choice == AppTheme.modern ? AppTheme.modern : AppTheme.layla;
  }

  /// Modern carries its night in its brightness rather than in a second theme,
  /// so the switch has to reach it that way.
  Brightness get _brightness =>
      nightByClock && _choice == AppTheme.modern
          ? Brightness.dark
          : _systemBrightness;

  ThemeData get themeData =>
      AppThemeBuilder.build(effective, system: _brightness);

  Future<void> load() async {
    _choice = await _storage.getAppTheme();
    _autoNight = await _storage.getAutoNightTheme();
    _loaded = true;
    _restartNightWatch();
    notifyListeners();
  }

  Future<void> setChoice(AppTheme theme) async {
    if (theme == _choice) return;
    _choice = theme;
    await _storage.setAppTheme(theme);
    _restartNightWatch();
    notifyListeners();
  }

  Future<void> setAutoNight(bool value) async {
    if (value == _autoNight) return;
    _autoNight = value;
    await _storage.setAutoNightTheme(value);
    _restartNightWatch();
    notifyListeners();
  }

  /// Kept in step with the platform, so the modern look follows the system's
  /// light or dark setting the way every other app on the machine does.
  void setSystemBrightness(Brightness brightness) {
    if (brightness == _systemBrightness) return;
    _systemBrightness = brightness;
    if (_choice == AppTheme.modern && !nightByClock) notifyListeners();
  }

  /// Whether the app should currently be dressed for night.
  ///
  /// Night runs from nightfall until dawn, so the small hours count as night
  /// rather than as an early morning.
  bool _isAfterNightfall() {
    final now = DateTime.now();
    final nightfall = HebrewClock.nightfall(now);
    final dawn = HebrewClock.dawn(now);
    if (nightfall == null || dawn == null) return false;
    return now.isAfter(nightfall) || now.isBefore(dawn);
  }

  /// Re-checks the clock periodically rather than at an exact moment.
  ///
  /// Nightfall moves daily and the app may be asleep when it passes, so a
  /// scheduled one-shot would be missed. A five-minute check costs nothing and
  /// only notifies when the answer actually changes.
  void _restartNightWatch() {
    _nightWatch?.cancel();
    if (!_autoNight) return;

    var wasNight = nightByClock;
    _nightWatch = Timer.periodic(const Duration(minutes: 5), (_) {
      final isNight = nightByClock;
      if (isNight != wasNight) {
        wasNight = isNight;
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _nightWatch?.cancel();
    super.dispose();
  }
}
