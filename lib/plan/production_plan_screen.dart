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

  /// Told when a day is overruled, so the change reaches the rest of the app
  /// rather than living only on this screen.
  final void Function(Project updated)? onProjectUpdated;

  const ProductionPlanScreen({
    super.key,
    required this.projects,
    required this.history,
    this.initialProject,
    this.onProjectUpdated,
  });

  @override
  State<ProductionPlanScreen> createState() => _ProductionPlanScreenState();
}

class _ProductionPlanScreenState extends State<ProductionPlanScreen> {
  final StorageService _storage = StorageService();

  Project? _project;
  DateTime _anchor = DateTime.now();

  /// A week or a month. The same engine answers both — they are one question
  /// over a different number of days — and a writer planning a weekend wants
  /// the short view without the other three weeks around it.
  bool _weekly = false;
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

  /// A week or a Hebrew month back or forward.
  ///
  /// A month is walked through the Hebrew calendar rather than by adding thirty
  /// days, which drifts; a week is exactly seven days and needs no such care.
  void _shift(int by) {
    if (_weekly) {
      setState(() => _anchor = _anchor.add(Duration(days: 7 * by)));
      return;
    }
    final jd = JewishDate.fromDateTime(_anchor);
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
    setState(() => _anchor = JewishDate.initDate(
          jewishYear: year,
          jewishMonth: month,
          jewishDayOfMonth: 1,
        ).getGregorianCalendar());
  }

  /// What the stretch is called at the top of the screen.
  String _periodLabel(ProductionPlan plan) {
    if (!_weekly) return formatDisplayDateMonth(_anchor, false);
    return 'שבוע: ${formatDisplayDate(plan.from, false)} – '
        '${formatDisplayDate(plan.to, false)}';
  }

  /// Lets the writer overrule the calendar for one day.
  ///
  /// The rules know about Shabbat and Chanukah. They do not know that he has a
  /// wedding on Tuesday, or that he has decided to sit down on a fast day
  /// after all — and a plan he cannot correct is a plan he will stop believing.
  ///
  /// Everything after the day moves, because the plan is a cumulative line and
  /// not a fixed one. That is the whole reason it was built that way.
  Future<void> _editDay(Project project, PlannedDay day) async {
    final chosen = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('יום ${formatHebrewNumber(day.hebrewDay)}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'כמה אתה כותב ביום הזה? כל מה שאחריו יזוז בהתאם.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 12),
            for (final option in const [
              (1.0, 'יום מלא'),
              (0.5, 'חצי יום'),
              (0.0, 'לא כותב'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(option.$2),
                trailing: day.weight == option.$1
                    ? Icon(Icons.check, color: SoferTokens.of(ctx).accent)
                    : null,
                onTap: () => Navigator.pop(ctx, option.$1),
              ),
            if (day.isOverridden)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('חזור ללוח'),
                  onPressed: () => Navigator.pop(ctx, -1.0),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final key = Project.planDay(day.date);
    final next = Map<DateTime, double>.from(project.planOverrides);
    // -1 is "forget my decision", which is not the same as "do not write":
    // one hands the day back to the calendar, the other overrules it with zero.
    chosen < 0 ? next.remove(key) : next[key] = chosen;

    final updated = project.copyWith(planOverrides: next);
    await _storage.saveProjects([updated]);
    if (!mounted) return;
    setState(() => _project = updated);
    widget.onProjectUpdated?.call(updated);
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
                    'עד הסוף: ${_position(project, plan.closingTarget)}.',
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

    return InkWell(
      onTap: () => _editDay(project, day),
      child: Container(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(
            color: day.isOverridden
                ? t.caution
                : (day.isToday ? t.accent : t.rule),
            width: day.isToday || day.isOverridden ? 1.5 : 0.5),
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
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('חודש')),
                            ButtonSegment(value: true, label: Text('שבוע')),
                          ],
                          selected: {_weekly},
                          onSelectionChanged: (v) =>
                              setState(() => _weekly = v.first),
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

                        final plan = _weekly
                            ? ProductionPlan.forWeek(
                                project: project,
                                history: widget.history,
                                anyDayInWeek: _anchor,
                                rules: _rules,
                                dayStart: _dayStart,
                                overrides: project.planOverrides,
                              )
                            : ProductionPlan.forMonth(
                                project: project,
                                history: widget.history,
                                anyDayInMonth: _anchor,
                                rules: _rules,
                                dayStart: _dayStart,
                                overrides: project.planOverrides,
                              );
                        return Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 12, 12, 0),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _shift(-1),
                                    icon: const Icon(Icons.chevron_right),
                                    tooltip:
                                        _weekly ? 'שבוע קודם' : 'חודש קודם',
                                  ),
                                  Expanded(
                                    child: Text(
                                      _periodLabel(plan),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontFamily: t.numeralFamily,
                                          fontSize: 17,
                                          color: t.ink),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _shift(1),
                                    icon: const Icon(Icons.chevron_left),
                                    tooltip: _weekly ? 'שבוע הבא' : 'חודש הבא',
                                  ),
                                ],
                              ),
                            ),
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
