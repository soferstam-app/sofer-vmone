import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/calendar_days.dart';
import 'logic/hebrew_work_calendar.dart';
import 'storage_service.dart';
import 'theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'settings/work_day_exception_dialog.dart';
import 'widgets/feedback.dart';

/// Which days the writer actually sits down to write.
///
/// Every completion estimate in the app is built from these answers, so they are
/// worth getting right once. The days nobody writes on are stated but not
/// offered as choices; everything soferim genuinely differ on is a choice of
/// three — a full day, half a day, or not a working day.
class WorkCalendarSettingsScreen extends StatefulWidget {
  const WorkCalendarSettingsScreen({super.key});

  @override
  State<WorkCalendarSettingsScreen> createState() =>
      _WorkCalendarSettingsScreenState();
}

class _WorkCalendarSettingsScreenState
    extends State<WorkCalendarSettingsScreen> {
  final StorageService _storage = StorageService();

  WorkCalendarRules _rules = WorkCalendarRules.standard;
  bool _useGregorianDates = false;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.getWorkCalendarRules();
    final gregorian = await _storage.getUseGregorianDates();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _useGregorianDates = gregorian;
      _loaded = true;
    });
  }

  Future<void> _update(WorkCalendarRules next) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _storage.setWorkCalendarRules(next);
      if (mounted) setState(() => _rules = next);
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'השינוי לא נשמר. בדוק שיש מקום פנוי ונסה שוב.',
              en: 'The change was not saved. Check free storage space and retry.',
            ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editException({String? key}) async {
    if (_saving) return;
    final existing = key == null ? null : _rules.exceptions[key];
    final picked = await showDialog<WorkDayExceptionChoice>(
      context: context,
      builder: (_) => WorkDayExceptionDialog(
        date: key == null ? DateTime.now() : DateTime.parse(key),
        existing: existing,
        gregorian: _useGregorianDates,
        takenDates: _rules.exceptions.keys.toSet(),
      ),
    );
    if (picked == null || !mounted) return;
    final next = Map<String, WorkDayException>.from(_rules.exceptions);
    if (key != null) next.remove(key);
    next[WorkCalendarRules.dateKey(picked.date)] = picked.exception;
    await _update(_rules.copyWith(exceptions: next));
  }

  List<Widget> _personalExceptions() {
    final dates = _rules.exceptions.keys.toList()..sort();
    return [
      _sectionTitle(context.l10n
          .pick(he: 'חריגות אישיות לפי תאריך', en: 'Personal date exceptions')),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(context.l10n.pick(
            he: 'יום חופש או חצי יום לכל הפרויקטים. משפיע על התכנון וצפי הסיום; אינו משנה כתיבה שכבר נשמרה. יום שכבר סגור בלוח נשאר סגור.',
            en: 'A day off or half day across all projects. Affects planning and completion estimates; recorded work stays unchanged. Days already closed by the calendar stay closed.',
          ))),
      for (final key in dates)
        ListTile(
          key: ValueKey('personal-exception-$key'),
          leading: const Icon(Icons.event_busy),
          title: Text(
              '${formatDisplayDate(DateTime.parse(key), false, english: context.l10n.isEnglish)} · ${formatDisplayDate(DateTime.parse(key), true, english: context.l10n.isEnglish)}'),
          subtitle: Text([
            _rules.exceptions[key]!.weight == DayWeight.half
                ? context.l10n.pick(he: 'חצי יום', en: 'Half day')
                : context.l10n.pick(he: 'יום חופש', en: 'Day off'),
            if (_rules.exceptions[key]!.note.isNotEmpty)
              _rules.exceptions[key]!.note,
          ].join(' · ')),
          onTap: _saving ? null : () => _editException(key: key),
          trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip:
                  context.l10n.pick(he: 'מחק חריגה', en: 'Delete exception'),
              onPressed: _saving
                  ? null
                  : () {
                      final next =
                          Map<String, WorkDayException>.from(_rules.exceptions)
                            ..remove(key);
                      _update(_rules.copyWith(exceptions: next));
                    }),
        ),
      Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: _saving ? null : () => _editException(),
            icon: const Icon(Icons.add),
            label: Text(context.l10n
                .pick(he: 'הוסף תאריך חריג', en: 'Add date exception')),
          )),
      const Divider(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(context.l10n.pick(he: "ימי עבודה", en: "Workdays")),
          centerTitle: true),
      // The same content in both layouts — a phone scrolls one column, a desktop
      // window gets a readable measure instead of stretched-out rows.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              _intro(),
              ..._personalExceptions(),
              _fixedDaysCard(),
              _sectionTitle(context.l10n.pick(he: "סוף שבוע", en: "Weekend")),
              _weightTile(
                icon: Icons.weekend,
                title: context.l10n.pick(he: "יום שישי", en: "Friday"),
                value: _rules.friday,
                allowFull: false,
                onChanged: (w) => _update(_rules.copyWith(friday: w)),
              ),
              _weightTile(
                icon: Icons.nightlight_round,
                title:
                    context.l10n.pick(he: "מוצאי שבת", en: "Motzaei Shabbat"),
                value: _rules.motzeiShabbat,
                allowFull: false,
                onChanged: (w) => _update(_rules.copyWith(motzeiShabbat: w)),
              ),
              const Divider(),
              _sectionTitle(context.l10n.pick(he: "צומות", en: "Fasts")),
              _weightTile(
                icon: Icons.no_food,
                title: context.l10n.pick(he: "י״ז בתמוז", en: "17 Tammuz"),
                value: _rules.fastSeventeenTammuz,
                onChanged: (w) =>
                    _update(_rules.copyWith(fastSeventeenTammuz: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title: context.l10n.pick(he: "צום גדליה", en: "Tzom Gedaliah"),
                value: _rules.fastGedalya,
                onChanged: (w) => _update(_rules.copyWith(fastGedalya: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title: context.l10n.pick(he: "י׳ בטבת", en: "10 Tevet"),
                value: _rules.fastTenthTevet,
                onChanged: (w) => _update(_rules.copyWith(fastTenthTevet: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title:
                    context.l10n.pick(he: "תענית אסתר", en: "Ta’anit Esther"),
                value: _rules.fastEsther,
                onChanged: (w) => _update(_rules.copyWith(fastEsther: w)),
              ),
              const Divider(),
              _sectionTitle(
                  context.l10n.pick(he: "מועדים", en: "Special days")),
              _weightTile(
                icon: Icons.local_fire_department,
                title: context.l10n.pick(he: "חנוכה", en: "Chanukah"),
                subtitle:
                    context.l10n.pick(he: "שמונת הימים", en: "All eight days"),
                value: _rules.chanukah,
                onChanged: (w) => _update(_rules.copyWith(chanukah: w)),
              ),
              _weightTile(
                icon: Icons.local_fire_department_outlined,
                title: context.l10n.pick(he: "ל״ג בעומר", en: "Lag BaOmer"),
                value: _rules.lagBaomer,
                onChanged: (w) => _update(_rules.copyWith(lagBaomer: w)),
              ),
              _weightTile(
                icon: Icons.celebration,
                title: context.l10n.pick(he: "איסרו חג", en: "Isru Chag"),
                subtitle: context.l10n.pick(
                    he: "למחרת פסח, שבועות וסוכות",
                    en: "The day after Pesach, Shavuot, and Sukkot"),
                value: _rules.isruChag,
                onChanged: (w) => _update(_rules.copyWith(isruChag: w)),
              ),
              _weightTile(
                icon: Icons.cabin,
                title: context.l10n.pick(
                    he: "בין יום כיפור לסוכות",
                    en: "Between Yom Kippur and Sukkot"),
                subtitle: context.l10n.pick(
                    he: "י״א–י״ג תשרי (י״ד הוא ערב סוכות)",
                    en: "11–13 Tishrei (14 is Erev Sukkot)"),
                value: _rules.betweenYomKippurAndSukkot,
                onChanged: (w) =>
                    _update(_rules.copyWith(betweenYomKippurAndSukkot: w)),
              ),
              const Divider(),
              _sectionTitle(
                  context.l10n.pick(he: "לפני פסח", en: "Before Pesach")),
              _pesachTile(),
              const Divider(),
              _sectionTitle(context.l10n.pick(he: "מקום", en: "Location")),
              SwitchListTile(
                secondary:
                    Icon(Icons.public, color: SoferTokens.of(context).accent),
                title:
                    Text(context.l10n.pick(he: "בארץ ישראל", en: "In Israel")),
                subtitle: Text(_rules.inIsrael
                    ? context.l10n.pick(
                        he: "יום טוב אחד — חול המועד מתחיל יום מוקדם יותר",
                        en:
                            "One day of Yom Tov; Chol HaMoed starts one day earlier")
                    : context.l10n.pick(
                        he: "חוץ לארץ — יומיים יום טוב בכל חג",
                        en: "Outside Israel; two days of Yom Tov for each festival")),
                value: _rules.inIsrael,
                onChanged: (v) => _update(_rules.copyWith(inIsrael: v)),
              ),
              const Divider(),
              _sectionTitle(
                  context.l10n.pick(he: "החודש הקרוב", en: "Next 30 days")),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  context.l10n.pick(
                      he: "תצוגה מקדימה של הימים שידולגו, כדי לראות מיד שההגדרות נותנות את התוצאה שהתכוונת אליה.",
                      en: "Preview the days that will be skipped so you can immediately verify the effect of these settings."),
                  style: TextStyle(
                      fontSize: 12, color: SoferTokens.of(context).inkMuted),
                ),
              ),
              ..._preview(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() {
    final t = SoferTokens.of(context);
    final text = Text(
      context.l10n.pick(
          he: "כל צפי סיום בתוכנה מדלג על הימים שאינם ימי עבודה כאן.",
          en: "Every estimated completion date in the app skips the non-workdays defined here."),
      style: TextStyle(
          fontFamily: t.labelFamily,
          fontSize: 14,
          height: 1.7,
          color: t.inkMuted),
    );

    if (t.isCards) {
      return Card(
        margin: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(padding: const EdgeInsets.all(14), child: text),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: text,
    );
  }

  /// The days that are never writing days, stated so the list is not a mystery,
  /// but without switches — they override every other setting.
  Widget _fixedDaysCard() {
    final t = SoferTokens.of(context);
    // In the ruled themes this is a stated block on the page, bounded by the
    // heavier rule, rather than a raised card floating on it.
    if (t.isRules) {
      return Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: t.ruleStrong),
            bottom: BorderSide(color: t.ruleStrong),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                context.l10n.pick(
                    he: "אינם ימי עבודה — קבוע", en: "Always non-workdays"),
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    letterSpacing: 1.5,
                    color: t.inkMuted)),
            const SizedBox(height: 7),
            Text(
              context.l10n.pick(
                  he: "שבת · יום טוב · חול המועד · ערבי חג · פורים ושושן פורים · תשעה באב וערב תשעה באב",
                  en: "Shabbat · Yom Tov · Chol HaMoed · Erev Yom Tov · Purim and Shushan Purim · Tisha B’Av and Erev Tisha B’Av"),
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 17,
                  height: 1.7,
                  color: t.ink),
            ),
            const SizedBox(height: 6),
            Text(
                context.l10n.pick(
                    he: "גובר על כל הגדרה אחרת — שבת של חנוכה היא שבת.",
                    en:
                        "These override every other setting; Shabbat during Chanukah remains Shabbat."),
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    color: t.inkFaint)),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline,
                    color: SoferTokens.of(context).inkMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      context.l10n.pick(
                          he: "אינם ימי עבודה — קבוע",
                          en: "Always non-workdays"),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.pick(
                  he: "שבת · יום טוב · חול המועד · ערבי חג · פורים ושושן פורים · תשעה באב וערב תשעה באב",
                  en: "Shabbat · Yom Tov · Chol HaMoed · Erev Yom Tov · Purim and Shushan Purim · Tisha B’Av and Erev Tisha B’Av"),
              style: const TextStyle(height: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.pick(
                  he: "גובר על כל הגדרה אחרת — שבת של חנוכה היא שבת.",
                  en: "These override every other setting; Shabbat during Chanukah remains Shabbat."),
              style: TextStyle(
                  fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pesachTile() {
    final window = _rules.pesachWindow;
    final range = window == null
        ? context.l10n.pick(he: "לא נכלל", en: "Not included")
        : context.l10n.pick(
            he: "${formatHebrewNumber(window.from)}–${formatHebrewNumber(window.to)} ניסן",
            en: "${window.from}–${window.to} Nisan");

    return Column(
      children: [
        _weightTile(
          icon: Icons.cleaning_services,
          title: context.l10n
              .pick(he: "הימים שלפני פסח", en: "Days before Pesach"),
          subtitle: range,
          value: _rules.beforePesach,
          onChanged: (w) => _update(_rules.copyWith(beforePesach: w)),
        ),
        ListTile(
          leading: Icon(Icons.tag, color: SoferTokens.of(context).accent),
          title: Text(context.l10n.pick(
              he: "כמה ימים לפני פסח", en: "Number of days before Pesach")),
          subtitle: Text(context.l10n.pick(
              he: "${_rules.daysBeforePesach} ימים",
              en: "${_rules.daysBeforePesach} days")),
          trailing: SizedBox(
            width: 96,
            child: DropdownButton<int>(
              value: _rules.daysBeforePesach.clamp(0, 14),
              isExpanded: true,
              items: List.generate(
                15,
                (i) => DropdownMenuItem(value: i, child: Text("$i")),
              ),
              onChanged: (v) => v == null
                  ? null
                  : _update(_rules.copyWith(daysBeforePesach: v)),
            ),
          ),
        ),
      ],
    );
  }

  /// A live sample of the next month, so the effect of a choice is visible
  /// immediately instead of only surfacing inside a delivery date weeks later.
  List<Widget> _preview() {
    final today = DateTime.now();
    final upcoming = HebrewWorkCalendar.daysOff(
      today,
      CalendarDays.addDays(today, 30),
      _rules,
    );

    if (upcoming.isEmpty) {
      return [
        ListTile(
            dense: true,
            title: Text(context.l10n.pick(
                he: "אין ימי הפסקה בחודש הקרוב",
                en: "No non-workdays in the next 30 days"))),
      ];
    }

    return upcoming.map((entry) {
      final half = entry.day.value > 0;
      return ListTile(
        dense: true,
        leading: Icon(
          half ? Icons.contrast : Icons.circle,
          size: half ? 14 : 8,
          color: half
              ? SoferTokens.of(context).caution
              : SoferTokens.of(context).inkFaint,
        ),
        title: Text(formatDisplayDate(entry.date, _useGregorianDates,
            english: context.l10n.isEnglish)),
        subtitle: _rules.exceptionOn(entry.date)?.note.isNotEmpty == true
            ? Text(_rules.exceptionOn(entry.date)!.note)
            : null,
        trailing: Text(
          half
              ? "${context.l10n.nonWorkReason(entry.day.reason?.label ?? '')} · ${context.l10n.pick(he: 'חצי יום', en: 'Half day')}"
              : context.l10n.nonWorkReason(entry.day.reason?.label ?? ''),
          style: TextStyle(color: SoferTokens.of(context).inkMuted),
        ),
      );
    }).toList();
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  /// One category with its three states.
  ///
  /// The control sits below the title rather than beside it, so the three
  /// labels stay readable on a narrow phone without truncating.
  Widget _weightTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required DayWeight value,
    required ValueChanged<DayWeight> onChanged,
    bool allowFull = true,
  }) {
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              style: TextStyle(
                  fontSize: 12, color: SoferTokens.of(context).inkMuted),
            ),
          ),
      ],
    );

    final choice = SegmentedButton<DayWeight>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        if (allowFull)
          ButtonSegment(
              value: DayWeight.full,
              label: Text(context.l10n.pick(he: "מלא", en: "Full"))),
        ButtonSegment(
            value: DayWeight.half,
            label: Text(context.l10n.pick(he: "חצי", en: "Half"))),
        ButtonSegment(
            value: DayWeight.none,
            label: Text(context.l10n.pick(he: "לא", en: "Off"))),
      ],
      selected: {
        // A stored `full` on a half-only category would leave the control with
        // nothing selected, which SegmentedButton asserts on.
        allowFull || value != DayWeight.full ? value : DayWeight.none,
      },
      onSelectionChanged: (v) => onChanged(v.first),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: LayoutBuilder(
        builder: (context, box) {
          // The longest label on this screen is "הימים שבין יום כיפור לסוכות".
          // Beside the control on a phone it wraps to three lines; below it, it
          // reads on one or two. So on a narrow screen it goes below.
          if (box.maxWidth < 380) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: SoferTokens.of(context).accent),
                    const SizedBox(width: 14),
                    Expanded(child: label),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: choice,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: SoferTokens.of(context).accent),
              const SizedBox(width: 14),
              Expanded(child: label),
              const SizedBox(width: 8),
              choice,
            ],
          );
        },
      ),
    );
  }
}
