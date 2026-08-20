import 'package:flutter/material.dart';

import '../logic/tefillin_units.dart';
import '../logic/tefillin_state.dart';
import '../theme/app_theme.dart';

/// The whole of a tefillin commission, drawn as the thing itself.
///
/// A commission is many pairs; a pair is a head set and a hand set; a set is
/// four parshiyot that must be written in order. Counting produced a single
/// number for all of that, which is why a writer could not say "pair three is
/// waiting on a correction, I am moving to pair seven" — the app had nowhere to
/// put the sentence.
///
/// Each cell is as wide as the parshiya is long. שמע is seven sefer lines and
/// והיה אם שמע is seventeen, so one is visibly a sliver of the other. That is
/// the arithmetic the summary screen was getting wrong, made into a picture.
enum BoardGrouping {
  /// A row per pair — how the work is delivered.
  byPair,

  /// A block per parshiya — how it is often written. A writer doing the first
  /// ten קדש of an order wants them under each other, not scattered down ten
  /// rows.
  byParshiya,
}

class TefillinBoard extends StatelessWidget {
  final String projectName;

  /// Every slot of the commission. Pairs are 1-based and contiguous.
  final List<TefillinSlot> slots;

  /// Pairs ordered, or null for an open commission — one written against a date
  /// rather than a count, which has no denominator and so shows no percentage.
  final int? pairsOrdered;

  final BoardGrouping grouping;
  final ValueChanged<BoardGrouping>? onGroupingChanged;
  final ValueChanged<TefillinSlot>? onSlotTap;
  final VoidCallback? onHelp;

  /// The daily target, as the writer set it.
  final String dailyTarget;

  const TefillinBoard({
    super.key,
    required this.projectName,
    required this.slots,
    required this.dailyTarget,
    this.pairsOrdered,
    this.grouping = BoardGrouping.byPair,
    this.onGroupingChanged,
    this.onSlotTap,
    this.onHelp,
  });

  /// The next parshiya to write: the first unbegun one, in writing order,
  /// skipping whatever is waiting on a correction.
  TefillinSlot? get _next {
    final ordered = [...slots]..sort((a, b) {
        final byPair = a.pair.compareTo(b.pair);
        if (byPair != 0) return byPair;
        final bySide = a.side.index.compareTo(b.side.index);
        if (bySide != 0) return bySide;
        return a.parshiya.compareTo(b.parshiya);
      });
    for (final s in ordered) {
      if (s.state == SlotState.partial && TefillinState.canWrite(s, slots)) {
        return s;
      }
    }
    for (final s in ordered) {
      if (s.state == SlotState.empty && TefillinState.canStart(s, slots)) {
        return s;
      }
    }
    return null;
  }

  double get _pairsDone {
    var lines = 0.0;
    for (final s in slots) {
      lines += s.seferLinesWritten;
    }
    return lines / TefillinUnits.seferLinesPerPair;
  }

