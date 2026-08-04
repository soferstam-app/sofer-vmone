import 'package:flutter/material.dart';
import 'package:kosher_dart/kosher_dart.dart';

import '../hebrew_utils.dart';
import '../logic/hebrew_clock.dart';
import '../logic/hebrew_work_calendar.dart';
import '../logic/production_plan.dart';
import '../models.dart';
import '../storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

/// The month as a calendar, saying which page each day asks for.
///
/// Asked for by a sofer: *someone who sets himself a page a day and is holding
/// at page ten should see, on a calendar, which page he is meant to be writing
/// on each day of the month.* And: *on Fridays and Motzei Shabbat I make up
/// what I missed, so it should say what I have to catch up to by the weekend.*
///
/// Every square carries a **position**, not an amount. "Two pages today" has to
/// be added up in the writer's head, on exactly the day he is already behind;
/// "be at page fourteen" is the answer to both questions at once, and the
/// catching up is the gap between it and where he is.
class ProductionPlanScreen extends StatefulWidget {
  final List<Project> projects;
  final List<WorkSession> history;
  final Project? initialProject;

  const ProductionPlanScreen({
    super.key,
    required this.projects,
    required this.history,
    this.initialProject,
  });

  @override
  State<ProductionPlanScreen> createState() => _ProductionPlanScreenState();
}

class _ProductionPlanScreenState extends State<ProductionPlanScreen> {
  final StorageService _storage = StorageService();

