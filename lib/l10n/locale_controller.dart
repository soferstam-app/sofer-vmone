import 'package:flutter/foundation.dart';

import '../storage_service.dart';
import 'app_localizations.dart';

/// Only a genuinely blank installation is asked before onboarding.
///
/// Everyone else used a Hebrew-only build. Treating the operating system's
/// language as their choice would turn an ordinary update into an unsolicited
/// interface change.
bool shouldAskForLanguage({
  required bool hasExplicitChoice,
  required bool onboardingSeen,
  required bool hasProjects,
  required bool hasHistory,
}) =>
    !hasExplicitChoice && !onboardingSeen && !hasProjects && !hasHistory;

/// Owns the language selected for this installation.
///
/// An absent value means a build from before English existed. It opens in
/// Hebrew, so an update can never change an existing writer's interface merely
/// because Windows or Android happens to use English.
class LocaleController extends ChangeNotifier {
  LocaleController({StorageService? storage})
      : _storage = storage ?? StorageService();

  final StorageService _storage;
  AppLanguage _language = AppLanguage.hebrew;
  bool _loaded = false;
  bool _hasExplicitChoice = false;

  AppLanguage get language => _language;
  bool get isLoaded => _loaded;
  bool get hasExplicitChoice => _hasExplicitChoice;

  Future<void> load() async {
    final stored = AppLanguage.fromCode(await _storage.getAppLanguageCode());
    _hasExplicitChoice = stored != null;
    _language = stored ?? AppLanguage.hebrew;
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    final changed = language != _language || !_hasExplicitChoice;
    _language = language;
    _hasExplicitChoice = true;
    await _storage.setAppLanguageCode(language.code);
    if (changed) notifyListeners();
  }
}
