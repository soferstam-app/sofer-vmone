import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/app_assets.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/main.dart' show localeController, startBrowserApp;
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

import 'account_store.dart';

@JS('soferAccountLanguage')
external JSString? get _accountLanguage;

@JS('soferRememberAccountLanguage')
external JSFunction? get _rememberAccountLanguage;

@JS('soferRememberAccountLanguage')
external JSBoolean _saveAccountLanguage(JSString language);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final account = AccountStore.enabled;
  if (!account) {
    SharedPreferences.setPrefix('sofer_web_pilot.');
  }
  AppAssets.packageName = 'sofer_vmone';

  // Register package assets under the names used by the original theme.
  const fonts = {
    'Heebo': 'Heebo-var.ttf',
    'FrankRuhlLibre': 'FrankRuhlLibre-var.ttf',
    'StamBeitYosef': 'stam/beit-yosef.otf',
    'StamAri': 'stam/ari.otf',
    'StamSephardi': 'stam/StamVaalish-Regular.ttf',
    'StamChabad': 'stam/chabad-book-alphabet.otf',
  };
  final loadFonts = fonts.entries.map((font) {
    final loader = FontLoader(font.key)
      ..addFont(rootBundle.load(AppAssets.path('assets/fonts/${font.value}')));
    return loader.load();
  });
  await Future.wait([
    if (account)
      AccountStore.load().then<void>((store) {
        StorageService.browserAccountStore = store;
      }),
    ...loadFonts,
  ]);
  await startBrowserApp(
    prepareStorage: account ? () async {} : _preparePilot,
    browserLanguage:
        account ? AppLanguage.fromCode(_accountLanguage?.toDart) : null,
    signOut: account ? AccountStore.signOut : null,
    linkPhone: account ? AccountStore.linkPhone : null,
    managePassword: account ? AccountStore.managePassword : null,
  );
  if (account) _watchAccountLanguage();
}

void _watchAccountLanguage() {
  if (_rememberAccountLanguage == null) return;
  var lastLanguage = localeController.language;
  localeController.addListener(() {
    final language = localeController.language;
    if (lastLanguage == language) return;
    lastLanguage = language;
    _saveAccountLanguage(language.code.toJS);
  });
}

Future<void> _preparePilot() async {
  const key = 'full_pilot_initialized';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(key) == true) return;

  final storage = StorageService();
  if (prefs.getKeys().isEmpty) {
    await storage.saveProjects([
      Project(
        id: 'pilot-example',
        name: 'ספר תורה לדוגמה',
        type: ProjectType.sefer,
        price: 0,
        expenses: 0,
        targetDaily: 0,
        targetMonthly: 0,
        totalPages: 245,
        linesPerPage: 42,
      ),
    ]);
  }
  await prefs.setBool(key, true);
}