  int get _maxPair => slots.fold(0, (m, s) => s.pair > m ? s.pair : m);

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: t.paper,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
          children: [
            _header(context, t),
            const SizedBox(height: 14),
            _continueStrip(context, t),
            const SizedBox(height: 18),
            if (grouping == BoardGrouping.byPair)
              ..._byPair(context, t)
            else
              ..._byParshiya(context, t),
            const SizedBox(height: 20),
            _legend(context, t),
          ],
        ),
      ),
    );
  }

  // --- Header -------------------------------------------------------------

  Widget _header(BuildContext context, SoferTokens t) {
    final done = _pairsDone;
    final ordered = pairsOrdered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                projectName,
                style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 21,
                  color: t.ink,
                ),
              ),
            ),
            _grouper(context, t),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              ordered == null
                  ? '${done.toStringAsFixed(2)} זוגות נכתבו · הזמנה פתוחה'
                  : '${done.toStringAsFixed(2)} מתוך $ordered זוגות · '
                      '${(done / ordered * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 13, color: t.inkMuted),
            ),
            Text('  ·  ', style: TextStyle(color: t.inkFaint)),
            Text(
              'יעד יומי: $dailyTarget',
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(width: 4),
            // Where the percentages live. A writer setting a target in
            // parshiyot has no way of knowing that four קדש and four שמע are
            // not the same day's work unless something tells him.
            InkWell(
              onTap: onHelp,
              customBorder: const CircleBorder(),
              child: Container(
                width: 19,
                height: 19,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.inkFaint),
                ),
                child: Text('?',
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        height: 1.1,
                        color: t.inkMuted)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: t.ruleStrong),
      ],
    );
  }

  Widget _grouper(BuildContext context, SoferTokens t) {
    Widget tab(String label, BoardGrouping value) {
      final on = grouping == value;
      return InkWell(
        onTap: () => onGroupingChanged?.call(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
          decoration: BoxDecoration(
            color: on ? t.accent : Colors.transparent,
            border: Border.all(color: on ? t.accent : t.rule),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: t.labelFamily,
              fontSize: 12,
              color: on ? t.paper : t.inkMuted,
            ),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      tab('לפי זוג', BoardGrouping.byPair),
      const SizedBox(width: 6),
      tab('לפי פרשייה', BoardGrouping.byParshiya),
    ]);
  }

  Widget _continueStrip(BuildContext context, SoferTokens t) {
    final next = _next;
    if (next == null) {
      return Text('ההזמנה הושלמה',
          style: TextStyle(
              fontFamily: t.labelFamily, fontSize: 13, color: t.positive));
    }
    final where = 'זוג ${next.pair} · ${TefillinUnits.sideName(next.side)} · '
        '${TefillinUnits.names[next.parshiya - 1]}';

    return Row(
      children: [
        InkWell(
          onTap: () => onSlotTap?.call(next),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: t.accent),
            child: Text('המשך כאן',
                style: TextStyle(
                    fontFamily: t.labelFamily, fontSize: 13, color: t.paper)),
          ),
        ),
        const SizedBox(width: 12),
        Text(where,
            style: TextStyle(
                fontFamily: t.numeralFamily, fontSize: 14, color: t.ink)),
        if (next.state == SlotState.partial)
          Text('  (עצר בשורה ${next.linesWritten})',
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 12, color: t.inkMuted)),
      ],
    );
  }

  // --- Grouped by pair ----------------------------------------------------

  List<Widget> _byPair(BuildContext context, SoferTokens t) {
    final rows = <Widget>[_pairColumnHeadings(t)];

    for (var pair = 1; pair <= _maxPair; pair++) {
      rows.add(_pairRow(context, t, pair));
    }
    return rows;
  }

  Widget _pairColumnHeadings(SoferTokens t) {
    Widget side(String label) => Expanded(
          flex: TefillinUnits.seferLinesPerSet,
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: t.inkMuted)),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Expanded(
                      flex: TefillinUnits.seferLines[i],
                      child: Text(
                        TefillinUnits.shortNames[i],
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 10,
                            color: t.inkFaint),
                      ),
                    ),
                    if (i < 3) const SizedBox(width: 2),
                  ],
                ],
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: 52),
          side('ראש'),
          const SizedBox(width: 18),
          side('יד'),
        ],
      ),
    );
  }

  Widget _pairRow(BuildContext context, SoferTokens t, int pair) {
    List<TefillinSlot> setOf(TefillinSide side) {
      final found = slots
          .where((s) => s.pair == pair && s.side == side)
          .toList()
        ..sort((a, b) => a.parshiya.compareTo(b.parshiya));
      return found;
    }

    Widget set(TefillinSide side) => Expanded(
          flex: TefillinUnits.seferLinesPerSet,
          child: Row(
            children: [
              for (final s in setOf(side)) ...[
                Expanded(
                  flex: TefillinUnits.seferLines[s.parshiya - 1],
                  child: _cell(context, t, s, showName: false),
                ),
                if (s.parshiya < 4) const SizedBox(width: 2),
              ],
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text('זוג $pair',
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 13,
                    color: t.inkMuted)),
          ),
          set(TefillinSide.head),
          const SizedBox(width: 18),
          set(TefillinSide.hand),
        ],
      ),
    );
  }

  // --- Grouped by parshiya ------------------------------------------------

  List<Widget> _byParshiya(BuildContext context, SoferTokens t) {
    final blocks = <Widget>[];

    for (var p = 1; p <= 4; p++) {
      blocks.add(Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(TefillinUnits.names[p - 1],
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 15, color: t.ink)),
            const SizedBox(width: 8),
            Text('מקביל ל־${TefillinUnits.seferLines[p - 1]} שורות של ס״ת',
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 11,
                    color: t.inkFaint)),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: t.rule)),
          ],
        ),
      ));

      for (final side in TefillinSide.values) {
        final row = slots
            .where((s) => s.parshiya == p && s.side == side)
            .toList()
          ..sort((a, b) => a.pair.compareTo(b.pair));

        blocks.add(Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(TefillinUnits.sideName(side),
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 12,
                        color: t.inkMuted)),
              ),
              for (final s in row) ...[
                Expanded(child: _cell(context, t, s, showName: true)),
                const SizedBox(width: 3),
              ],
            ],
          ),
        ));
      }
      blocks.add(const SizedBox(height: 10));
    }
    return blocks;
  }

  // --- One cell -----------------------------------------------------------

  Widget _cell(BuildContext context, SoferTokens t, TefillinSlot s,
      {required bool showName}) {
    final fraction = s.fraction;

    Color border;
    Color text;
    switch (s.state) {
      case SlotState.done:
        border = t.accent;
        text = t.paper;
      case SlotState.partial:
        border = t.accent;
        text = t.ink;
      case SlotState.stuck:
        border = t.caution;
        text = t.caution;
      case SlotState.voided:
        border = t.danger;
        text = t.danger;
      case SlotState.empty:
        border = t.rule;
        text = t.inkFaint;
    }

    final label = showName
        ? 'זוג ${s.pair}'
        : (s.state == SlotState.partial ? '${s.linesWritten}' : '');

    return InkWell(
      onTap: () => onSlotTap?.call(s),
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.paper,
          border: Border.all(
              color: border, width: s.state == SlotState.empty ? 1 : 1.4),
          // Writing runs right to left, and so does the fill.
          gradient: fraction > 0
              ? LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [t.accent, t.accent, t.paper, t.paper],
                  stops: [0, fraction, fraction, 1],
                )
              : null,
        ),
        child: s.state == SlotState.stuck || s.state == SlotState.voided
            ? CustomPaint(
                painter: _HatchPainter(border, s.state == SlotState.voided),
                child: Center(
                  child: Text(
                    s.state == SlotState.voided ? 'נפסל' : 'לתיקון',
                    style: TextStyle(
                        fontFamily: t.labelFamily, fontSize: 10, color: text),
                  ),
                ),
              )
            : Text(label,
                style: TextStyle(
                    fontFamily: t.labelFamily, fontSize: 10.5, color: text)),
      ),
    );
  }

  // --- Legend -------------------------------------------------------------

  Widget _legend(BuildContext context, SoferTokens t) {
    Widget item(Widget swatch, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch,
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 11,
                    color: t.inkMuted)),
          ],
        );

    Widget box({Color? fill, required Color line, double filled = 0}) =>
        Container(
          width: 26,
          height: 15,
          decoration: BoxDecoration(
            color: t.paper,
            border: Border.all(color: line),
            gradient: filled > 0
                ? LinearGradient(
                    begin: Alignment.centerRight,
                    end: Alignment.centerLeft,
                    colors: [t.accent, t.accent, t.paper, t.paper],
                    stops: [0, filled, filled, 1],
                  )
                : null,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: t.rule),
        const SizedBox(height: 10),
        Wrap(spacing: 20, runSpacing: 8, children: [
          item(box(line: t.rule), 'טרם נכתב'),
          item(box(line: t.accent, filled: 0.55), 'בכתיבה'),
          item(box(line: t.accent, filled: 1), 'נכתב'),
          item(box(line: t.caution), 'ממתין לתיקון'),
          item(box(line: t.danger), 'נפסל'),
        ]),
        const SizedBox(height: 10),
        Text(
          'רוחב התא הוא גודל הפרשייה בפועל — שמע מקבילה ל־7 שורות '
          'של ס״ת, והיה אם שמע מקבילה ל־17.',
          style: TextStyle(
              fontFamily: t.labelFamily, fontSize: 11, color: t.inkFaint),
        ),
      ],
    );
  }
}

