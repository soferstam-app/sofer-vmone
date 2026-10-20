import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Paints the system-bar insets and sets their icon contrast before applying
/// SafeArea. Route app bars sit below these insets and cannot style them.
class AppSystemUi extends StatelessWidget {
  final Widget child;

  const AppSystemUi({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final dark =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final icons = dark ? Brightness.light : Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // Older Android uses these colors; newer Android ignores them and
        // shows the matching ColoredBox through transparent system bars.
        statusBarColor: background,
        statusBarIconBrightness: icons,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness: icons,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ColoredBox(
        color: background,
        child: SafeArea(child: child),
      ),
    );
  }
}
