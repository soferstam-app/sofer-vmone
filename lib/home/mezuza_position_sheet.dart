import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/mezuza_state.dart';
import '../logic/production_calculator.dart';
import '../theme/app_theme.dart';

/// A short, tap-only position picker for a run of mezuzot.
class MezuzaPositionSheet extends StatelessWidget {
  final int current;
  final int currentLine;
  final DateTime? currentStartedOn;
  final bool useGregorianDates;
  final MezuzaPicks picks;
  final ValueChanged<MezuzaSlot> onPick;

  const MezuzaPositionSheet({
    super.key,
    required this.current,
    required this.currentLine,
    required this.picks,
    required this.onPick,
    this.currentStartedOn,
    this.useGregorianDates = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Material(
      color: t.paper,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        side: BorderSide(color: t.ruleStrong),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('שינוי מיקום',
                  style: TextStyle(
                      fontFamily: t.numeralFamily, fontSize: 21, color: t.ink)),
              const SizedBox(height: 14),
              _section(t, 'הנוכחי'),
              _current(t),
              if (picks.stopped.isNotEmpty) ...[
                const SizedBox(height: 16),
                _section(t, 'עצרתי באמצע'),
                for (final slot in picks.stopped) _row(t, slot),
              ],
              if (picks.nextUp.isNotEmpty) ...[
                const SizedBox(height: 16),
                _section(t, 'הבאות בתור'),
                for (final slot in picks.nextUp) _row(t, slot),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(SoferTokens t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontFamily: t.labelFamily, fontSize: 11.5, color: t.inkFaint)),
      );

  Widget _current(SoferTokens t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(border: Border.all(color: t.accent)),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsetsDirectional.only(end: 10),
              decoration:
                  BoxDecoration(color: t.accent, shape: BoxShape.circle),
            ),
            Text('מזוזה $current',
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 17, color: t.ink)),
            const Spacer(),
            Text(
                'שורה $currentLine מתוך ${ProductionCalculator.linesPerMezuza}',
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 14,
                    color: t.accent)),
          ],
        ),
      );

  Widget _row(SoferTokens t, MezuzaSlot slot) => InkWell(
        onTap: () => onPick(slot),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
          child: Row(
            children: [
              const SizedBox(width: 17),
              Text('מזוזה ${slot.index}',
                  style: TextStyle(
                      fontFamily: t.numeralFamily, fontSize: 16, color: t.ink)),
              const SizedBox(width: 12),
              if (slot.startedOn != null)
                Text(
                    'התחיל ${formatDisplayDate(slot.startedOn!, useGregorianDates)}',
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 11,
                        color: t.inkFaint)),
              const Spacer(),
              Text(
                slot.state == MezuzaSlotState.partial
                    ? 'המשך משורה ${slot.resumeLine}'
                    : 'התחלה',
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12.5,
                    color: slot.state == MezuzaSlotState.partial
                        ? t.accent
                        : t.inkMuted),
              ),
            ],
          ),
        ),
      );
}
