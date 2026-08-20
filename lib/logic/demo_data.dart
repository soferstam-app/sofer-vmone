import 'dart:convert';

import '../models.dart';
import '../storage_service.dart';
import 'currency.dart';
import 'tefillin_position.dart';
import 'tefillin_units.dart';

/// A commission of each kind, for looking at the app rather than using it.
///
/// Built for review: somebody judging a change to how tefillin works needs a
/// tefillin order part way through, beside a sefer and a run of mezuzot to
/// compare it against, and nobody should have to type that in.
///
/// **It never touches the real store.** [install] hands [StorageService] a
/// [MemoryStore], and while that is set nothing in the app opens the
/// preferences file at all — so no fabricated commission can land among real
/// ones. Everything is gone when the window closes.
///
/// shared_preferences' own `setMockInitialValues` was tried first and does not
/// hold in a release build on Windows: the app went on reading and writing the
/// real file, which was found by hashing it before and after a run. Isolation
/// has to be something the app itself enforces.
class DemoData {
  const DemoData._();

  /// Whether this build was compiled to open with demo data.
  ///
  /// The documented Windows build command has always used `DEMO=1`, while
  /// Dart's bool.fromEnvironment accepts only the literal `true`. Accept both
  /// spellings explicitly; otherwise a build labelled "demo" silently opens
  /// the real store, which defeats the isolation this class exists to provide.
  static const String _environmentValue =
      String.fromEnvironment('DEMO', defaultValue: '');
  static const bool enabled =
      _environmentValue == '1' || _environmentValue == 'true';

