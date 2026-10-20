import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/theme/app_theme.dart';
import 'package:sofer_vmone/widgets/app_system_ui.dart';

void main() {
  const pageKey = ValueKey('page');
  const padding = FakeViewPadding(top: 24, bottom: 34);

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    addTearDown(tester.view.reset);
  }

  Future<void> host(WidgetTester tester, ThemeData theme,
      {GlobalKey<NavigatorState>? navigatorKey}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: theme,
      builder: (_, child) => AppSystemUi(child: child!),
      home: Scaffold(
        key: pageKey,
        // Intentionally opposite to the root's light themes. With SafeArea
        // alone this annotation never reaches the status bar's sample point.
        appBar: AppBar(
          backgroundColor: Colors.black,
          systemOverlayStyle: SystemUiOverlayStyle.light,
          title: const Text('Writing'),
        ),
        body: const Center(child: Text('Page content')),
      ),
    ));
    await tester.pumpAndSettle();
  }

  void expectBars(WidgetTester tester, ThemeData theme) {
    final style = SystemChrome.latestStyle!;
    final dark =
        ThemeData.estimateBrightnessForColor(theme.scaffoldBackgroundColor) ==
            Brightness.dark;
    expect(style.statusBarIconBrightness,
        dark ? Brightness.light : Brightness.dark);
    expect(style.systemNavigationBarIconBrightness,
        dark ? Brightness.light : Brightness.dark);
    expect(style.statusBarColor, theme.scaffoldBackgroundColor);
    expect(style.systemNavigationBarColor, theme.scaffoldBackgroundColor);
    expect(style.systemStatusBarContrastEnforced, isFalse);
    final background = find
        .descendant(
            of: find.byType(AppSystemUi), matching: find.byType(ColoredBox))
        .first;
    expect(tester.widget<ColoredBox>(background).color,
        theme.scaffoldBackgroundColor);
    expect(tester.getRect(background), const Rect.fromLTWH(0, 0, 390, 844));
  }

  for (final choice in [
    (AppTheme.modern, Brightness.light),
    (AppTheme.modern, Brightness.dark),
    (AppTheme.klaf, Brightness.dark),
    (AppTheme.layla, Brightness.light),
  ]) {
    testWidgets('system icons remain readable for ${choice.$1}/${choice.$2}',
        (tester) async {
      phone(tester);
      final theme = AppThemeBuilder.build(choice.$1, system: choice.$2);
      await host(tester, theme);
      expectBars(tester, theme);
      // Insets belong to the root; route content is neither covered nor
      // padded a second time by its app bar.
      expect(tester.getRect(find.byKey(pageKey)),
          const Rect.fromLTWH(0, 24, 390, 786));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching themes updates the actual platform overlay style',
      (tester) async {
    phone(tester);
    for (final choice in [AppTheme.klaf, AppTheme.layla, AppTheme.modern]) {
      final theme = AppThemeBuilder.build(choice);
      await host(tester, theme);
      expectBars(tester, theme);
    }
  });

  testWidgets('routes, dialogs and keyboard keep the system bar style',
      (tester) async {
    phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final theme = AppThemeBuilder.build(AppTheme.klaf);
    await host(tester, theme, navigatorKey: navigator);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: TextField()))));
    await tester.pumpAndSettle();
    expectBars(tester, theme);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    tester.view.padding = const FakeViewPadding(top: 24);
    await tester.pumpAndSettle();
    expectBars(tester, theme);
    showDialog<void>(
        context: tester.element(find.byType(TextField)),
        builder: (_) => const AlertDialog(content: Text('Save your work')));
    await tester.pumpAndSettle();
    expectBars(tester, theme);
    navigator.currentState!.pop();
    navigator.currentState!.pop();
    tester.view.viewInsets = const FakeViewPadding();
    tester.view.padding = padding;
    await tester.pumpAndSettle();
    expectBars(tester, theme);
    expect(tester.getRect(find.byKey(pageKey)),
        const Rect.fromLTWH(0, 24, 390, 786));
    expect(tester.takeException(), isNull);
  });
}
