// A dialog must depend on its own context, not on the screen underneath.
//
// Seven dialog builders took `ctx` and then read `SoferTokens.of(context)` —
// the *screen's* context. A dialog lives in the navigator's overlay, which is a
// separate subtree, so that registers the dialog as a dependent of something
// outside itself. Where the two happen to resolve to the same inherited element
// it is merely wrong on paper; where a screen wraps itself in anything local it
// is a dependency that outlives what it points at.
//
// This does not claim to reproduce the red screen the writer photographed
// (`'_dependents.isEmpty': is not true`). It pins the teardown orders that were
// worth suspecting: a dialog still open when the theme changes under it, and a
// dialog still open when the screen it was opened from goes away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  final navigator = GlobalKey<NavigatorState>();

  Widget harness(ValueNotifier<AppTheme> theme) => ValueListenableBuilder(
        valueListenable: theme,
        builder: (_, choice, __) => MaterialApp(
          theme: AppThemeBuilder.build(choice),
          navigatorKey: navigator,
          home: Builder(
            builder: (home) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(home).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Builder(
                        builder: (screen) => Scaffold(
                          body: Center(
                            child: ElevatedButton(
                              onPressed: () => showDialog<void>(
                                context: screen,
                                builder: (ctx) => AlertDialog(
                                  content: Text('שלום',
                                      style: TextStyle(
                                          color: SoferTokens.of(ctx).ink)),
                                ),
                              ),
                              child: const Text('dialog'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('push'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> openDialogOnPushedScreen(WidgetTester tester) async {
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    expect(find.text('שלום'), findsOneWidget);
  }

  testWidgets('the theme may change with a dialog open', (tester) async {
    final theme = ValueNotifier(AppTheme.klaf);
    addTearDown(theme.dispose);

    await tester.pumpWidget(harness(theme));
    await openDialogOnPushedScreen(tester);

    // Nightfall arriving, or the writer reaching for the setting.
    theme.value = AppTheme.layla;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('and the screen underneath may be taken away', (tester) async {
    final theme = ValueNotifier(AppTheme.klaf);
    addTearDown(theme.dispose);

    await tester.pumpWidget(harness(theme));
    await openDialogOnPushedScreen(tester);

    // The route the dialog was opened from is removed while the dialog is
    // still up. Anything the dialog registered against that screen is now
    // pointing at a subtree being torn down.
    navigator.currentState!.removeRouteBelow(ModalRoute.of(
        tester.element(find.text('שלום')))!);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
