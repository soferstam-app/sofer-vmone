import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

/// How much of each unit has been written. Keys are 1-based — there is no
/// page 0 — and values run from 0 to 1.
typedef UnitFill = Map<int, double>;

/// A run of units sharing a state, for stating the map in words.
class UnitRun {
  final int from;
  final int to;
  final double fill;

  const UnitRun(this.from, this.to, this.fill);

  bool get isFull => fill >= 1;
  bool get isEmpty => fill <= 0;
  int get length => to - from + 1;
}

/// Groups consecutive units of the same state into runs.
///
/// This is what makes the map worth reading: for work done in order it collapses
/// to two or three runs, and the interesting case — a hole left by a correction
/// — shows up as a run of its own instead of having to be spotted in a field of
/// cells.
List<UnitRun> unitRuns(int total, UnitFill fill) {
  final runs = <UnitRun>[];
  if (total <= 0) return runs;

  double stateOf(int unit) {
    final value = fill[unit] ?? 0;
    // Anything part-written is its own state; full and empty group freely.
    return value <= 0 ? 0 : (value >= 1 ? 1 : value);
  }

  var start = 1;
  var current = stateOf(1);
  for (var unit = 2; unit <= total; unit++) {
    final next = stateOf(unit);
    final samePartial = current > 0 && current < 1;
    if (next != current || samePartial) {
      runs.add(UnitRun(start, unit - 1, current));
      start = unit;
      current = next;
    }
  }
  runs.add(UnitRun(start, total, current));
  return runs;
}

/// The whole commission as one continuous band.
///
/// A scroll is a continuous strip, not a grid, so this is nearer to the object
/// than a field of squares is — and it stays legible at 245 units where squares
/// large enough to label came to thousands of pixels of grid.
///
/// With [rows] above one the band is wrapped, which is how a hole in the middle
/// of a long commission becomes findable.
class ScrollMap extends StatelessWidget {
  final int total;
  final UnitFill fill;
  final double bandHeight;
  final int rows;

