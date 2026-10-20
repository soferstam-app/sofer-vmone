import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/l10n/app_localizations.dart';
import 'package:sofer_vmone/l10n/locale_controller.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  tearDown(() => StorageService.demoStore = null);

  test('an old installation without a language remains Hebrew', () async {
    StorageService.demoStore = MemoryStore({});
    final controller = LocaleController();

    await controller.load();

    expect(controller.language, AppLanguage.hebrew);
    expect(controller.hasExplicitChoice, isFalse);
  });

  test('an explicit English choice survives another launch', () async {
    StorageService.demoStore = MemoryStore({});
    final first = LocaleController();
    await first.load();
    await first.setLanguage(AppLanguage.english);

    final reopened = LocaleController();
    await reopened.load();

    expect(reopened.language, AppLanguage.english);
    expect(reopened.hasExplicitChoice, isTrue);
  });

  test('only a genuinely fresh installation asks before onboarding', () {
    expect(
      shouldAskForLanguage(
        hasExplicitChoice: false,
        onboardingSeen: false,
        hasProjects: false,
        hasHistory: false,
      ),
      isTrue,
    );
    expect(
      shouldAskForLanguage(
        hasExplicitChoice: false,
        onboardingSeen: true,
        hasProjects: false,
        hasHistory: false,
      ),
      isFalse,
    );
    expect(
      shouldAskForLanguage(
        hasExplicitChoice: false,
        onboardingSeen: false,
        hasProjects: true,
        hasHistory: false,
      ),
      isFalse,
    );
    expect(
      shouldAskForLanguage(
        hasExplicitChoice: true,
        onboardingSeen: false,
        hasProjects: false,
        hasHistory: false,
      ),
      isFalse,
    );
  });
}