  static DateTime _daysAgo(int n) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 9)
        .subtract(Duration(days: n));
  }

  /// Loads the demo into memory in place of whatever is on disk.
  ///
  /// Must run before anything reads a preference.
  static Future<void> install() async {
    final projects = _projects();
    final history = _history();

    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([for (final p in projects) p.toJson()]),
      'history': jsonEncode([for (final s in history) s.toJson()]),
      'onboarding_seen': true,
      'smart_workflow_enabled': true,
      'app_theme': 'klaf',
      'sofer_name': 'דמו',
      'last_project': projects.first.id,
      // Where the writer stands in the tefillin order: pair 4, the hand's
      // והיה כי יביאך, three ruled lines in.
      'last_positions': jsonEncode({
        projects.first.id: {
          'page': const TefillinPosition(
                  pair: 4, side: TefillinSide.hand, parshiya: 2)
              .slotIndex,
          'line': 4,
        },
        'demo-sefer': {'page': 74, 'line': 1},
        // Two mezuzot are intentionally left part-written so the skip-and-
        // return flow can be reviewed without first manufacturing the state.
        'demo-mezuza': {'page': 20, 'line': 7},
      }),
    });
  }

  static List<Project> _projects() => [
        Project(
          id: 'demo-tefillin',
          name: 'תפילין — הזמנת ר׳ מנחם',
          type: ProjectType.tefillin,
          price: 1200,
          expenses: 260,
          currency: Currency.ils,
          targetDaily: 3,
          targetMonthly: 60,
          targetUnits: 10,
          // Pair five is held up on a correction and pair six lost a parshiya
          // altogether — the two things no session can record.
          tefillinFlags: const {
            '5:head:2': 'stuck',
            '6:head:2': 'void',
          },
        ),
        Project(
          id: 'demo-sefer',
          name: 'ספר תורה — בית כנסת אור החיים',
          type: ProjectType.sefer,
          price: 500,
          expenses: 40,
          currency: Currency.ils,
          targetDaily: 1,
          targetMonthly: 22,
          totalPages: 245,
          linesPerPage: 42,
        ),
        Project(
          id: 'demo-mezuza',
          name: 'מזוזות — הזמנה של 30',
          type: ProjectType.mezuza,
          price: 180,
          expenses: 25,
          currency: Currency.ils,
          targetDaily: 2,
          targetMonthly: 40,
          targetUnits: 30,
        ),
      ];

  static List<WorkSession> _history() {
    final out = <WorkSession>[];
    var n = 0;

    void tefillin({
      required int pair,
      required TefillinSide side,
      required int parshiya,
      required int daysAgo,
      int endLine = 0,
      int minutes = 55,
    }) {
      final start = _daysAgo(daysAgo);
      final part = side == TefillinSide.head ? 'ראש' : 'יד';
      final name = TefillinUnits.names[parshiya - 1];
      out.add(WorkSession(
        id: 'demo-t-${n++}',
        projectId: 'demo-tefillin',
        startTime: start,
        endTime: start.add(Duration(minutes: minutes)),
        amount: 1,
        startLine: 0,
        endLine: endLine,
        tefillinType: side == TefillinSide.head ? 'head' : 'hand',
        parshiya: parshiya,
        pairIndex: pair,
        description: 'פרשיית $name של $part (זוג $pair)',
        isManual: false,
        workingDateAtEntry: DateTime(start.year, start.month, start.day),
      ));
    }

    // Three pairs finished outright, oldest first.
    for (var pair = 1; pair <= 3; pair++) {
      for (final side in TefillinSide.values) {
        for (var p = 1; p <= 4; p++) {
          tefillin(
            pair: pair,
            side: side,
            parshiya: p,
            daysAgo: 58 - (pair * 8) - (side.index * 4) - p,
            // Longer parshiyot took longer, so the rate per sefer line comes
            // out sane rather than saying שמע takes as long as קדש.
            minutes: 12 + TefillinUnits.seferLines[p - 1] * 3,
          );
        }
      }
    }

    // The fourth: its head is finished, its hand is part way through.
    for (var p = 1; p <= 4; p++) {
      tefillin(
          pair: 4,
          side: TefillinSide.head,
          parshiya: p,
          daysAgo: 22 - p,
          minutes: 12 + TefillinUnits.seferLines[p - 1] * 3);
    }
    tefillin(pair: 4, side: TefillinSide.hand, parshiya: 1, daysAgo: 12);
    tefillin(
        pair: 4,
        side: TefillinSide.hand,
        parshiya: 2,
        daysAgo: 2,
        endLine: 3,
        minutes: 26);

    // Pairs five and six were begun and stopped on — see the flags above.
    tefillin(pair: 5, side: TefillinSide.head, parshiya: 1, daysAgo: 16);
    tefillin(pair: 6, side: TefillinSide.head, parshiya: 1, daysAgo: 11);

    // Somebody writing the opening of every set first, to carry on by however
    // many pass inspection.
    for (var pair = 7; pair <= 10; pair++) {
      tefillin(
          pair: pair,
          side: TefillinSide.head,
          parshiya: 1,
          daysAgo: 10 - (pair - 7));
    }

    // A sefer, a page or so a day for the last fortnight.
    for (var i = 0; i < 26; i++) {
      final start = _daysAgo(40 - i);
      final page = 61 + (i ~/ 2);
      final from = i.isEven ? 1 : 22;
      final to = i.isEven ? 21 : 42;
      out.add(WorkSession(
        id: 'demo-s-$i',
        projectId: 'demo-sefer',
        startTime: start,
        endTime: start.add(const Duration(minutes: 104)),
        amount: page,
        startLine: from,
        endLine: to,
        description: 'כתיבה רציפה',
        isManual: false,
        linesPerPageAtEntry: 42,
        workingDateAtEntry: DateTime(start.year, start.month, start.day),
      ));
    }

    // Mezuzot, two or three at a sitting.
    for (var i = 0; i < 7; i++) {
      final start = _daysAgo(30 - i * 4);
      out.add(WorkSession(
        id: 'demo-m-$i',
        projectId: 'demo-mezuza',
        startTime: start,
        endTime: start.add(const Duration(minutes: 145)),
        amount: i.isEven ? 3 : 2,
        startLine: 0,
        endLine: 0,
        description: '${i.isEven ? 3 : 2} מזוזות',
        isManual: false,
        workingDateAtEntry: DateTime(start.year, start.month, start.day),
      ));
    }

    for (final partial in const [
      (index: 19, lines: 10),
      (index: 20, lines: 6)
    ]) {
      final start = _daysAgo(1);
      out.add(WorkSession(
        id: 'demo-m-part-${partial.index}',
        projectId: 'demo-mezuza',
        startTime: start,
        endTime: start.add(Duration(minutes: partial.lines * 5)),
        amount: 1,
        startLine: 0,
        endLine: partial.lines,
        mezuzaIndex: partial.index,
        description: 'מזוזה ${partial.index} (${partial.lines} שורות)',
        isManual: false,
        workingDateAtEntry: DateTime(start.year, start.month, start.day),
      ));
    }

    return out;
  }
}
