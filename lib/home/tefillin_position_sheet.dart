import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/tefillin_position.dart';
import '../logic/tefillin_units.dart';
import '../theme/app_theme.dart';

/// Moving about a tefillin commission without leaving the timer.
///
/// The sefer equivalent is a dialog with two number fields, which works because
/// a sefer has two numbers. Here the answer is nearly always one of five or six
/// slots, so they are simply listed and tapped. Nothing is typed and no screen
/// is opened.
class TefillinPositionSheet extends StatelessWidget {
  final TefillinPosition current;

  /// Real ruled lines written of [current], for the line the sheet shows
  /// against it.
  final int currentLine;

  /// When the writer began the parshiya he is on.
  final DateTime? currentStartedOn;

  final TefillinPicks picks;
  final ValueChanged<TefillinSlot> onPick;

  /// Whether dates read as Gregorian, which is the writer's own setting.
  final bool useGregorianDates;

  /// Opens the full board — for the rare case the list does not cover.
  final VoidCallback? onOpenBoard;

  const TefillinPositionSheet({
    super.key,
    required this.current,
    required this.currentLine,
    required this.picks,
    required this.onPick,
    this.currentStartedOn,
    this.useGregorianDates = false,
    this.onOpenBoard,
  });

  /// "התחיל ג׳ אלול" — which job this is, said in the only terms that identify
  /// it. Empty for a slot never begun.
  String _started(DateTime? day) =>
      day == null ? '' : 'התחיל ${formatDisplayDate(day, useGregorianDates)}';

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: t.paper,
          border: Border(top: BorderSide(color: t.ruleStrong, width: 2)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        // A commission with several parshiyot stopped part way makes a longer
        // list than a short window can hold, and a list that runs off the
        // bottom edge hides exactly the entries the writer went looking for.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('מה אני כותב עכשיו',
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 12,
                      letterSpacing: 1.4,
                      color: t.inkMuted)),
              const SizedBox(height: 10),
              _currentRow(t),
              const SizedBox(height: 14),
              if (picks.stopped.isNotEmpty) ...[
                _section(t, 'עצרתי באמצע'),
                for (final s in picks.stopped) _row(t, s),
                const SizedBox(height: 12),
              ],
              if (picks.stuck.isNotEmpty) ...[
                _section(t, 'ממתין לתיקון'),
                for (final s in picks.stuck) _row(t, s),
                const SizedBox(height: 12),
              ],
              if (picks.nextUp.isNotEmpty) ...[
                _section(t, 'הבא בתור'),
                for (final s in picks.nextUp) _row(t, s),
              ],
              const SizedBox(height: 14),
              Container(height: 1, color: t.rule),
              const SizedBox(height: 12),
              Row(
                children: [
                  InkWell(
                    onTap: onOpenBoard,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('כל ההזמנה  ›',
                          style: TextStyle(
                              fontFamily: t.labelFamily,
                              fontSize: 13,
                              color: t.accent)),
                    ),
                  ),
                  const Spacer(),
                  Text('מה שנכתב כבר לא מוצג כאן',
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 11,
                          color: t.inkFaint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(SoferTokens t, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: TextStyle(
                fontFamily: t.labelFamily, fontSize: 11.5, color: t.inkFaint)),
      );

  /// Where the writer is. Marked, and not tappable — it is not a destination.
  Widget _currentRow(SoferTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: t.accent, width: 1.4),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsetsDirectional.only(end: 10),
              decoration:
                  BoxDecoration(color: t.accent, shape: BoxShape.circle),
            ),
            Text(current.parshiyaName,
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 17, color: t.ink)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(current.whereLabel,
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 13,
                        color: t.inkMuted)),
                if (currentStartedOn != null)
                  Text(_started(currentStartedOn),
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 11,
                          color: t.inkFaint)),
              ],
            ),
            const Spacer(),
            // A parshiya not begun has not reached line one, and "line 0" is
            // a number no sofer counts. It says so in words instead.
            Text(
                currentLine < 1
                    ? 'טרם התחיל'
                    : 'שורה $currentLine מתוך ${current.lineCount}',
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 14,
                    color: t.accent)),
          ],
        ),
      );

  Widget _row(SoferTokens t, TefillinSlot s) {
    final where = 'זוג ${s.pair} · ${TefillinUnits.sideName(s.side)}';
    final trailing = switch (s.state) {
      SlotState.partial =>
        'שורה ${s.linesWritten} מתוך ${TefillinUnits.linesIn(s.side)}',
      SlotState.stuck => 'לתיקון',
      _ => 'מקביל ל־${TefillinUnits.seferLines[s.parshiya - 1]} שורות של ס״ת',
    };
    final trailingColor = s.state == SlotState.stuck ? t.caution : t.inkFaint;

    return InkWell(
      onTap: () => onPick(s),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 17),
            Text(TefillinUnits.names[s.parshiya - 1],
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 16, color: t.ink)),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(where,
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 13,
                        color: t.inkMuted)),
                // Which job this actually is. A pair number alone identifies
                // nothing a writer remembers.
                if (s.startedOn != null)
                  Text(_started(s.startedOn),
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 11,
                          color: t.inkFaint)),
              ],
            ),
            const Spacer(),
            Text(trailing,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12.5,
                    color: trailingColor)),
          ],
        ),
      ),
    );
  }
}

/// The smart-mode position, said the way tefillin wants it said.
///
/// The other types put a number in the large type — "שורה 12" — because that is
/// what they count. A sofer writing tefillin does not think "parshiya 2"; he
/// thinks "the vehaya ki yeviacha of pair four". So the name goes large and the
/// numbers go under it.
class TefillinHero extends StatelessWidget {
  final TefillinPosition position;
  final int currentLine;
  final bool isRunning;
  final VoidCallback onTap;
  final DateTime? startedOn;
  final bool useGregorianDates;

  const TefillinHero({
    super.key,
    required this.position,
    required this.currentLine,
    required this.isRunning,
    required this.onTap,
    this.startedOn,
    this.useGregorianDates = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isRunning)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  decoration:
                      BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    position.parshiyaName,
                    style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 46,
                      height: 1,
                      letterSpacing: -1,
                      color: t.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${position.whereLabel} · שורה $currentLine מתוך ${position.lineCount}',
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 17,
                    color: t.inkMuted),
              ),
              const SizedBox(width: 10),
              Text('שנה  ›',
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 13,
                      color: t.accent)),
            ],
          ),
          // Under the pair, because the pair number on its own is a label the
          // writer has no memory of. The day he began it, he does.
          if (startedOn != null) ...[
            const SizedBox(height: 4),
            Text(
              'התחיל ${formatDisplayDate(startedOn!, useGregorianDates)}',
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 12.5, color: t.inkFaint),
            ),
          ],
        ],
      ),
    );
  }
}
