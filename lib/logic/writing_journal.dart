import 'package:kosher_dart/kosher_dart.dart';

import '../hebrew_utils.dart';
import '../models.dart';
import 'calendar_days.dart';
import 'date_logic.dart';
import 'export_table.dart';
import 'hebrew_clock.dart';
import 'recording.dart';
import 'production_calculator.dart';

enum JournalDateDisplay { hebrew, gregorian, both }

/// The writer's chosen shape for the weekly writing journal.
///
/// Kept as one portable setting: adding or removing a column must not require a
/// storage migration, and the same printed form should follow the writer from
/// Android to Windows with the rest of the settings.
class WritingJournalSettings {
  static const defaults = WritingJournalSettings();

  final bool useAsHome;
  final JournalDateDisplay dateDisplay;
  final bool inIsrael;
  final bool showProject;
  final bool showTime;
  final bool showNotes;
  final bool showParsha;
  final int blankRowsPerDay;

  const WritingJournalSettings({
    this.useAsHome = false,
    this.dateDisplay = JournalDateDisplay.both,
    this.inIsrael = true,
    this.showProject = true,
    this.showTime = true,
    this.showNotes = true,
    this.showParsha = true,
    this.blankRowsPerDay = 2,
  });

  WritingJournalSettings copyWith({
    bool? useAsHome,
    JournalDateDisplay? dateDisplay,
    bool? inIsrael,
    bool? showProject,
    bool? showTime,
    bool? showNotes,
    bool? showParsha,
    int? blankRowsPerDay,
  }) =>
      WritingJournalSettings(
        useAsHome: useAsHome ?? this.useAsHome,
        dateDisplay: dateDisplay ?? this.dateDisplay,
        inIsrael: inIsrael ?? this.inIsrael,
        showProject: showProject ?? this.showProject,
        showTime: showTime ?? this.showTime,
        showNotes: showNotes ?? this.showNotes,
        showParsha: showParsha ?? this.showParsha,
        blankRowsPerDay: (blankRowsPerDay ?? this.blankRowsPerDay).clamp(1, 6),
      );

  Map<String, dynamic> toJson() => {
        'useAsHome': useAsHome,
        'dateDisplay': dateDisplay.name,
        'inIsrael': inIsrael,
        'showProject': showProject,
        'showTime': showTime,
        'showNotes': showNotes,
        'showParsha': showParsha,
        'blankRowsPerDay': blankRowsPerDay,
      };

  factory WritingJournalSettings.fromJson(Map<String, dynamic> json) {
    final storedDisplay = json['dateDisplay'];
    final dateDisplay = JournalDateDisplay.values.firstWhere(
      (value) => value.name == storedDisplay,
      orElse: () => JournalDateDisplay.both,
    );
    final rows = switch (json['blankRowsPerDay']) {
      final num value => value.toInt().clamp(1, 6),
      _ => 2,
    };
    return WritingJournalSettings(
      useAsHome: json['useAsHome'] == true,
      dateDisplay: dateDisplay,
      inIsrael: json['inIsrael'] != false,
      showProject: json['showProject'] != false,
      showTime: json['showTime'] != false,
      showNotes: json['showNotes'] != false,
      showParsha: json['showParsha'] != false,
      blankRowsPerDay: rows,
    );
  }
}

/// One entry within one working day. Breaks between slices are not writing time.
class JournalEntry {
  final List<WorkSession> sessions;
  const JournalEntry(this.sessions);
  String get projectId => sessions.first.projectId;
  String get key => '$projectId:${sessions.first.entryId ?? sessions.first.id}';
  bool get timeRecorded => sessions.any((s) => s.timeRecorded);
  Duration get duration => sessions.fold(
      Duration.zero,
      (sum, s) =>
          sum +
          (s.timeRecorded && !s.duration.isNegative
              ? s.duration
              : Duration.zero));
  String get notes => sessions
      .map((s) => s.extraFields['entryNotes'])
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet()
      .join(' · ');
  String get description =>
      sessions.map((s) => s.description).toSet().join(' · ');
  String descriptionFor(Project? project, {required bool english}) {
    if (project == null ||
        !project.type.isPaged ||
        sessions.length < 2 ||
        sessions.any((s) => s.isPartialLine || s.isInvalid)) {
      return description;
    }
    final sorted = [...sessions]..sort((a, b) {
        final page = a.amount.compareTo(b.amount);
        return page != 0 ? page : a.startLine.compareTo(b.startLine);
      });
    for (var i = 1; i < sorted.length; i++) {
      final before = sorted[i - 1];
      final after = sorted[i];
      final adjacent = before.amount == after.amount
          ? after.startLine == before.endLine + 1
          : after.amount == before.amount + 1 &&
              after.startLine == 1 &&
              before.endLine ==
                  (before.linesPerPageAtEntry ??
                      ProductionCalculator.linesPerPageOf(project));
      if (!adjacent) return description;
    }
    final first = sorted.first;
    final last = sorted.last;
    return english
        ? 'Page ${first.amount}, line ${first.startLine} – page ${last.amount}, line ${last.endLine}'
        : 'עמוד ${formatHebrewNumber(first.amount)} שורה ${first.startLine} – עמוד ${formatHebrewNumber(last.amount)} שורה ${last.endLine}';
  }

  String durationLabel({required bool english}) =>
      WritingJournalLogic.durationText(duration,
          recorded: timeRecorded, english: english);
}

class WritingJournalLogic {
  const WritingJournalLogic._();

