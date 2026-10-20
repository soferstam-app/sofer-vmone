import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show rootBundle, SystemChrome, SystemUiMode;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'home_screen.dart';
import 'backup_service.dart';
import 'backup/migration_backup_gate.dart';
import 'logic/demo_data.dart';
import 'logic/onboarding.dart';
import 'logic/window_sizing.dart';
import 'l10n/app_localizations.dart';
import 'l10n/language_choice_screen.dart';
import 'l10n/locale_controller.dart';
import 'onboarding/onboarding_screen.dart';
import 'storage_service.dart';
import 'storage_recovery_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'notification_service.dart';
import 'accessibility/accessibility_controller.dart';
import 'version.dart';
import 'widgets/app_system_ui.dart';

final ValueNotifier<bool> windowsFloatingMode = ValueNotifier<bool>(false);
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Which look the app is wearing. Global for the same reason
/// [windowsFloatingMode] is: one app-wide switch with no owner below the root.
final ThemeController themeController = ThemeController();

/// The interface language, loaded before the first frame for the same reason
/// as the theme: neither direction nor words should flash in the wrong state.
final LocaleController localeController = LocaleController();

/// The reading size is app-wide, just like language and visual theme.
final AccessibilityController accessibilityController =
    AccessibilityController();

/// Puts the bundled fonts' licences where a user can actually read them.
///
/// Both fonts are under the SIL Open Font License, which requires the licence
/// to accompany the font wherever it is redistributed — and an app binary is a
/// redistribution. A file in the repository does not accompany anything; this
/// is what carries it into the build and in front of the reader, through
/// Flutter's own licence page.
void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final font in const ['Heebo', 'FrankRuhlLibre']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });
}

/// What the window should open at, measured against the display it opens on.
///
/// A failure to read the display is not a reason to refuse to start: it falls
/// back to the modest default, which is what the app did before it asked.
Future<Size> _startupWindowSize() async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    return WindowSizing.startup(
      remembered: await StorageService().getWindowSize(),
      available: display.visibleSize ?? display.size,
    );
  } catch (_) {
    return WindowSizing.preferred;
  }
}

/// Writes down the size the writer leaves the window at.
///
/// Debounced, because dragging an edge fires a resize on every frame and the
/// only size worth keeping is the one he stops at. The floating timer window
/// is not a size to remember, which [WindowSizing.worthRemembering] settles.
class _WindowSizeMemory extends WindowListener {
  Timer? _pending;

  @override
  void onWindowResized() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 600), () async {
      try {
        final size = await windowManager.getSize();
        if (!WindowSizing.worthRemembering(size)) return;
        await StorageService().setWindowSize(size);
      } catch (error) {
        debugPrint('Could not remember window size: $error');
      }
    });
  }
}

void main(List<String> _) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Every successful preference write feeds the one live migration snapshot.
  // The callback is deliberately installed here, before the first screen can
  // save anything, and failures remain non-fatal inside BackupService.
  StorageService.onChanged = BackupService.instance.writeAutoBackup;

  // Set only by the detached Windows updater. The new version acknowledges
  // itself after its first rendered frame; until then the updater retains a
  // complete copy of every package entry it replaced.
  final updateReadyPath =
      Platform.isWindows ? Platform.environment['SOFER_UPDATE_READY'] : null;
  final updateErrorPath =
      Platform.isWindows ? Platform.environment['SOFER_UPDATE_ERROR'] : null;

  // Before anything reads a setting. A demo build keeps every record in
  // memory, so it can be walked through without a fabricated commission ever
  // reaching the writer's own data.
  if (DemoData.enabled) await DemoData.install();

  registerFontLicences();
  await NotificationService().init();

  if (Platform.isAndroid) {
    // Keep the clock, battery and navigation controls visible. The root paints
    // their transparent insets, including on Android's mandatory edge-to-edge.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    FlutterForegroundTask.initCommunicationPort();
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        // The size he left it at, cut down to whatever screen he is on now.
        size: await _startupWindowSize(),
        // Below this the layouts stop being usable: the ruled themes drop to
        // one column at 620 and below about 400 the figures and the buttons
        // start colliding. There was no floor at all, so the window could be
        // dragged down to a sliver and the app simply broke.
        minimumSize: WindowSizing.minimum,
        center: true,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    windowManager.addListener(_WindowSizeMemory());
  }

  await _loadAndRunApp(updateReadyPath, updateErrorPath);
}

