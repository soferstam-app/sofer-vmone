import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/mezuza_state.dart';
import '../logic/production_calculator.dart';
import '../theme/app_theme.dart';
import '../l10n/app_localizations.dart';

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
              Text(context.l10n.pick(he: 'שינוי מיקום', en: 'Change position'),
                  style: TextStyle(
                      fontFamily: t.numeralFamily, fontSize: 21, color: t.ink)),
              const SizedBox(height: 14),
              _section(t, context.l10n.pick(he: 'הנוכחי', en: 'Current')),
              _current(context, t),
              if (picks.stopped.isNotEmpty) ...[
                const SizedBox(height: 16),
                _section(
                    t,
                    context.l10n
                        .pick(he: 'עצרתי באמצע', en: 'Stopped part-way')),
                for (final slot in picks.stopped) _row(context, t, slot),
              ],
              if (picks.nextUp.isNotEmpty) ...[
                const SizedBox(height: 16),
                _section(t, context.l10n.pick(he: 'הבאות בתור', en: 'Next up')),
                for (final slot in picks.nextUp) _row(context, t, slot),
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

  Widget _current(BuildContext context, SoferTokens t) => Container(
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
            Text(
                context.l10n.pick(he: 'מזוזה $current', en: 'Mezuzah $current'),
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 17, color: t.ink)),
            const Spacer(),
            Text(
                context.l10n.pick(
                  he: 'שורה $currentLine מתוך ${ProductionCalculator.linesPerMezuza}',
                  en: 'Line $currentLine of ${ProductionCalculator.linesPerMezuza}',
                ),
                style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 14,
                    color: t.accent)),
          ],
        ),
      );

  Widget _row(BuildContext context, SoferTokens t, MezuzaSlot slot) => InkWell(
        onTap: () => onPick(slot),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
          child: Row(
            children: [
              const SizedBox(width: 17),
              Text(
                  context.l10n.pick(
                      he: 'מזוזה ${slot.index}', en: 'Mezuzah ${slot.index}'),
                  style: TextStyle(
                      fontFamily: t.numeralFamily, fontSize: 16, color: t.ink)),
              const SizedBox(width: 12),
              if (slot.startedOn != null)
                Text(
                    context.l10n.pick(
                      he: 'התחיל ${formatDisplayDate(slot.startedOn!, useGregorianDates)}',
                      en: 'Started ${formatDisplayDate(slot.startedOn!, useGregorianDates, english: true)}',
                    ),
                    style: TextStyle(
                        fontFamily: t.labelFamily,
                        fontSize: 11,
                        color: t.inkFaint)),
              const Spacer(),
              Text(
                slot.state == MezuzaSlotState.partial
                    ? context.l10n.pick(
                        he: 'המשך משורה ${slot.resumeLine}',
                        en: 'Continue from line ${slot.resumeLine}',
                      )
                    : context.l10n.pick(he: 'התחלה', en: 'Start'),
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
