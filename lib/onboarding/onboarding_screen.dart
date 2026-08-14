import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/onboarding.dart';
import '../main.dart' show themeController;
import '../theme/app_theme.dart';

/// The five screens a sofer sees the first time he opens the app.
///
/// Shown once, before the home screen, and only to someone with nothing in the
/// app yet — see [shouldShowOnboarding]. Reachable again from the settings
/// screen, because otherwise the only way back to it is to reinstall.
///
/// Everything here is scrolled rather than fitted. The readers are older than
/// the average and many of them raise the system font; a page laid out to an
/// exact height loses its button off the bottom edge, which is the one thing
/// that must never happen on the screen that teaches the app.
class OnboardingScreen extends StatefulWidget {
  /// Called when the writer is done — by finishing, or by skipping.
  ///
  /// [createProject] says whether he pressed the last button rather than
  /// leaving: the screen ends by opening the thing it spent five pages
  /// explaining, instead of dropping him on an empty home screen.
  final void Function({required bool createProject}) onDone;

  /// True when opened from settings to be read again, rather than shown on a
  /// first launch. The only difference is the last button: there is no first
  /// project to open when the writer already has some.
  final bool fromSettings;

  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.fromSettings = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _maxColumn = 430.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _index == onboardingPages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onDone(createProject: true);
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _back() => _controller.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): _SkipIntent(),
          },
          child: Actions(
            actions: {
              _SkipIntent: CallbackAction<_SkipIntent>(
                onInvoke: (_) {
                  widget.onDone(createProject: false);
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxColumn),
                  child: Column(
                    children: [
                      _TopRow(
                        index: _index,
                        onSkip: () => widget.onDone(createProject: false),
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _controller,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemCount: onboardingPages.length,
                          itemBuilder: (_, i) => SingleChildScrollView(
                            padding:
                                const EdgeInsets.fromLTRB(22, 4, 22, 12),
                            child: _Page(page: onboardingPages[i]),
                          ),
                        ),
                      ),
                      _BottomBar(
                        index: _index,
                        isLast: _isLast,
                        fromSettings: widget.fromSettings,
                        onNext: _next,
                        onBack: _index == 0 ? null : _back,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipIntent extends Intent {
  const _SkipIntent();
}

class _TopRow extends StatelessWidget {
  final int index;
  final VoidCallback onSkip;

  const _TopRow({required this.index, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Counted from one. A person reading "0 מתוך 5" on the first page
          // has found a bug, whatever the array says.
          Text(
            '${index + 1} מתוך ${onboardingPages.length}',
            style: TextStyle(fontSize: 12, color: t.inkFaint),
          ),
          TextButton(
            onPressed: onSkip,
            child: const Text('דלג'),
          ),
        ],
      ),
    );
  }
}

class _Page extends StatelessWidget {
  final OnboardingPage page;

  const _Page({required this.page});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final isTitlePage = page.kind == OnboardingKind.prose;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          page.title,
          style: TextStyle(
            fontSize: isTitlePage ? 26 : 19,
            fontWeight: FontWeight.w600,
            fontFamily: t.numeralFamily,
            color: t.ink,
          ),
        ),
        const SizedBox(height: 14),
        for (final paragraph in page.paragraphs) ...[
          Text(paragraph, style: _body(t)),
          const SizedBox(height: 10),
        ],
        switch (page.kind) {
          OnboardingKind.steps => _Steps(items: page.items),
          OnboardingKind.facts => _Facts(items: page.items),
          OnboardingKind.list => _Items(items: page.items),
          OnboardingKind.appearance => const _AppearancePicker(),
          OnboardingKind.prose => const SizedBox.shrink(),
        },
        if (page.footnote != null) ...[
          const SizedBox(height: 14),
          Text(
            page.footnote!,
            style: _body(t).copyWith(
              color: isTitlePage ? t.ink : t.inkMuted,
              fontWeight: isTitlePage ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  static TextStyle _body(SoferTokens t) =>
      TextStyle(fontSize: 14.5, height: 1.75, color: t.inkMuted);
}

class _Steps extends StatelessWidget {
  final List<OnboardingItem> items;

  const _Steps({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink)),
                const SizedBox(height: 3),
                Text(item.text,
                    style: TextStyle(
                        fontSize: 13.5, height: 1.7, color: t.inkMuted)),
              ],
            ),
          ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  final List<OnboardingItem> items;

  const _Facts({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(fontSize: 14, color: t.inkFaint)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.text,
                      style: TextStyle(
                          fontSize: 14, height: 1.6, color: t.ink)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Items extends StatelessWidget {
  final List<OnboardingItem> items;

  const _Items({required this.items});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: item.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: t.ink)),
                TextSpan(text: ' — ', style: TextStyle(color: t.inkFaint)),
                TextSpan(text: item.text, style: TextStyle(color: t.inkMuted)),
              ]),
              style: const TextStyle(fontSize: 13.5, height: 1.65),
            ),
          ),
      ],
    );
  }
}

/// The one page that asks rather than tells.
///
/// Ending on a choice rather than a paragraph means the writer has already
/// done something in the app before he reaches the home screen, and it puts
/// the one setting that changes everything in front of him while he is still
/// looking, instead of buried where he will find it in a month.
class _AppearancePicker extends StatelessWidget {
  const _AppearancePicker();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        final chosen = themeController.choice;
        return Row(
          children: [
            for (final theme in AppTheme.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _Swatch(
                    theme: theme,
                    selected: theme == chosen,
                    onTap: () => themeController.setChoice(theme),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Swatch extends StatelessWidget {
  final AppTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch(
      {required this.theme, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Built from the theme itself, so a swatch cannot drift from what tapping
    // it produces.
    final preview = AppThemeBuilder.build(theme).extension<SoferTokens>()!;
    final here = SoferTokens.of(context);

    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
          decoration: BoxDecoration(
            color: preview.paper,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? here.accent : preview.rule,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            theme.label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: preview.ink),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final bool isLast;
  final bool fromSettings;
  final VoidCallback onNext;
  final VoidCallback? onBack;

  const _BottomBar({
    required this.index,
    required this.isLast,
    required this.fromSettings,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 18),
      child: Column(
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                OutlinedButton(onPressed: onBack, child: const Text('הקודם')),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: onNext,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text(
                      isLast
                          ? (fromSettings ? 'סיום' : 'פתיחת פרויקט ראשון')
                          : 'הבא',
                      style: const TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < onboardingPages.length; i++)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == index ? t.accent : t.rule,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