Future<void> _loadAndRunApp(
    String? updateReadyPath, String? updateErrorPath) async {
  try {
    await StorageService().ensureWorkRecovered();
    // Read before the first frame, so the app never flashes the wrong look.
    await themeController.load();
    await localeController.load();
    await accessibilityController.load();
  } on WorkRecoveryException catch (error) {
    debugPrint('Startup recovery required: $error');
    final code = await StorageService().recoveryLanguageCode();
    final english = code == 'en' ||
        (code != 'he' &&
            WidgetsBinding.instance.platformDispatcher.locale.languageCode !=
                'he');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(english ? 'en' : 'he'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: StorageRecoveryScreen(
        english: english,
        onRetry: () => _loadAndRunApp(updateReadyPath, updateErrorPath),
      ),
    ));
    // A recovery screen is not a successful upgrade acknowledgement.
    return;
  }

  runApp(const MyApp());

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (updateReadyPath != null && updateReadyPath.isNotEmpty) {
      try {
        await File(updateReadyPath).writeAsString(
          'ready',
          flush: true,
        );
      } catch (_) {
        // No acknowledgement means the updater restores the previous package.
      }
    }

    if (updateErrorPath != null && updateErrorPath.isNotEmpty) {
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.pick(
              he: 'העדכון לא הושלם',
              en: 'Update was not completed',
            )),
            content: Text(
              context.l10n.pick(
                he: 'הגרסה החדשה לא הצליחה להיפתח כראוי, ולכן התוכנה החזירה אוטומטית את הגרסה הקודמת. הנתונים האישיים לא שונו.',
                en: 'The new version did not open correctly, so the app automatically restored the previous version. Your personal data was not changed.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.confirm),
              ),
            ],
          ),
        );
      }
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    didChangePlatformBrightness();
  }

  @override
  void didChangePlatformBrightness() => themeController.setSystemBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          [themeController, localeController, accessibilityController]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          onGenerateTitle: (context) => context.l10n.appName,
          theme: themeController.themeData,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: localeController.language.locale,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: accessibilityController.scalerFor(media.textScaler),
              ),
              child: AppSystemUi(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const _Opening(),
        );
      },
    );
  }
}

/// Decides whether the app opens with the explanation or with the home screen.
///
/// A frame of nothing rather than a spinner: the answer comes from local
/// settings and arrives in the same breath, and a spinner that flashes for one
/// frame reads as a fault.
class _Opening extends StatefulWidget {
  const _Opening();

  @override
  State<_Opening> createState() => _OpeningState();
}

class _OpeningState extends State<_Opening> {
  final _storage = StorageService();
  bool? _showOnboarding;
  bool _showLanguageChoice = false;
  bool _openProjects = false;

  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final seen = await _storage.getOnboardingSeen();
    final projects = await _storage.loadProjects();
    final history = await _storage.loadHistory();
    final askLanguage = shouldAskForLanguage(
      hasExplicitChoice: localeController.hasExplicitChoice,
      onboardingSeen: seen,
      hasProjects: projects.isNotEmpty,
      hasHistory: history.isNotEmpty,
    );
    if (!localeController.hasExplicitChoice && !askLanguage) {
      // Existing installations predate this setting. Persist Hebrew once so a
      // later platform-language change can never alter their interface.
      await localeController.setLanguage(AppLanguage.hebrew);
    }
    // Version bookkeeping is independent of the external-backup check.
    await _storage.setLastRunAppVersion(appVersion);
    if (!mounted) return;
    setState(() {
      _showLanguageChoice = askLanguage;
      _showOnboarding = shouldShowOnboarding(
        seen: seen,
        hasProjects: projects.isNotEmpty,
        hasHistory: history.isNotEmpty,
      );
    });
  }

  Future<void> _chooseLanguage(AppLanguage language) async {
    await localeController.setLanguage(language);
    if (!mounted) return;
    setState(() => _showLanguageChoice = false);
  }

  Future<void> _finish({required bool createProject}) async {
    await _storage.setOnboardingSeen(true);
    if (!mounted) return;
    setState(() {
      _openProjects = createProject;
      _showOnboarding = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      return Scaffold(backgroundColor: SoferTokens.of(context).paper);
    }
    if (_showLanguageChoice) {
      return LanguageChoiceScreen(onSelected: _chooseLanguage);
    }
    if (_showOnboarding!) {
      return OnboardingScreen(onDone: ({required createProject}) {
        _finish(createProject: createProject);
      });
    }
    return MigrationBackupGate(
      child: SoferHome(
        windowsFloatingMode: Platform.isWindows ? windowsFloatingMode : null,
        openProjectsOnStart: _openProjects,
      ),
    );
  }
}
