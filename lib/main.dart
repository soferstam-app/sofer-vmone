import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:window_manager/window_manager.dart';
import 'home_screen.dart';
import 'notification_service.dart';
import 'theme/theme_controller.dart';

final ValueNotifier<bool> windowsFloatingMode = ValueNotifier<bool>(false);

/// Which look the app is wearing. Global for the same reason
/// [windowsFloatingMode] is: one app-wide switch with no owner below the root.
final ThemeController themeController = ThemeController();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();

  if (Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1280, 720),
        center: true,
        titleBarStyle: TitleBarStyle.normal,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
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
