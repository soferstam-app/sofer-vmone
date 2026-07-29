import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/hebrew_work_calendar.dart';
import 'storage_service.dart';

/// Which days the writer actually sits down to write.
///
/// Every completion estimate in the app is built from these answers, so they
/// are worth getting right once. The defaults follow the common practice, but
/// nothing here is universal — some soferim write on Chanukah, some do not.
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
    setState(() => _rules = next);
    await _storage.setWorkCalendarRules(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // A live sample: the next fortnight, so the effect of a switch is visible
    // immediately instead of only showing up inside a delivery date weeks
    // later.
    final today = DateTime.now();
    final upcoming = HebrewWorkCalendar.daysOff(
      today,
      today.add(const Duration(days: 30)),
      _rules,
    );

    return Scaffold(
      appBar: AppBar(title: const Text("ימי עבודה"), centerTitle: true),
      body: ListView(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                "כל צפי סיום בתוכנה מדלג על הימים שמסומנים כאן כימים שאינם ימי "
                "עבודה. החישוב נעשה תמיד לפי הלוח העברי — שבת, חגים, חול המועד "
                "וצומות אינם נופלים בתאריך לועזי קבוע.",
                style: TextStyle(height: 1.4),
              ),
            ),
          ),
          _sectionTitle("קבוע"),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text("שבת, יום טוב ותשעה באב"),
            subtitle: Text("תמיד אינם ימי עבודה"),
            dense: true,
          ),
          const Divider(),
          _sectionTitle("סוף שבוע"),
          ListTile(
            leading: const Icon(Icons.weekend, color: Colors.deepPurple),
            title: const Text("יום שישי"),
            subtitle: Text("כרגע: ${_rules.friday.label}"),
            trailing: SegmentedButton<FridayWork>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: FridayWork.none, label: Text("לא")),
                ButtonSegment(value: FridayWork.half, label: Text("חצי")),
                ButtonSegment(value: FridayWork.full, label: Text("מלא")),
              ],
              selected: {_rules.friday},
              onSelectionChanged: (v) =>
                  _update(_rules.copyWith(friday: v.first)),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.nightlight_round,
                color: Colors.deepPurple),
            title: const Text("מוצאי שבת כחצי יום"),
            subtitle: const Text("כתיבה במוצ״ש נספרת כחצי יום עבודה"),
            value: _rules.motzeiShabbatHalfDay,
            onChanged: (v) =>
                _update(_rules.copyWith(motzeiShabbatHalfDay: v)),
          ),
          const Divider(),
          _sectionTitle("מועדים"),
          SwitchListTile(
            secondary: const Icon(Icons.public, color: Colors.deepPurple),
            title: const Text("בארץ ישראל"),
            subtitle: Text(_rules.inIsrael
                ? "יום טוב אחד — חול המועד מתחיל יום מוקדם יותר"
                : "חוץ לארץ — יומיים יום טוב בכל חג"),
            value: _rules.inIsrael,
            onChanged: (v) => _update(_rules.copyWith(inIsrael: v)),
          ),
          _skipTile(
            icon: Icons.holiday_village,
            title: "חול המועד",
            subtitle: "פסח וסוכות, כולל הושענא רבה",
            value: _rules.skipCholHamoed,
            onChanged: (v) => _update(_rules.copyWith(skipCholHamoed: v)),
          ),
          _skipTile(
            icon: Icons.hourglass_bottom,
            title: "ערבי חג",
            subtitle: "ערב פסח, שבועות, ראש השנה, יום כיפור וסוכות",
            value: _rules.skipErevYomTov,
            onChanged: (v) => _update(_rules.copyWith(skipErevYomTov: v)),
          ),
          _skipTile(
            icon: Icons.no_food,
            title: "צומות",
            subtitle: "י״ז בתמוז, צום גדליה, י׳ בטבת ותענית אסתר",
            value: _rules.skipFasts,
            onChanged: (v) => _update(_rules.copyWith(skipFasts: v)),
          ),
          _skipTile(
            icon: Icons.event_busy,
            title: "ערב תשעה באב",
            subtitle: "היום שלפני הצום, גם כשהצום נדחה",
            value: _rules.skipErevTishaBeav,
            onChanged: (v) => _update(_rules.copyWith(skipErevTishaBeav: v)),
          ),
          _skipTile(
            icon: Icons.cabin,
            title: "בין יום כיפור לסוכות",
            subtitle: "י״א–י״ד תשרי",
            value: _rules.skipBetweenYomKippurAndSukkot,
            onChanged: (v) =>
                _update(_rules.copyWith(skipBetweenYomKippurAndSukkot: v)),
          ),
          _skipTile(
            icon: Icons.cleaning_services,
            title: "השבוע שלפני פסח",
            subtitle: "ח׳–י״ד ניסן",
            value: _rules.skipWeekBeforePesach,
            onChanged: (v) => _update(_rules.copyWith(skipWeekBeforePesach: v)),
          ),
          _skipTile(
            icon: Icons.theater_comedy,
            title: "פורים ושושן פורים",
            value: _rules.skipPurim,
            onChanged: (v) => _update(_rules.copyWith(skipPurim: v)),
          ),
          _skipTile(
            icon: Icons.local_fire_department,
            title: "חנוכה",
            subtitle: "שמונת הימים",
            value: _rules.skipChanukah,
            onChanged: (v) => _update(_rules.copyWith(skipChanukah: v)),
          ),
          _skipTile(
            icon: Icons.star_outline,
            title: "ימים מיוחדים",
            subtitle: "ט״ו בשבט, ל״ג בעומר, פסח שני, ט״ו באב ואיסרו חג",
            value: _rules.skipMinorHolidays,
            onChanged: (v) => _update(_rules.copyWith(skipMinorHolidays: v)),
          ),
          _skipTile(
            icon: Icons.brightness_3,
            title: "ראש חודש",
            value: _rules.skipRoshChodesh,
            onChanged: (v) => _update(_rules.copyWith(skipRoshChodesh: v)),
          ),
          const Divider(),
          _sectionTitle("החודש הקרוב"),
          if (upcoming.isEmpty)
            const ListTile(
              dense: true,
              title: Text("אין ימי הפסקה בחודש הקרוב"),
            )
          else
            ...upcoming.map(
              (d) => ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: Text(formatDisplayDate(d.date, _useGregorianDates)),
                trailing: Text(
                  d.reason.label,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

  /// The switch reads as "this is a day off", so it is on when the day is
  /// skipped — the same direction the writer thinks in.
  Widget _skipTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile(
        secondary: Icon(icon, color: Colors.deepPurple),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: onChanged,
      );
}
