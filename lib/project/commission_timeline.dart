import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A point worth marking on the run from start to delivery.
class TimelineMark {
  final String caption;

  /// The date, written out. Left empty for a mark whose caption already says
  /// everything there is to say — "today" needs no date printed beside it.
  final String value;

  /// 0 at the start of the run, 1 at its end.
  final double at;

  /// Drawn in the accent — reserved for where the writer is now.
  final bool current;

  /// Drawn faintly, for a date that is a commitment rather than a measurement.
  final bool quiet;

  const TimelineMark({
    required this.caption,
    this.value = '',
    required this.at,
    this.current = false,
    this.quiet = false,
  });
}

/// The commission as a line from the day it began to the day it lands.
///
/// One scale only, and that scale is time. An earlier version placed the ticks
/// by date but drew the accent by how much of the work was done, which put two
/// unrelated quantities on one line: the "you are here" dot sat a quarter of
/// the way along and was labelled 0%, which is simply two different questions
/// answered in one place. How much is written is stated in its own row now.
///
/// The two ends carry their dates above the line, aligned inwards so they
/// cannot run off the edge at any width. Everything between them carries its
/// label below the line, stacked into as many rows as it takes so that two
/// labels never print on top of each other however the dates happen to fall.
class CommissionTimeline extends StatelessWidget {
  final List<TimelineMark> marks;

  /// How much of the run has already gone by, 0 to 1 — the length drawn in the
  /// accent.
  final double elapsed;

  const CommissionTimeline({
    super.key,
    required this.marks,
    required this.elapsed,
  });

  /// Where the ticks begin, measured from the top of the widget. The end labels
  /// sit in the space above them.
  static const double tickTop = 40;
  static const double tickHeight = 14;

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final gone = elapsed.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;

        final ends = <TimelineMark>[];
        final middles =
            <({TimelineMark mark, double from, double span, int row})>[];
        final taken = <({double from, double to, int row})>[];

        // One label to each end at most. Two dates can land on the same end —
        // a commission that began today and finishes today puts everything at
        // once — and stacking them there would print one over the other, so the
        // second goes below the line with the rest.
        var startTaken = false;
        var endTaken = false;

        for (final mark in marks) {
          final at = mark.at.clamp(0.0, 1.0);
          if (at <= 0.02 && !startTaken) {
            startTaken = true;
            ends.add(mark);
            continue;
          }
          if (at >= 0.98 && !endTaken) {
            endTaken = true;
            ends.add(mark);
            continue;
          }
          // A label with a date under it needs room for the date; one with only
          // a caption does not, and staying narrow is what keeps it clear of
          // its neighbours.
          final span = (mark.value.isEmpty ? 56.0 : 124.0).clamp(0.0, width);
          final from = (width * at - span / 2)
              .clamp(0.0, (width - span).clamp(0.0, width));
          var row = 0;
          while (taken.any((other) =>
              other.row == row &&
              from < other.to + 8 &&
              from + span + 8 > other.from)) {
            row++;
          }
          taken.add((from: from, to: from + span, row: row));
          middles.add((mark: mark, from: from, span: span, row: row));
        }

        final rowHeight =
            middles.any((m) => m.mark.value.isNotEmpty) ? 38.0 : 20.0;
        final rows = middles.isEmpty
            ? 0
            : middles.map((m) => m.row).reduce((a, b) => a > b ? a : b) + 1;
        final height = tickTop + tickHeight + 3 + rows * rowHeight;

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The run itself, right to left: Hebrew reads that way and so does
              // the scroll.
              Positioned(
                top: tickTop + 6,
                right: 0,
                left: 0,
                child: Container(height: 2, color: t.rule),
              ),
              Positioned(
                top: tickTop + 6,
                right: 0,
                child: Container(
                  height: 2,
                  width: (width * gone).clamp(2.0, width),
                  color: t.accent,
                ),
              ),
              for (final mark in ends)
                _EndMark(
                  mark: mark,
                  width: width,
                  bottom: height - (tickTop + tickHeight),
                ),
              for (final m in middles)
                _MidMark(
                  mark: m.mark,
                  from: m.from,
                  span: m.span,
                  drop: m.row * rowHeight,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A date at one end of the run, printed above the line.
class _EndMark extends StatelessWidget {
  final TimelineMark mark;
  final double width;

  /// Distance from the bottom of the widget to the foot of the tick. Anchoring
  /// by the bottom rather than by a fixed height means the label can be as tall
  /// as the font makes it without ever pushing the tick off the line.
  final double bottom;

  const _EndMark({
    required this.mark,
    required this.width,
    required this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final atStart = mark.at <= 0.02;
    final colour = mark.current
        ? t.accent
        : mark.quiet
            ? t.inkMuted
            : t.ink;

    // In this direction the start of the run is the right edge, so the opening
    // mark aligns to start and the closing one to end. Having these the wrong
    // way round is what threw the labels across the page.
    return Positioned(
      right: atStart ? 0 : null,
      left: atStart ? null : 0,
      bottom: bottom,
      child: SizedBox(
        // Never more than a little under half the run, so the two ends cannot
        // meet in the middle however long the dates are.
        width: width * 0.46,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              atStart ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(mark.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: t.inkMuted)),
            const SizedBox(height: 1),
            Text(mark.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: atStart ? TextAlign.start : TextAlign.end,
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 14, color: colour)),
            const SizedBox(height: 4),
            SizedBox(
              height: CommissionTimeline.tickHeight,
              child: Container(width: 2, color: colour),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mark somewhere along the run, labelled below the line.
class _MidMark extends StatelessWidget {
  final TimelineMark mark;

  /// Offset of the label box from the right edge — the line runs right to left.
  final double from;
  final double span;

  /// How far the label drops below the line, to keep clear of a neighbour.
  final double drop;

  const _MidMark({
    required this.mark,
    required this.from,
    required this.span,
    required this.drop,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final colour = mark.current
        ? t.accent
        : mark.quiet
            ? t.inkMuted
            : t.ink;

    return Positioned(
      right: from,
      top: CommissionTimeline.tickTop,
      child: SizedBox(
        width: span,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: CommissionTimeline.tickHeight,
              child: Center(
                child: mark.current
                    // A dot for where the writer is, a tick for a date.
                    ? Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: colour, shape: BoxShape.circle),
                      )
                    : Container(
                        width: 2,
                        height: CommissionTimeline.tickHeight,
                        color: colour),
              ),
            ),
            SizedBox(height: 3 + drop),
            Text(mark.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    color: mark.current ? colour : t.inkMuted)),
            if (mark.value.isNotEmpty)
              Text(mark.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: t.numeralFamily,
                      fontSize: 13,
                      color: colour)),
          ],
        ),
      ),
    );
  }
}
