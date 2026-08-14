import 'package:flutter/material.dart';

import '../logic/hebrew_clock.dart';
import '../logic/writing_rhythm.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

/// When this writer writes fastest.
///
/// The figures were in every record already — the hour a sitting began, how
/// long it took, how much came out of it — and nothing had ever divided them.
/// A sofer who knows his own best hours can plan a day around them, which is
/// something no amount of counting output will tell him.
///
/// Shows nothing at all until there is enough to say. A pace drawn from one
/// sitting is a coincidence, and presenting it with the same confidence as one
/// drawn from thirty is how an app teaches someone the wrong thing about
/// themselves.
class RhythmPanel extends StatelessWidget {
  final Project project;
  final List<WorkSession> sessions;
  final DayStart dayStart;

  const RhythmPanel({
    super.key,
    required this.project,
    required this.sessions,
    required this.dayStart,
  });

  static const List<String> _weekdays = [
    'ראשון',
    'שני',
    'שלישי',
    'רביעי',
    'חמישי',
    'שישי',
    'שבת',
  ];

  static String _hourLabel(int hour) =>
      '${hour.toString().padLeft(2, '0')}:00';

  static String _dayLabel(int weekday) =>
      weekday >= 1 && weekday <= 7 ? _weekdays[weekday - 1] : '';

  /// The hours, drawn to scale against the best of them.
  ///
  /// Hours with too few sittings behind them are drawn faintly rather than left
  /// out: that a writer has barely worked at six in the morning is itself worth
  /// seeing, and a gap would read as "slow" instead of "untested".
  Widget _hourBars(BuildContext context, List<RhythmSlot> hours) {
    final t = SoferTokens.of(context);
    final top = hours.map((h) => h.linesPerHour).reduce((a, b) => a > b ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final hour in hours)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  child: Text(_hourLabel(hour.slot),
                      style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: 13,
                          color: hour.isReliable ? t.ink : t.inkFaint)),
                ),
                Expanded(
                  child: Opacity(
                    opacity: hour.isReliable ? 1 : 0.35,
                    child: SoferProgress(
                        top <= 0 ? 0 : (hour.linesPerHour / top).clamp(0.0, 1.0)),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 76,
                  child: Text(
                    '${hour.linesPerHour.toStringAsFixed(1)} שו׳/שעה',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 11,
                        color: hour.isReliable ? t.inkMuted : t.inkFaint),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tefillin are counted in parshiyot rather than lines, so a lines-per-hour
    // figure would be measuring something this panel does not know the shape
    // of. Better to say nothing than to say it in the wrong unit.
    if (project.type == ProjectType.tefillin) return const SizedBox.shrink();

    final hours = WritingRhythm.byHourOfDay(project, sessions, dayStart);
    final days = WritingRhythm.byDayOfWeek(project, sessions, dayStart);
    final bestHour = WritingRhythm.best(hours);
    final bestDay = WritingRhythm.best(days);

    if (bestHour == null) {
      // Not an empty state to apologise for — it says what is missing and what
      // would fill it, which is the only useful thing to say here.
      return const SizedBox.shrink();
    }

    final t = SoferTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SoferSectionTitle("מתי אתה כותב מהר", padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'הקצב הטוב שלך הוא סביב '),
              TextSpan(
                  text: _hourLabel(bestHour.slot),
                  style: TextStyle(
                      color: t.accent, fontWeight: FontWeight.bold)),
              TextSpan(
                  text: ' — ${bestHour.linesPerHour.toStringAsFixed(1)} '
                      'שורות לשעה'),
              if (bestDay != null) ...[
                const TextSpan(text: ', והיום החזק שלך הוא '),
                TextSpan(
                    text: _dayLabel(bestDay.slot),
                    style: TextStyle(
                        color: t.accent, fontWeight: FontWeight.bold)),
              ],
              const TextSpan(text: '.'),
            ]),
            style: TextStyle(
                fontFamily: t.labelFamily,
                fontSize: 14,
                height: 1.7,
                color: t.inkMuted),
          ),
          const SizedBox(height: 12),
          _hourBars(context, hours),
          const SizedBox(height: 8),
          Text(
            'המידה היא שורות לשעה — כמה נכתב חלקי הזמן שנמדד. '
            'שעות שנמדדו פחות מ-${WritingRhythm.minSittings} פעמים מוצגות בהיר, '
            'כי ישיבה אחת טובה אינה עובדה על אותה שעה.',
            style: TextStyle(
                fontFamily: t.labelFamily,
                fontSize: 11,
                height: 1.7,
                color: t.inkFaint),
          ),
        ],
      ),
    );
  }
}
