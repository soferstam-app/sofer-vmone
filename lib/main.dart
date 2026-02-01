import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'home_screen.dart';
import 'netfree_cert.dart';
import 'notification_service.dart';

final ValueNotifier<bool> windowsFloatingMode = ValueNotifier<bool>(false);

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final SecurityContext securityContext =
        context ?? SecurityContext(withTrustedRoots: true);

    try {
      if (netfreeCertContent.contains("BEGIN CERTIFICATE")) {
        securityContext
            .setTrustedCertificatesBytes(utf8.encode(netfreeCertContent));
      } else {
        debugPrint("שגיאה: תוכן תעודת נטפרי ריק או לא תקין");
      }
    } catch (e) {
      debugPrint("שגיאה בטעינת תעודת נטפרי: $e");
    }

    final HttpClient client = super.createHttpClient(securityContext);

    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) {
      final bool isGoogle = host.contains("google.com") ||
          host.contains("googleapis.com") ||
          host.contains("gstatic.com");
      final bool isNetfree = host.contains("netfree.link");
      final bool isNetfreeIssuer = cert.issuer.toString().contains("NetFree");

      if (isGoogle || isNetfree || isNetfreeIssuer) {
        return true;
      }

      return false;
    };

    return client;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyHttpOverrides();
  await NotificationService().init();

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

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'סופר ומונה',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
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
          windowsFloatingMode: Platform.isWindows ? windowsFloatingMode : null),
    );
  }
}
