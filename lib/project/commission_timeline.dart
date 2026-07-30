import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A point worth marking on the run from start to delivery.
class TimelineMark {
  final String caption;
  final String value;

  /// 0 at the start of the run, 1 at its end.
  final double at;

  /// Drawn in the accent — reserved for where the writer is now.
  final bool current;

  /// Drawn faintly, for a date that is a commitment rather than a measurement.
  final bool quiet;

  const TimelineMark({
    required this.caption,
    required this.value,
    required this.at,
    this.current = false,
    this.quiet = false,
  });
}

/// The commission as a line from the day it began to the day it lands.
///
/// The estimate and the agreed deadline both sit on it, and the distance between
/// them is the answer to the only question a client ever asks. Read off the line
/// rather than worked out from two dates in a table.
class CommissionTimeline extends StatelessWidget {
  final List<TimelineMark> marks;

  /// How far along the work is, 0 to 1 — the length drawn in the accent.
  final double progress;

  const CommissionTimeline({
    super.key,
    required this.marks,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final done = progress.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;

        return SizedBox(
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The run itself, right to left: Hebrew reads that way and so does
              // the scroll.
              Positioned(
                top: 30,
                right: 0,
                left: 0,
                child: Container(height: 2, color: t.rule),
              ),
              Positioned(
                top: 30,
                right: 0,
                child: Container(
                  height: 2,
                  width: (width * done).clamp(2.0, width),
                  color: t.accent,
                ),
              ),
              for (final mark in marks)
                _Mark(mark: mark, width: width),
            ],
          ),
        );
      },
    );
  }
}

class _Mark extends StatelessWidget {
  final TimelineMark mark;
  final double width;

  const _Mark({required this.mark, required this.width});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final offset = (width * mark.at.clamp(0.0, 1.0));
    // Labels at the ends align inwards so they cannot run off the edge.
    final atStart = mark.at <= 0.02;
    final atEnd = mark.at >= 0.98;
    final colour = mark.current
        ? t.accent
        : mark.quiet
            ? t.inkMuted
            : t.ink;

    final label = Column(
      crossAxisAlignment: atStart
          ? CrossAxisAlignment.end
          : atEnd
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(mark.caption,
            style: TextStyle(
                fontFamily: t.labelFamily,
                fontSize: 11,
                letterSpacing: 1.2,
                color: t.inkMuted)),
        const SizedBox(height: 1),
        Text(mark.value,
            maxLines: 1,
            style: TextStyle(
                fontFamily: t.numeralFamily, fontSize: 14, color: colour)),
      ],
    );

    // The mark on the line: a dot for where the writer is, a tick for a date.
    final tick = mark.current
        ? Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          )
        : Container(width: 2, height: 14, color: colour);

    // A mid-line label is centred on its tick, which means shifting it half its
    // own width — and clamping so it cannot run off either edge.
    const boxWidth = 132.0;
    final anchor = atEnd
        ? null
        : atStart
            ? 0.0
            : (offset - boxWidth / 2).clamp(0.0, (width - boxWidth).clamp(0.0, width));

    return Positioned(
      // Right-anchored, because the line runs right to left.
      right: anchor,
      left: atEnd ? 0 : null,
      top: 0,
      child: SizedBox(
        width: atStart || atEnd ? null : boxWidth,
        child: Column(
          crossAxisAlignment: atStart
              ? CrossAxisAlignment.end
              : atEnd
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
          children: [label, const SizedBox(height: 4), tick],
        ),
      ),
    );
  }
}
