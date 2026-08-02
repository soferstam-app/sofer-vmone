// The fonts are redistributed, so their licence has to be too.
//
// Frank Ruhl Libre and Heebo are both under the SIL Open Font License, which
// requires the licence to accompany the font software wherever it goes — and an
// app binary is a redistribution. They shipped for a while with neither the
// licence nor an attribution anywhere.
//
// The ways this silently breaks: the asset declaration is dropped from pubspec
// (the file stays in the repository and vanishes from the build), the text is
// truncated, or the registration is removed and the licence ships but is
// unreachable. Each of those looks like nothing at all.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Whatever `registerFontLicences` puts into the registry.
  Future<List<LicenseEntry>> registered() async {
    registerFontLicences();
    return LicenseRegistry.licenses.toList();
  }

  test('both fonts reach the licence registry', () async {
    final entries = await registered();
    final packages = entries.expand((e) => e.packages).toSet();

    expect(packages, containsAll(['Heebo', 'FrankRuhlLibre']),
        reason: 'a licence nobody can reach has accompanied nothing');
  });

  test('each carries the whole licence, not a summary of one', () async {
    final entries = await registered();

    for (final font in ['Heebo', 'FrankRuhlLibre']) {
      final entry = entries.firstWhere((e) => e.packages.contains(font));
      final text = entry.paragraphs.map((p) => p.text).join('\n');

      // An approximation of a licence is worse than none: it is a different
      // licence, granted by nobody.
      for (final required in const [
        'SIL OPEN FONT LICENSE Version 1.1',
        'PREAMBLE',
        'DEFINITIONS',
        'PERMISSION & CONDITIONS',
        'TERMINATION',
        'DISCLAIMER',
      ]) {
        expect(text, contains(required), reason: '$font is missing $required');
      }
      expect(text, contains('WITHOUT WARRANTY OF ANY KIND'));
    }
  });

  test('each names its own copyright holder', () async {
    // The licence body is the same for every OFL font; the notice is not, and
    // copying one font's notice onto another attributes it to the wrong people.
    final entries = await registered();

    String textOf(String font) => entries
        .firstWhere((e) => e.packages.contains(font))
        .paragraphs
        .map((p) => p.text)
        .join('\n');

    expect(textOf('Heebo'), contains('The Heebo Project Authors'));
    expect(textOf('FrankRuhlLibre'),
        contains('The Frank Ruhl Libre Project Authors'));
    expect(textOf('Heebo'), isNot(contains('Frank Ruhl')));
  });
}
