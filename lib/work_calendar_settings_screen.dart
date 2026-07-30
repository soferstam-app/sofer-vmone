import 'package:flutter/material.dart';

import 'hebrew_utils.dart';
import 'logic/hebrew_work_calendar.dart';
import 'storage_service.dart';

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

    return Scaffold(
      appBar: AppBar(title: const Text("ימי עבודה"), centerTitle: true),
      // The same content in both layouts — a phone scrolls one column, a desktop
      // window gets a readable measure instead of stretched-out rows.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            children: [
              _intro(),
              _fixedDaysCard(),
              _sectionTitle("סוף שבוע"),
              _weightTile(
                icon: Icons.weekend,
                title: "יום שישי",
                value: _rules.friday,
                allowFull: false,
                onChanged: (w) => _update(_rules.copyWith(friday: w)),
              ),
              _weightTile(
                icon: Icons.nightlight_round,
                title: "מוצאי שבת",
                value: _rules.motzeiShabbat,
                allowFull: false,
                onChanged: (w) => _update(_rules.copyWith(motzeiShabbat: w)),
              ),
              const Divider(),
              _sectionTitle("צומות"),
              _weightTile(
                icon: Icons.no_food,
                title: "י״ז בתמוז",
                value: _rules.fastSeventeenTammuz,
                onChanged: (w) =>
                    _update(_rules.copyWith(fastSeventeenTammuz: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title: "צום גדליה",
                value: _rules.fastGedalya,
                onChanged: (w) => _update(_rules.copyWith(fastGedalya: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title: "י׳ בטבת",
                value: _rules.fastTenthTevet,
                onChanged: (w) => _update(_rules.copyWith(fastTenthTevet: w)),
              ),
              _weightTile(
                icon: Icons.no_food,
                title: "תענית אסתר",
                value: _rules.fastEsther,
                onChanged: (w) => _update(_rules.copyWith(fastEsther: w)),
              ),
              const Divider(),
              _sectionTitle("מועדים"),
              _weightTile(
                icon: Icons.local_fire_department,
                title: "חנוכה",
                subtitle: "שמונת הימים",
                value: _rules.chanukah,
                onChanged: (w) => _update(_rules.copyWith(chanukah: w)),
              ),
              _weightTile(
                icon: Icons.local_fire_department_outlined,
                title: "ל״ג בעומר",
                value: _rules.lagBaomer,
                onChanged: (w) => _update(_rules.copyWith(lagBaomer: w)),
              ),
              _weightTile(
                icon: Icons.celebration,
                title: "איסרו חג",
                subtitle: "למחרת פסח, שבועות וסוכות",
                value: _rules.isruChag,
                onChanged: (w) => _update(_rules.copyWith(isruChag: w)),
              ),
              _weightTile(
                icon: Icons.cabin,
                title: "בין יום כיפור לסוכות",
                subtitle: "י״א–י״ג תשרי (י״ד הוא ערב סוכות)",
                value: _rules.betweenYomKippurAndSukkot,
                onChanged: (w) =>
                    _update(_rules.copyWith(betweenYomKippurAndSukkot: w)),
              ),
              const Divider(),
              _sectionTitle("לפני פסח"),
              _pesachTile(),
              const Divider(),
              _sectionTitle("מקום"),
              SwitchListTile(
                secondary: const Icon(Icons.public, color: Colors.deepPurple),
                title: const Text("בארץ ישראל"),
                subtitle: Text(_rules.inIsrael
                    ? "יום טוב אחד — חול המועד מתחיל יום מוקדם יותר"
                    : "חוץ לארץ — יומיים יום טוב בכל חג"),
                value: _rules.inIsrael,
                onChanged: (v) => _update(_rules.copyWith(inIsrael: v)),
              ),
              const Divider(),
              _sectionTitle("החודש הקרוב"),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  "תצוגה מקדימה של הימים שידולגו, כדי לראות מיד שההגדרות נותנות "
                  "את התוצאה שהתכוונת אליה.",
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
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

  Widget _intro() => Card(
        margin: const EdgeInsets.all(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            "כל צפי סיום בתוכנה מדלג על הימים שאינם ימי עבודה כאן.",
            style: TextStyle(height: 1.4),
          ),
        ),
      );

  /// The days that are never writing days, stated so the list is not a mystery,
  /// but without switches — they override every other setting.
  Widget _fixedDaysCard() => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  const Text("אינם ימי עבודה — קבוע",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "שבת · יום טוב · חול המועד · ערבי חג · פורים ושושן פורים · "
                "תשעה באב וערבו",
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                "גובר על כל הגדרה אחרת — שבת של חנוכה היא שבת.",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );

  Widget _pesachTile() {
    final window = _rules.pesachWindow;
    final range = window == null
        ? "לא נכלל"
        : "${formatHebrewNumber(window.from)}–${formatHebrewNumber(window.to)} ניסן";

    return Column(
      children: [
        _weightTile(
          icon: Icons.cleaning_services,
          title: "הימים שלפני פסח",
          subtitle: range,
          value: _rules.beforePesach,
          onChanged: (w) => _update(_rules.copyWith(beforePesach: w)),
        ),
        ListTile(
          leading: const Icon(Icons.tag, color: Colors.deepPurple),
          title: const Text("כמה ימים לפני פסח"),
          subtitle: Text("${_rules.daysBeforePesach} ימים"),
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
      today.add(const Duration(days: 30)),
      _rules,
    );

    if (upcoming.isEmpty) {
      return const [
        ListTile(dense: true, title: Text("אין ימי הפסקה בחודש הקרוב")),
      ];
    }

    return upcoming.map((entry) {
      final half = entry.day.value > 0;
      return ListTile(
        dense: true,
        leading: Icon(
          half ? Icons.contrast : Icons.circle,
          size: half ? 14 : 8,
          color: half ? Colors.orange.shade600 : Colors.grey.shade500,
        ),
        title: Text(formatDisplayDate(entry.date, _useGregorianDates)),
        trailing: Text(
          half
              ? "${entry.day.reason?.label ?? ''} · חצי יום"
              : entry.day.reason?.label ?? '',
          style: TextStyle(color: Colors.grey.shade600),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.deepPurple),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SegmentedButton<DayWeight>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: [
              if (allowFull)
                const ButtonSegment(value: DayWeight.full, label: Text("מלא")),
              const ButtonSegment(value: DayWeight.half, label: Text("חצי")),
              const ButtonSegment(value: DayWeight.none, label: Text("לא")),
            ],
            selected: {
              // A stored `full` on a half-only category would leave the control
              // with nothing selected, which SegmentedButton asserts on.
              allowFull || value != DayWeight.full ? value : DayWeight.none,
            },
            onSelectionChanged: (v) => onChanged(v.first),
          ),
        ],
      ),
    );
  }
}
