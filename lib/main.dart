import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'home_screen.dart';
import 'logic/window_sizing.dart';
import 'storage_service.dart';
import 'theme/theme_controller.dart';
import 'notification_service.dart';

final ValueNotifier<bool> windowsFloatingMode = ValueNotifier<bool>(false);

/// Which look the app is wearing. Global for the same reason
/// [windowsFloatingMode] is: one app-wide switch with no owner below the root.
final ThemeController themeController = ThemeController();

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
      final size = await windowManager.getSize();
      if (!WindowSizing.worthRemembering(size)) return;
      await StorageService().setWindowSize(size);
    });
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();
  await NotificationService().init();

  if (Platform.isAndroid) {
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

  // Read before the first frame, so the app never flashes the wrong look.
  await themeController.load();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        themeController
            .setSystemBrightness(MediaQuery.platformBrightnessOf(context));

        return MaterialApp(
          title: 'סופר ומונה',
          theme: themeController.themeData,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('he', 'IL'),
          ],
          locale: const Locale('he', 'IL'),
          home: SoferHome(
              windowsFloatingMode:
                  Platform.isWindows ? windowsFloatingMode : null),
        );
      },
    );
  }
}
