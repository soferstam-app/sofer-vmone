import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../storage_service.dart';

/// The four deliberate reading sizes offered inside the app.
///
/// Named choices are easier to hit and understand than a fine slider when the
/// setting itself is being used because the current text is hard to see.
enum AppTextSize {
  regular(100, 1.0),
  large(125, 1.25),
  extraLarge(160, 1.6),
  maximum(200, 2.0);

  const AppTextSize(this.percent, this.factor);

  final int percent;
  final double factor;

  static AppTextSize fromPercent(int? value) => values.firstWhere(
        (option) => option.percent == value,
        orElse: () => regular,
      );
}

/// Owns the app-wide reading size and applies it immediately.
///
/// The larger of the operating-system choice and the in-app choice wins. We
/// do not multiply them: a writer who already chose 160% in Android and then
/// chooses 160% here asked for 160%, not an accidental 256%.
class AccessibilityController extends ChangeNotifier {
  AccessibilityController({StorageService? storage})
      : _storage = storage ?? StorageService();

  final StorageService _storage;
  AppTextSize _textSize = AppTextSize.regular;
  bool _loaded = false;

  AppTextSize get textSize => _textSize;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    _textSize =
        AppTextSize.fromPercent(await _storage.getInterfaceTextScalePercent());
    _loaded = true;
    notifyListeners();
  }

  Future<void> setTextSize(AppTextSize value) async {
    if (value == _textSize) return;
    _textSize = value;
    notifyListeners();
    await _storage.setInterfaceTextScalePercent(value.percent);
  }

  TextScaler scalerFor(TextScaler system) =>
      TextScaler.linear(math.max(system.scale(1), _textSize.factor));
}