  static DateTime weekStart(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    // DateTime uses Monday=1…Sunday=7. The journal uses Sunday as its first
    // column, matching the printed forms used by the writers.
    return CalendarDays.addDays(date, -(date.weekday % 7));
  }

  static List<DateTime> weekDays(DateTime day) {
    final first = weekStart(day);
    return [for (var i = 0; i < 7; i++) CalendarDays.addDays(first, i)];
  }

  static String weeklyParsha(DateTime day,
      {required bool inIsrael, required bool english}) {
    final calendar = JewishCalendar.fromDateTime(day)..inIsrael = inIsrael;
    final formatter = HebrewDateFormatter()..hebrewFormat = !english;
    return formatter.formatWeeklyParsha(calendar);
  }

  static List<WorkSession> sessionsOnDay(
    Iterable<WorkSession> history,
    DateTime day,
    DayStart dayStart,
  ) =>
      history
          .where((session) =>
              !session.isDeleted &&
              DateLogic.sessionIsOnDay(session, day, dayStart))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  static List<JournalEntry> entriesOnDay(
      Iterable<WorkSession> history, DateTime day, DayStart dayStart) {
    final byProject = <String, List<WorkSession>>{};
    for (final session in sessionsOnDay(history, day, dayStart)) {
      byProject.putIfAbsent(session.projectId, () => []).add(session);
    }
    return [
      for (final sessions in byProject.values)
        for (final recording in Recording.gather(sessions))
          JournalEntry(recording.sessions)
    ]..sort((a, b) =>
        a.sessions.first.startTime.compareTo(b.sessions.first.startTime));
  }

  static String dateLabel(
    DateTime day,
    JournalDateDisplay display, {
    required bool english,
  }) {
    final hebrew = formatDisplayDate(day, false, english: english);
    final gregorian = formatDisplayDate(day, true, english: english);
    return switch (display) {
      JournalDateDisplay.hebrew => hebrew,
      JournalDateDisplay.gregorian => gregorian,
      JournalDateDisplay.both => '$hebrew · $gregorian',
    };
  }

  static String durationLabel(WorkSession session, {required bool english}) {
    return durationText(session.duration,
        recorded: session.timeRecorded, english: english);
  }

  static String durationText(Duration value,
      {required bool recorded, required bool english}) {
    if (!recorded) return english ? 'Not recorded' : 'לא נרשם';
    final duration = value.isNegative ? Duration.zero : value;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return english ? '$minutes min' : '$minutes דק׳';
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  /// Builds both a filled export and a paper form from the same week and
  /// column settings as the screen. [blank] changes only the rows, never the
  /// headings, so copying the paper back into the app is mechanical.
  static ExportTable exportWeek({
    required DateTime anyDayInWeek,
    required List<Project> projects,
    required List<WorkSession> history,
    required DayStart dayStart,
    required WritingJournalSettings settings,
    required bool english,
    required bool blank,
  }) {
    final days = weekDays(anyDayInWeek);
    final byId = {for (final project in projects) project.id: project};
    final parsha =
        weeklyParsha(days.last, inIsrael: settings.inIsrael, english: english);
    final headings = <String>[
      english ? 'Day' : 'יום',
      english ? 'Date' : 'תאריך',
      if (settings.showProject) english ? 'Project' : 'פרויקט',
      english ? 'Written' : 'מה נכתב',
      if (settings.showTime) english ? 'Writing time' : 'זמן כתיבה',
      if (settings.showNotes) english ? 'Notes' : 'הערות',
    ];
    const heDays = ['ראשון', 'שני', 'שלישי', 'רביעי', 'חמישי', 'שישי', 'שבת'];
    const enDays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Shabbat'
    ];
    final rows = <ExportRow>[];

    for (var dayIndex = 0; dayIndex < days.length; dayIndex++) {
      final day = days[dayIndex];
      final daySessions =
          blank ? const <JournalEntry>[] : entriesOnDay(history, day, dayStart);
      final rowCount = blank
          ? settings.blankRowsPerDay
          : (daySessions.isEmpty ? 1 : daySessions.length);
      for (var rowIndex = 0; rowIndex < rowCount; rowIndex++) {
        final session =
            rowIndex < daySessions.length ? daySessions[rowIndex] : null;
        rows.add(ExportRow([
          rowIndex == 0 ? (english ? enDays[dayIndex] : heDays[dayIndex]) : '',
          rowIndex == 0
              ? dateLabel(day, settings.dateDisplay, english: english)
              : '',
          if (settings.showProject)
            session == null ? '' : (byId[session.projectId]?.name ?? ''),
          session?.descriptionFor(byId[session.projectId], english: english) ??
              '',
          if (settings.showTime)
            session == null ? '' : session.durationLabel(english: english),
          if (settings.showNotes) session?.notes ?? '',
        ], muted: !blank && daySessions.isEmpty));
      }
    }

    final from = dateLabel(days.first, settings.dateDisplay, english: english);
    final to = dateLabel(days.last, settings.dateDisplay, english: english);
    final parshaText = settings.showParsha && parsha.isNotEmpty
        ? (english ? ' · Parashat $parsha' : ' · פרשת $parsha')
        : '';
    return ExportTable(
      title: english ? 'Writing Journal' : 'יומן כתיבה',
      summary: '$from – $to$parshaText',
      headings: headings,
      rows: rows,
      rtl: !english,
      note: blank
          ? (english
              ? 'Fill this sheet during the week, then copy each row into the Writing Journal.'
              : 'ממלאים במהלך השבוע, ולאחר מכן מעתיקים כל שורה ליומן הכתיבה.')
          : null,
    );
  }
}