/// Diagonal ruling across a slot that is not being written on.
class _HatchPainter extends CustomPainter {
  final Color color;
  final bool dense;

  _HatchPainter(this.color, this.dense);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: dense ? 0.55 : 0.35)
      ..strokeWidth = 1;
    final step = dense ? 5.0 : 7.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter old) =>
      old.color != color || old.dense != dense;
}

/// What each parshiya is worth, shown where the writer sets a target.
///
/// Without this, "four parshiyot a day" is a number set blind: four קדש is
/// sixty-four sefer lines and four שמע is twenty-eight, and nothing on the
/// form said so.
class TefillinShareHelp extends StatelessWidget {
  const TefillinShareHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    TableRow row(String a, String b, String c, {bool strong = false}) {
      TextStyle style(bool numeric) => TextStyle(
            fontFamily: numeric ? t.numeralFamily : t.labelFamily,
            fontSize: 13,
            color: strong ? t.ink : t.inkMuted,
          );
      return TableRow(
        children: [
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(a, style: style(false))),
          Text(b, textAlign: TextAlign.center, style: style(true)),
          Text(c, textAlign: TextAlign.center, style: style(true)),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: t.paper,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.panelRadius),
            side: BorderSide(color: t.ruleStrong)),
        title: Text('כמה שווה כל פרשייה',
            style: TextStyle(fontFamily: t.numeralFamily, color: t.ink)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'שורה של תפילין רחבה בהרבה משורה של ספר תורה: מספר השורות '
                'קבוע, ולכן הכתב נמתח לרוחב לפי אורך הפרשייה. המספרים כאן הם '
                'מקבילים למספר שורות של ס״ת, וכך אפשר להשוות הספק בין תפילין, '
                'מזוזות וספר תורה.',
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12.5,
                    height: 1.6,
                    color: t.inkMuted),
              ),
              const SizedBox(height: 14),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.2),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
                border:
                    TableBorder(horizontalInside: BorderSide(color: t.rule)),
                children: [
                  row('פרשייה', 'מקביל לשורות של ס״ת', 'חלק מהסט',
                      strong: true),
                  for (var i = 0; i < 4; i++)
                    row(
                      TefillinUnits.names[i],
                      '${TefillinUnits.seferLines[i]}',
                      '${(TefillinUnits.shareOfSet(i + 1) * 100).toStringAsFixed(1)}%',
                    ),
                  row('סט שלם (ראש או יד)', '52', '100%', strong: true),
                  row('זוג — ראש ויד', '104', '2 סטים', strong: true),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'זוג שלם הוא 104 שורות — כ־2.5 עמודים של ספר תורה.\n'
                'את היעד היומי אפשר לקבוע בפרשיות או בסטים עשרוניים, בהגדרות.',
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    height: 1.7,
                    color: t.inkFaint),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('סגור', style: TextStyle(color: t.accent)),
          ),
        ],
      ),
    );
  }
}