  const ScrollMap({
    super.key,
    required this.total,
    required this.fill,
    this.bandHeight = 38,
    this.rows = 1,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    if (total <= 0) return const SizedBox.shrink();

    final perRow = (total / rows).ceil();

    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          if (row > 0) const SizedBox(height: 4),
          Container(
            height: bandHeight,
            decoration: BoxDecoration(
              border: Border.all(color: rows == 1 ? t.ruleStrong : t.rule),
            ),
            child: CustomPaint(
              painter: _BandPainter(
                from: row * perRow + 1,
                to: ((row + 1) * perRow).clamp(1, total),
                fill: fill,
                written: t.accent,
                blank: t.paper,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ],
    );
  }
}

class _BandPainter extends CustomPainter {
  final int from;
  final int to;
  final UnitFill fill;
  final Color written;
  final Color blank;

  _BandPainter({
    required this.from,
    required this.to,
    required this.fill,
    required this.written,
    required this.blank,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = to - from + 1;
    if (count <= 0) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = blank);
    final ink = Paint()..color = written;
    final slice = size.width / count;

    // Right to left: the first unit of a Hebrew scroll sits at the right edge.
    for (var i = 0; i < count; i++) {
      final value = (fill[from + i] ?? 0).clamp(0.0, 1.0);
      if (value <= 0) continue;
      final right = size.width - i * slice;
      canvas.drawRect(
        Rect.fromLTRB(right - slice, 0, right, size.height * value),
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      old.from != from ||
      old.to != to ||
      old.written != written ||
      !identical(old.fill, fill);
}

/// Opens the map over the screen it was asked for from.
Future<void> showScrollMap(
  BuildContext context, {
  required String title,
  required int total,
  required UnitFill fill,
  required String unitSingular,
  required String unitPlural,
  bool hebrewNumerals = true,
}) {
  return showDialog(
    context: context,
    builder: (ctx) {
      final t = SoferTokens.of(ctx);
      final runs = unitRuns(total, fill);
      final full = runs.where((r) => r.isFull).toList();
      final partial = runs.where((r) => !r.isFull && !r.isEmpty).toList();
      final untouched = runs.where((r) => r.isEmpty).toList();

      String label(int n) =>
          hebrewNumerals ? formatHebrewNumber(n) : n.toString();
      String range(UnitRun r) => r.length == 1
          ? label(r.from)
          : "${label(r.from)}–${label(r.to)}";
      String list(List<UnitRun> rs) => rs.map(range).join(", ");
      int count(List<UnitRun> rs) =>
          rs.fold(0, (sum, r) => sum + r.length);

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SoferSectionTitle("כל העבודה · $total $unitPlural",
                    padding: EdgeInsets.zero),
                const SizedBox(height: 8),
                ScrollMap(total: total, fill: fill),
                const SizedBox(height: 3),
                _Ruler(total: total, label: label),
                if (total > 60) ...[
                  const SizedBox(height: 18),
                  SoferSectionTitle("מחולק לשורות · לאיתור חורים",
                      padding: EdgeInsets.zero),
                  const SizedBox(height: 8),
                  ScrollMap(
                      total: total, fill: fill, rows: 5, bandHeight: 14),
                ],
                const SizedBox(height: 18),
                const SoferRule(),
                const SizedBox(height: 12),
                if (full.isNotEmpty)
                  _Legend(
                    swatch: t.accent,
                    label: "נכתב במלואו",
                    detail: "$unitPlural ${list(full)}",
                    trailing: "${count(full)}",
                  ),
                for (final r in partial)
                  _Legend(
                    swatch: t.accent,
                    half: true,
                    label: "חלקי",
                    detail: "$unitSingular ${range(r)} — "
                        "${(r.fill * 100).toStringAsFixed(0)}%",
                  ),
                if (untouched.isNotEmpty)
                  _Legend(
                    swatch: t.paper,
                    outlined: true,
                    label: "טרם נכתב",
                    detail: "$unitPlural ${list(untouched)}",
                    trailing: "${count(untouched)}",
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("סגור")),
        ],
      );
    },
  );
}

/// Tick marks under the band, so a position can be read off it.
class _Ruler extends StatelessWidget {
  final int total;
  final String Function(int) label;

  const _Ruler({required this.total, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    const divisions = 8;
    return Column(
      children: [
        Row(children: [
          for (var i = 0; i < divisions; i++)
            Expanded(
              child: Container(
                height: 5,
                decoration: BoxDecoration(
                  border: Border(
                    left: i == 0
                        ? BorderSide.none
                        : BorderSide(color: t.rule),
                  ),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 3),
        Row(children: [
          for (var i = 0; i < divisions; i++)
            Expanded(
              child: Text(
                label(i == 0 ? 1 : (total * i / divisions).round()),
                textAlign: i == 0 ? TextAlign.right : TextAlign.center,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 10,
                    color: t.inkMuted),
              ),
            ),
        ]),
      ],
    );
  }
}

/// One state of the map, stated in words next to its swatch.
class _Legend extends StatelessWidget {
  final Color swatch;
  final String label;
  final String detail;
  final String? trailing;
  final bool half;
  final bool outlined;

  const _Legend({
    required this.swatch,
    required this.label,
    required this.detail,
    this.trailing,
    this.half = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsetsDirectional.only(end: 9, top: 3),
            decoration: BoxDecoration(
              color: outlined ? t.paper : null,
              border: Border.all(color: outlined ? t.rule : swatch),
              gradient: half
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [swatch, swatch, t.paper, t.paper],
                      stops: const [0, .45, .45, 1],
                    )
                  : null,
            ),
            child: half || outlined
                ? null
                : ColoredBox(color: swatch, child: const SizedBox.expand()),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: "$label: ",
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 13,
                        color: t.inkMuted)),
                TextSpan(
                    text: detail,
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: 14,
                        color: t.ink)),
              ]),
            ),
          ),
          if (trailing != null)
            Text(trailing!,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    color: t.inkFaint)),
        ],
      ),
    );
  }
}