  Project? _project;
  DateTime _month = DateTime.now();
  WorkCalendarRules _rules = WorkCalendarRules.standard;
  DayStart _dayStart = DayStart.midnight;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject ??
        (widget.projects.isEmpty ? null : widget.projects.first);
    _load();
  }

  Future<void> _load() async {
    final rules = await _storage.getWorkCalendarRules();
    final dayStart = await _storage.getDayStart();
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _dayStart = dayStart;
      _loaded = true;
    });
  }

  /// One Hebrew month back or forward. Walked through the Hebrew calendar
  /// rather than by adding thirty days, which drifts.
  void _shiftMonth(int by) {
    final jd = JewishDate.fromDateTime(_month);
    var year = jd.getJewishYear();
    var month = jd.getJewishMonth();
    final monthsInYear = jd.isJewishLeapYear() ? 13 : 12;

    // Months are numbered from Nisan, so the year turns over between Adar and
    // Nisan rather than at the top of the count.
    for (var i = 0; i < by.abs(); i++) {
      if (by > 0) {
        month++;
        if (month > monthsInYear) {
          month = 1;
          year++;
        }
      } else {
        month--;
        if (month < 1) {
          month = monthsInYear;
          year--;
        }
      }
    }
    setState(() => _month = JewishDate.initDate(
          jewishYear: year,
          jewishMonth: month,
          jewishDayOfMonth: 1,
        ).getGregorianCalendar());
  }

  /// A position as a sofer says it — "עמוד יד", "מזוזה 3".
  String _position(Project project, double units) {
    // Rounded up: reaching a target means finishing the unit it lands in, and
    // "be at page 13.4" is not an instruction anyone can follow.
    final n = units <= 0 ? 0 : units.ceil();
    if (n <= 0) return '—';
    return switch (project.type) {
      ProjectType.sefer => 'עמוד ${formatHebrewNumber(n)}',
      ProjectType.mezuza => 'מזוזה $n',
      ProjectType.tefillin => 'סט $n',
    };
  }

  Widget _summary(BuildContext context, ProductionPlan plan, Project project) {
    final t = SoferTokens.of(context);
    final behind = plan.behindBy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            behind == null
                ? 'אתה בקצב. עד סוף החודש: ${_position(project, plan.closingTarget)}.'
                : 'אתה מפגר ב-${behind.ceil()} '
                    '${project.type == ProjectType.sefer ? "עמודים" : "יחידות"}. '
                    'עד סוף החודש: ${_position(project, plan.closingTarget)}.',
            style: TextStyle(
              fontFamily: t.labelFamily,
              fontSize: 15,
              height: 1.7,
              color: behind == null ? t.inkMuted : t.danger,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'כל יום מראה לאן צריך להגיע עד סופו. הפיגור מתחלק על הימים שנותרו, '
            'לכן יום שכבר עבר שומר על היעד שנמדד מולו.',
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

  /// One square of the calendar.
  Widget _cell(BuildContext context, PlannedDay day, Project project) {
    final t = SoferTokens.of(context);

    final Color background;
    if (day.isToday) {
      background = t.accent.withValues(alpha: 0.14);
    } else if (!day.isWorkingDay) {
      background = t.rule.withValues(alpha: 0.25);
    } else if (day.isBehind) {
      background = t.danger.withValues(alpha: 0.10);
    } else {
      background = Colors.transparent;
    }

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
            color: day.isToday ? t.accent : t.rule,
            width: day.isToday ? 1.5 : 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatHebrewNumber(day.hebrewDay),
            style: TextStyle(
                fontFamily: t.numeralFamily,
                fontSize: 12,
                color: day.isWorkingDay ? t.ink : t.inkFaint),
          ),
          const SizedBox(height: 2),
          if (!day.isWorkingDay)
            Text(
              day.closedReason?.label ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: t.labelFamily, fontSize: 9, color: t.inkFaint),
            )
          else ...[
            // The target for the day: the adjusted one where it still matters,
            // the original where the day has already been judged.
            Text(
              _position(project,
                  day.isFuture || day.isToday ? day.adjustedTarget : day.plannedTarget),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: t.numeralFamily,
                  fontSize: 11,
                  color: day.isBehind ? t.danger : t.ink),
            ),
            if (day.isHalfDay)
              Text('חצי יום',
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 8,
                      color: t.inkFaint)),
            if (day.actual != null && !day.isFuture)
              Text(
                'בפועל ${_position(project, day.actual!)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 9,
                    color: day.isBehind ? t.danger : t.inkMuted),
              ),
          ],
        ],
      ),
    );
  }

  /// The month as weeks, Sunday first, with the leading blanks a calendar needs.
  Widget _grid(BuildContext context, ProductionPlan plan, Project project) {
    final t = SoferTokens.of(context);
    const names = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];

    // weekday: Monday is 1 in Dart, and the Hebrew week starts on Sunday.
    int column(DateTime d) => d.weekday % 7;
    final lead = plan.days.isEmpty ? 0 : column(plan.days.first.date);

    return Column(
      children: [
        Row(
          children: [
            for (final n in names)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(n,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: t.labelFamily,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: t.inkMuted)),
                ),
              ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // Tall enough for a date, a target and what was actually reached.
          childAspectRatio: 0.72,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox.shrink(),
            for (final day in plan.days) _cell(context, day, project),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final project = _project;

    return Scaffold(
      appBar: AppBar(title: const Text('לוח חודשי')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : project == null
              ? const Center(child: Text('אין פרויקטים לתכנן'))
              : SoferPage(
                  maxWidth: 760,
                  child: ListView(
                    children: [
                      if (widget.projects.length > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: DropdownButtonFormField<Project>(
                            initialValue: project,
                            decoration: const InputDecoration(
                              labelText: 'פרויקט',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: widget.projects
                                .map((p) => DropdownMenuItem(
                                    value: p, child: Text(p.name)))
                                .toList(),
                            onChanged: (p) => setState(() => _project = p),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => _shiftMonth(-1),
                              icon: const Icon(Icons.chevron_right),
                              tooltip: 'חודש קודם',
                            ),
                            Expanded(
                              child: Text(
                                formatDisplayDateMonth(_month, false),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontFamily: t.numeralFamily,
                                    fontSize: 19,
                                    color: t.ink),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _shiftMonth(1),
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'חודש הבא',
                            ),
                          ],
                        ),
                      ),
                      Builder(builder: (context) {
                        if (project.targetDaily <= 0) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                            child: Text(
                              'לפרויקט הזה אין יעד יומי, ולכן אין מה לתכנן. '
                              'אפשר להגדיר אותו במסך הפרויקטים.',
                              style: TextStyle(
                                  fontFamily: t.labelFamily,
                                  fontSize: 14,
                                  height: 1.7,
                                  color: t.inkMuted),
                            ),
                          );
                        }

                        final plan = ProductionPlan.forMonth(
                          project: project,
                          history: widget.history,
                          anyDayInMonth: _month,
                          rules: _rules,
                          dayStart: _dayStart,
                        );
                        return Column(
                          children: [
                            _summary(context, plan, project),
                            const SoferRule(),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 24),
                              child: _grid(context, plan, project),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
    );
  }
}
