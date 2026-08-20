// Night dress means the night version of the look the writer chose.
//
// The automatic switch sent everyone to layla, the parchment family after dark.
// For a writer on klaf that is right. For one on modern it handed him a
// different app rather than a darker one — and modern has a dark mode of its
// own, which the switch was walking straight past.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  group('the three looks are three looks', () {
    test('modern has a dark of its own, and it is not layla', () {
      final modernDark =
          AppThemeBuilder.build(AppTheme.modern, system: Brightness.dark);
      final layla = AppThemeBuilder.build(AppTheme.layla);

      final a = modernDark.extension<SoferTokens>()!;
      final b = layla.extension<SoferTokens>()!;

      expect(a.paper, isNot(b.paper));
      expect(a.layout, AppLayout.cards, reason: 'modern stays cards');
      expect(b.layout, AppLayout.rules, reason: 'layla stays ruled');
    });

    test('modern dark really is dark', () {
      final tokens = AppThemeBuilder.build(AppTheme.modern,
              system: Brightness.dark)
          .extension<SoferTokens>()!;
      final light = AppThemeBuilder.build(AppTheme.modern,
              system: Brightness.light)
          .extension<SoferTokens>()!;

      expect(tokens.paper.computeLuminance(),
          lessThan(light.paper.computeLuminance()));
    });

    test('and a writer on modern keeps his layout after dark', () {
      // The failure this replaces: choosing modern and switching on the
      // automatic night meant reading a ruled parchment app at nightfall.
      for (final brightness in Brightness.values) {
        expect(
          AppThemeBuilder.build(AppTheme.modern, system: brightness)
              .extension<SoferTokens>()!
              .layout,
          AppLayout.cards,
        );
      }
    });
  });

  group('klaf after dark', () {
    test('is layla, which is the same family in the dark', () {
      final klaf = AppThemeBuilder.build(AppTheme.klaf)
          .extension<SoferTokens>()!;
      final layla = AppThemeBuilder.build(AppTheme.layla)
          .extension<SoferTokens>()!;

      expect(klaf.layout, layla.layout, reason: 'the same arrangement');
      expect(layla.paper.computeLuminance(),
          lessThan(klaf.paper.computeLuminance()),
          reason: 'darker, not different');
    });
  });
}
