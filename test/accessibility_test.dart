import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/accessibility/accessibility_controller.dart';
import 'package:sofer_vmone/home_screen.dart';
import 'package:sofer_vmone/main.dart' show accessibilityController;
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/settings/accessibility_screen.dart';
import 'package:sofer_vmone/settings_screen.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  tearDown(() async {
    StorageService.demoStore = MemoryStore({});
    await accessibilityController.load();
    StorageService.demoStore = null;
  });

  test('text size survives launch and never double-magnifies system text',
      () async {
    StorageService.demoStore =
        MemoryStore({'interface_text_scale_percent': 160});
    final controller = AccessibilityController();
    await controller.load();

    expect(controller.textSize, AppTextSize.extraLarge);
    expect(controller.scalerFor(TextScaler.linear(1.25)).scale(10), 16);

    await controller.setTextSize(AppTextSize.regular);
    expect(controller.scalerFor(TextScaler.linear(1.5)).scale(10), 15);
    expect(await StorageService().getInterfaceTextScalePercent(), 100);
  });

  test('an unknown future size falls back safely', () async {
    StorageService.demoStore =
        MemoryStore({'interface_text_scale_percent': 175});
    final controller = AccessibilityController();
    await controller.load();
    expect(controller.textSize, AppTextSize.regular);
  });

  testWidgets('maximum text keeps every accessibility choice reachable',
      (tester) async {
    StorageService.demoStore =
        MemoryStore({'interface_text_scale_percent': 200});
    await accessibilityController.load();
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.klaf),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
              textScaler: accessibilityController.scalerFor(media.textScaler)),
          child: child!,
        );
      },
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AccessibilityScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('תצוגה מקדימה'), 400);
    expect(find.text('תצוגה מקדימה'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maximum text keeps the full tablet home usable in every theme',
      (tester) async {
    final project = Project(
      id: 'p',
      name: 'ספר תורה לבדיקה',
      type: ProjectType.sefer,
      price: 40000,
      expenses: 0,
      targetDaily: 21,
      targetMonthly: 420,
      totalPages: 245,
      linesPerPage: 42,
    );
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final theme in AppTheme.values) {
      StorageService.demoStore = MemoryStore({
        'projects': jsonEncode([project.toJson()]),
        'history': '[]',
        'last_project': project.id,
      });
      await tester.pumpWidget(MaterialApp(
        theme: AppThemeBuilder.build(theme),
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: SoferHome(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: theme.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('maximum text keeps settings scrollable without clipping',
      (tester) async {
    StorageService.demoStore = MemoryStore({});
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemeBuilder.build(AppTheme.modern),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: SettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('בדוק ועדכן'), 500);
    expect(tester.takeException(), isNull);
  });
}
