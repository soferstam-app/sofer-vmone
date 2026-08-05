import 'logic/currency.dart';
import 'logic/hebrew_clock.dart';
import 'logic/json_compat.dart';
import 'logic/mergeable.dart';

enum ProjectType { sefer, mezuza, tefillin }

class Project implements Mergeable<Project> {
  @override
  final String id;
  final String name;
  final ProjectType type;
  final double price;
  final double expenses;

  /// What [price] and [expenses] are amounts of.
  ///
  /// Stored on the commission rather than read from the setting, so that
  /// changing the setting cannot restate what a job was agreed at. Absent on
  /// anything recorded before this existed, which reads as shekels — the only
  /// thing it could have been.
  final Currency currency;
  final int targetDaily;
  final int targetMonthly;

  /// For sefer: when true, [targetDaily] is in lines; when false, in pages.
  final bool dailyGoalInLines;
  final int? totalPages;
  final int? linesPerPage;

  /// How large the order is, for mezuzot and tefillin — the number of mezuzot
  /// or of full sets. A sefer states its size through [totalPages] instead.
  ///
  /// Null means the size was never entered, and no completion date can be
  /// estimated for the project.
  final int? targetUnits;

  @override
  final DateTime lastUpdated;

  /// When this record was deleted, and when it was restored. Two independent
  /// registers rather than one flag.
  ///
  /// Merging used to resolve a disagreement by whichever device wrote last, so
  /// an edit made on a stale copy beat a deletion made on another device and
  /// the record came back from the dead. Registers merge on their own: each
  /// side takes the later of the two, and a deletion is undone only by a
  /// restore that is genuinely later than it — never by an unrelated edit.
  @override
  final DateTime? deletedAt;
  @override
  final DateTime? restoredAt;

  /// Whether this record counts as deleted.
  bool get isDeleted {
    final deleted = deletedAt;
    if (deleted == null) return false;
    final restored = restoredAt;
    return restored == null || deleted.isAfter(restored);
  }

  final String? clientEmail;
  final DateTime? targetCompletionDate;

  /// Days the writer has decided about himself, against what the calendar says.
  ///
  /// Keyed by the day, valued by how much of it he writes: 0 for a day he is
  /// not working, 0.5 for half, 1 for a full one. The work calendar knows about
  /// Shabbat and Chanukah; it does not know about the wedding on Tuesday, and a
  /// plan he cannot correct is a plan he will stop believing.
  ///
  /// Stored with the commission because it is a fact about *this* job: a writer
  /// may take Tuesday off one sefer and spend it on another.
  final Map<DateTime, double> planOverrides;

  /// Fields written by a newer version of the app, carried through untouched.
  ///
  /// Without this, a phone on a newer build exporting to a PC on an older one
  /// would lose them the next time the PC exported back.
  final Map<String, dynamic> extraFields;

  /// Everything this version writes. Anything else in a stored record goes to
  /// [extraFields].
  static const Set<String> _knownKeys = {
    'id',
    'name',
    'type',
    'typeName',
    'price',
    'expenses',
    'currency',
    'targetDaily',
    'targetMonthly',
    'dailyGoalInLines',
    'totalPages',
    'linesPerPage',
    'targetUnits',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
    'clientEmail',
    'targetCompletionDate',
    'planOverrides',
  };

  /// The size of the job in billable units — pages, mezuzot or sets — however
  /// the project happens to state it. Null when unknown.
  double? get plannedUnits => switch (type) {
        ProjectType.sefer => totalPages?.toDouble(),
        ProjectType.mezuza || ProjectType.tefillin => targetUnits?.toDouble(),
      };

  Project({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    required this.expenses,
    this.currency = Currency.ils,
    required this.targetDaily,
    required this.targetMonthly,
    this.dailyGoalInLines = false,
    this.totalPages,
    this.linesPerPage,
    this.targetUnits,
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.clientEmail,
    this.targetCompletionDate,
    this.planOverrides = const {},
    this.extraFields = const {},
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// A day as it is keyed. Date only — a plan is about days, not moments, and
  /// a stray time would make two entries for one Tuesday.
  static DateTime planDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _planKey(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Map<String, dynamic> toJson() {
    return {
      // Unknown fields first, so anything this version owns always wins.
      ...extraFields,
      'id': id,
      'name': name,
      // Written both ways on purpose — see JsonCompat.enumByName. The name is
      // what this build reads; the index is what an older one still needs to
      // find where it expects it.
      'typeName': type.name,
      'type': type.index,
      'price': price,
      'expenses': expenses,
      'currency': currency.toJson(),
      'targetDaily': targetDaily,
      'targetMonthly': targetMonthly,
      'dailyGoalInLines': dailyGoalInLines,
      'totalPages': totalPages,
      'linesPerPage': linesPerPage,
      'targetUnits': targetUnits,
      'lastUpdated': lastUpdated.toIso8601String(),
      // The flag is still written because an older build looks for it and
      // would read every record as alive without it. The registers are what
      // this build reads.
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'restoredAt': restoredAt?.toIso8601String(),
      'clientEmail': clientEmail,
      'targetCompletionDate': targetCompletionDate?.toIso8601String(),
      'planOverrides': {
        for (final e in planOverrides.entries) _planKey(e.key): e.value,
      },
    };
  }

  /// Throws only when there is no usable id — a record that cannot be merged is
  /// not a record. Every other field falls back rather than failing, so one odd
  /// value cannot cost the user a whole import.
  factory Project.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('project without an id');

    final lastUpdated = JsonCompat.date(json['lastUpdated'], DateTime.now());
    final tombstone = JsonCompat.tombstone(json, lastUpdated);

    return Project(
      id: id,
      name: JsonCompat.string(json['name'], 'פרויקט'),
      type: JsonCompat.enumByName(
          json, 'typeName', 'type', ProjectType.values, ProjectType.sefer),
      price: JsonCompat.number(json['price'], 0),
      expenses: JsonCompat.number(json['expenses'], 0),
      currency: Currency.fromJson(json['currency']),
      targetDaily: JsonCompat.integer(json['targetDaily'], 0),
      targetMonthly: JsonCompat.integer(json['targetMonthly'], 0),
      dailyGoalInLines: JsonCompat.boolean(json['dailyGoalInLines'], false),
      totalPages: JsonCompat.intOrNull(json['totalPages']),
      linesPerPage: JsonCompat.intOrNull(json['linesPerPage']),
      targetUnits: JsonCompat.intOrNull(json['targetUnits']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      clientEmail: json['clientEmail'] as String?,
      targetCompletionDate: JsonCompat.dateOrNull(json['targetCompletionDate']),
      // A key that is not a date, or a weight that is not a number, is dropped
      // rather than taken down with the whole commission: one bad entry in a
      // planning aid must not cost the writer the job it belongs to.
      planOverrides: switch (json['planOverrides']) {
        final Map raw => {
            for (final e in raw.entries)
              if (DateTime.tryParse('${e.key}') != null &&
                  JsonCompat.doubleOrNull(e.value) != null)
                planDay(DateTime.parse('${e.key}')):
                    JsonCompat.doubleOrNull(e.value)!,
          },
        _ => const <DateTime, double>{},
      },
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  Project copyWith({
    String? name,
    double? price,
    double? expenses,
    Currency? currency,
    int? targetDaily,
    int? targetMonthly,
    bool? dailyGoalInLines,
    int? totalPages,
    int? linesPerPage,
    int? targetUnits,
    bool? isDeleted,
    String? clientEmail,
    DateTime? targetCompletionDate,
    Map<DateTime, double>? planOverrides,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      type: type,
      price: price ?? this.price,
      expenses: expenses ?? this.expenses,
      currency: currency ?? this.currency,
      targetDaily: targetDaily ?? this.targetDaily,
      targetMonthly: targetMonthly ?? this.targetMonthly,
      dailyGoalInLines: dailyGoalInLines ?? this.dailyGoalInLines,
      totalPages: totalPages ?? this.totalPages,
      linesPerPage: linesPerPage ?? this.linesPerPage,
      targetUnits: targetUnits ?? this.targetUnits,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      clientEmail: clientEmail ?? this.clientEmail,
      targetCompletionDate: targetCompletionDate ?? this.targetCompletionDate,
      planOverrides: planOverrides ?? this.planOverrides,
      extraFields: extraFields,
    );
  }

  @override
  Project withTombstone({DateTime? deletedAt, DateTime? restoredAt}) => Project(
        id: id,
        name: name,
        type: type,
        price: price,
        expenses: expenses,
        currency: currency,
        targetDaily: targetDaily,
        targetMonthly: targetMonthly,
        dailyGoalInLines: dailyGoalInLines,
        totalPages: totalPages,
        linesPerPage: linesPerPage,
        targetUnits: targetUnits,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        clientEmail: clientEmail,
        targetCompletionDate: targetCompletionDate,
        planOverrides: planOverrides,
        extraFields: extraFields,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class WorkSession implements Mergeable<WorkSession> {
  @override
  final String id;
  final String projectId;
  final DateTime startTime;
  final DateTime endTime;

  /// Quantity, whose meaning depends on the project type — use the named
  /// accessors below rather than reading this directly:
  ///
  /// * sefer    → the **page number** this session was written on
  /// * mezuza   → the **count** of mezuzot
  /// * tefillin → the **count** of sets, head/hand units, or parshiyot,
  ///              depending on [tefillinType] and [parshiya]
  ///
  /// The three meanings share one field for historical reasons; changing the
  /// storage shape would break every existing backup.
  final int amount;
  final int startLine;
  final int endLine;
  final String? tefillinType; // 'head' or 'hand'
  final int? parshiya; // 1-4
  final String description;
  final bool isManual;
  /// When true: counts only for project total written (הספק); excluded from profit, averages, daily goal.
  final bool backlogOnly;

  /// Whether a working time was actually given for this session.
  ///
  /// Plenty of sofrim record only what they wrote and never how long it took.
  /// That used to be stored as a session beginning at midday and lasting no time
  /// at all — an invented fact sitting in a raw field, and afterwards
  /// indistinguishable from a sitting that genuinely measured zero. Nothing
  /// could tell the two apart again, which is precisely what a later change to
  /// any time-dependent calculation would have to be able to do.
  ///
  /// [duration] stays derived from the timestamps and is still zero here. This
  /// says *why* it is zero, and it is the flag to read before presenting or
  /// computing anything per hour.
  ///
  /// Sessions written before this field existed derive it from the times they
  /// carry: an end after the start means a time was given. That reading loses
  /// nothing, because it is the only thing the older writer could have meant.
  final bool timeRecorded;

  /// Whether the hour on [startTime] is a fact about when the writing happened.
  ///
  /// False when the writer gave only a length — "two hours" — and the app had
  /// to anchor it somewhere to store a pair of timestamps. The duration is
  /// real; the position on the clock is not, and anything that asks *when* a
  /// sofer writes has to know the difference.
  ///
  /// This was already wrong before anyone could say so: the entry form opened
  /// at 09:00 by default, so every manual record left untouched swore the
  /// writer had begun at nine. His "best hour" was an artefact of a default.
  ///
  /// Absent on records written before the field existed, which read as true —
  /// the same reading the old code gave them, and the only one available for a
  /// record that never stated otherwise.
  final bool timeOfDayKnown;

  /// Lines per page as configured when this session was recorded (sefer only).
  ///
  /// Production and profit are derived from lines divided by page size, so
  /// changing the project setting later would otherwise rewrite what the
  /// writer earned in past months. Snapshotting the value keeps history
  /// stable. Null on sessions recorded before this field existed, which fall
  /// back to the project's current setting.
  final int? linesPerPageAtEntry;

  /// The save this record came out of, shared by every record it produced.
  ///
  /// One entry becomes several records: a page range is one record per page, a
  /// sitting in smart mode one per page it touched. The stretch of time entered
  /// is divided between them, and each record stores its own slice — a
  /// conclusion sitting in a raw field. Which meant that if the division were
  /// ever found to be wrong, or a better one wanted, there was nothing left to
  /// redo it from: the records had scattered and nothing said they belonged
  /// together.
  ///
  /// The slices are contiguous and exhaust the stretch, so with the grouping
  /// known the original entry is recovered exactly — first to last. That is why
  /// this is the only thing stored: the stretch, the weights and the division
  /// all follow from the records themselves, and storing a derived value twice
  /// is how the two copies come to disagree.
  ///
  /// Set on every record this build writes, including one saved alone. A group
  /// of one has to be marked as such, or an unmarked record is ambiguous
  /// between "saved by itself" and "saved before any of this existed" — and
  /// those want opposite treatment.
  final String? entryId;

  /// The day-boundary rule that was in force when this session was recorded.
  ///
  /// The *rule*, not the day it produced. Freezing the day protected history
  /// from a later change of setting, which is right — but it also meant that a
  /// mistake in the sunset or nightfall computation could never be corrected
  /// for work already recorded, and that adding per-city zmanim would leave
  /// every past record reckoned by the wrong place for ever. Freezing the rule
  /// gives both: the setting may change and nothing moves, and the computation
  /// may be corrected and everything does.
  ///
  /// Null on sessions recorded before the rule was kept. Those keep
  /// [workingDateAtEntry], which is exactly what they were counted under.
  final DayStart? dayRule;

  /// The working day this session was filed under when it was recorded.
  ///
  /// Derived once, at entry, from the day-boundary setting in force at the time
  /// — not recomputed on every read. A sofer who used to write until 00:30 and
  /// counted it as the previous day, and who later moves his boundary, must not
  /// have years of past work silently re-filed under different days: what
  /// matters is how the day was reckoned when the writing actually happened.
  ///
  /// This also means a future change to how the boundary is computed — adding a
  /// city for writers abroad, say, which would shift every nightfall — cannot
  /// move history.
  ///
  /// Null on sessions recorded before this field existed; those fall back to
  /// deriving the day from the current setting, which is the old behaviour and
  /// the best available answer for a record that never stated one.
  ///
  /// Still written by this build, even though [dayRule] is what it reads. An
  /// older build looks for this and would otherwise re-derive the day with
  /// whatever setting happens to be current on that device.
  final DateTime? workingDateAtEntry;

  @override
  final DateTime lastUpdated;

  /// When this record was deleted, and when it was restored. Two independent
  /// registers rather than one flag.
  ///
  /// Merging used to resolve a disagreement by whichever device wrote last, so
  /// an edit made on a stale copy beat a deletion made on another device and
  /// the record came back from the dead. Registers merge on their own: each
  /// side takes the later of the two, and a deletion is undone only by a
  /// restore that is genuinely later than it — never by an unrelated edit.
  @override
  final DateTime? deletedAt;
  @override
  final DateTime? restoredAt;

  /// Whether this record counts as deleted.
  bool get isDeleted {
    final deleted = deletedAt;
    if (deleted == null) return false;
    final restored = restoredAt;
    return restored == null || deleted.isAfter(restored);
  }

  /// Fields written by a newer version, carried through untouched. See
  /// [Project.extraFields].
  final Map<String, dynamic> extraFields;

  static const Set<String> _knownKeys = {
    'id',
    'projectId',
    'startTime',
    'endTime',
    'amount',
    'startLine',
    'endLine',
    'tefillinType',
    'parshiya',
    'description',
    'isManual',
    'backlogOnly',
    'timeRecorded',
    'timeOfDayKnown',
    'linesPerPageAtEntry',
    'entryId',
    'dayRule',
    'workingDateAtEntry',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
  };

  WorkSession({
    required this.id,
    required this.projectId,
    required this.startTime,
    required this.endTime,
    required this.amount,
    required this.startLine,
    required this.endLine,
    this.tefillinType,
    this.parshiya,
    required this.description,
    required this.isManual,
    this.backlogOnly = false,
    bool? timeRecorded,
    this.timeOfDayKnown = true,
    this.linesPerPageAtEntry,
    this.entryId,
    this.dayRule,
    this.workingDateAtEntry,
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.extraFields = const {},
  })  : // Left unstated, it is read off the times — the same rule that migrates
        // a session recorded before the field existed. Callers that know the
        // answer say so, because a writer who chose not to give a time is not
        // the same as a sitting that happened to measure nothing.
        timeRecorded = timeRecorded ?? endTime.isAfter(startTime),
        lastUpdated = lastUpdated ?? DateTime.now();

  Duration get duration => endTime.difference(startTime);

  /// The page this session was written on. Sefer projects only — reading it
  /// for another type is a bug, since [amount] means a count there.
  int get pageNumber {
    assert(
      linesPerPageAtEntry != null || startLine > 0 || endLine > 0,
      'pageNumber read on a session that carries no line information — '
      'this is almost certainly not a sefer session',
    );
    return amount;
  }

  /// The number of units produced. Mezuza and tefillin projects only.
  int get unitCount => amount;

  Map<String, dynamic> toJson() {
    return {
      ...extraFields,
      'id': id,
      'projectId': projectId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'amount': amount,
      'startLine': startLine,
      'endLine': endLine,
      'tefillinType': tefillinType,
      'parshiya': parshiya,
      'description': description,
      'isManual': isManual,
      'backlogOnly': backlogOnly,
      'timeRecorded': timeRecorded,
      'timeOfDayKnown': timeOfDayKnown,
      'linesPerPageAtEntry': linesPerPageAtEntry,
      'entryId': entryId,
      'dayRule': dayRule?.toJson(),
      'workingDateAtEntry': workingDateAtEntry?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      // The flag is still written because an older build looks for it and
      // would read every record as alive without it. The registers are what
      // this build reads.
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'restoredAt': restoredAt?.toIso8601String(),
    };
  }

  /// Throws only without a usable id, which is what merging keys on. A session
  /// missing its times falls back to the epoch rather than failing: a wrong
  /// duration is visible and fixable, a refused import is not.
  factory WorkSession.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('session without an id');

    final start = JsonCompat.date(json['startTime'], DateTime(1970));
    final end = JsonCompat.date(json['endTime'], start);
    final lastUpdated = JsonCompat.date(json['lastUpdated'], DateTime.now());
    final tombstone = JsonCompat.tombstone(json, lastUpdated);

    return WorkSession(
      id: id,
      projectId: JsonCompat.string(json['projectId']),
      startTime: start,
      endTime: end,
      amount: JsonCompat.integer(json['amount'], 0),
      startLine: JsonCompat.integer(json['startLine'], 0),
      endLine: JsonCompat.integer(json['endLine'], 0),
      tefillinType: json['tefillinType'] as String?,
      parshiya: JsonCompat.intOrNull(json['parshiya']),
      description: JsonCompat.string(json['description']),
      isManual: JsonCompat.boolean(json['isManual'], false),
      backlogOnly: JsonCompat.boolean(json['backlogOnly'], false),
      // Absent on anything written before the field existed. Reading it off the
      // times is exactly what the old writer meant by them.
      timeRecorded:
          JsonCompat.boolean(json['timeRecorded'], end.isAfter(start)),
      timeOfDayKnown: JsonCompat.boolean(json['timeOfDayKnown'], true),
      linesPerPageAtEntry: JsonCompat.intOrNull(json['linesPerPageAtEntry']),
      // Empty is absent: a record that names no entry belongs to no group, and
      // an empty string would gather every such record into one.
      entryId: switch (json['entryId']) {
        final String s when s.isNotEmpty => s,
        _ => null,
      },
      dayRule: json['dayRule'] is Map
          ? DayStart.fromJson(Map<String, dynamic>.from(json['dayRule'] as Map))
          : null,
      workingDateAtEntry: JsonCompat.dateOrNull(json['workingDateAtEntry']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  @override
  WorkSession withTombstone({DateTime? deletedAt, DateTime? restoredAt}) =>
      WorkSession(
        id: id,
        projectId: projectId,
        startTime: startTime,
        endTime: endTime,
        amount: amount,
        startLine: startLine,
        endLine: endLine,
        tefillinType: tefillinType,
        parshiya: parshiya,
        description: description,
        isManual: isManual,
        backlogOnly: backlogOnly,
        timeRecorded: timeRecorded,
        timeOfDayKnown: timeOfDayKnown,
        linesPerPageAtEntry: linesPerPageAtEntry,
        entryId: entryId,
        dayRule: dayRule,
        workingDateAtEntry: workingDateAtEntry,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );

  WorkSession copyWith({
    DateTime? startTime,
    DateTime? endTime,
    int? amount,
    int? startLine,
    int? endLine,
    String? description,
    bool? backlogOnly,
    bool? timeRecorded,
    bool? timeOfDayKnown,
    bool? isDeleted,
    DayStart? dayRule,
    DateTime? workingDateAtEntry,
  }) {
    return WorkSession(
      id: id,
      projectId: projectId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      amount: amount ?? this.amount,
      startLine: startLine ?? this.startLine,
      endLine: endLine ?? this.endLine,
      tefillinType: tefillinType,
      parshiya: parshiya,
      description: description ?? this.description,
      isManual: isManual,
      backlogOnly: backlogOnly ?? this.backlogOnly,
      // Carried through rather than re-derived: editing an amount must not turn
      // a session that never had a time into one that did, or the other way
      // round.
      timeRecorded: timeRecorded ?? this.timeRecorded,
      timeOfDayKnown: timeOfDayKnown ?? this.timeOfDayKnown,
      linesPerPageAtEntry: linesPerPageAtEntry,
      // Kept through an edit. A corrected record is still one of the records
      // that save produced, and losing the mark would strand the rest of the
      // group with a stretch that no longer accounts for it.
      entryId: entryId,
      dayRule: dayRule ?? this.dayRule,
      workingDateAtEntry: workingDateAtEntry ?? this.workingDateAtEntry,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      extraFields: extraFields,
    );
  }
}

/// How an expense is charged against the work.
///
/// The right answer differs by what was bought: parchment is consumed by a
/// specific project, a delivery may serve several at once, ink and tools are
/// used up gradually over a stretch of time, and rent for a writing room
/// belongs to the month it covers.
enum ExpenseAllocation {
  /// Charged to one or more specific projects.
  project,

  /// Spread over a date range the user chooses.
  period,

  /// Charged to the calendar month of the expense date.
  month,
}

class Expense implements Mergeable<Expense> {
  @override
  final String id;
  final String product;
  final DateTime date;
  final double amount;

  /// What [amount] is an amount of. See [Project.currency]: stored on the
  /// record, not read from the setting, so changing the setting cannot restate
  /// what a purchase cost. Absent on anything from before this existed, which
  /// reads as shekels — the only thing it could have been.
  final Currency currency;

  /// How this expense is attributed. Defaults to [ExpenseAllocation.month],
  /// which is how every expense behaved before allocation existed.
  final ExpenseAllocation allocation;

  /// Projects this expense belongs to, when [allocation] is
  /// [ExpenseAllocation.project]. Splitting across several divides the cost
  /// evenly between them — a delivery serving three projects is a third each.
  final List<String> projectIds;

  /// Range this expense is spread over, when [allocation] is
  /// [ExpenseAllocation.period].
  final DateTime? periodStart;
  final DateTime? periodEnd;

  @override
  final DateTime lastUpdated;

  /// When this record was deleted, and when it was restored. Two independent
  /// registers rather than one flag.
  ///
  /// Merging used to resolve a disagreement by whichever device wrote last, so
  /// an edit made on a stale copy beat a deletion made on another device and
  /// the record came back from the dead. Registers merge on their own: each
  /// side takes the later of the two, and a deletion is undone only by a
  /// restore that is genuinely later than it — never by an unrelated edit.
  @override
  final DateTime? deletedAt;
  @override
  final DateTime? restoredAt;

  /// Whether this record counts as deleted.
  bool get isDeleted {
    final deleted = deletedAt;
    if (deleted == null) return false;
    final restored = restoredAt;
    return restored == null || deleted.isAfter(restored);
  }

  /// Fields written by a newer version, carried through untouched. See
  /// [Project.extraFields].
  final Map<String, dynamic> extraFields;

  static const Set<String> _knownKeys = {
    'id',
    'product',
    'date',
    'amount',
    'currency',
    'allocation',
    'allocationName',
    'projectIds',
    'periodStart',
    'periodEnd',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
  };

  Expense({
    required this.id,
    required this.product,
    required this.date,
    required this.amount,
    this.currency = Currency.ils,
    this.allocation = ExpenseAllocation.month,
    this.projectIds = const [],
    this.periodStart,
    this.periodEnd,
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.extraFields = const {},
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// Share of this expense borne by one project, when split across several.
  double get amountPerProject =>
      projectIds.isEmpty ? amount : amount / projectIds.length;

  Map<String, dynamic> toJson() {
    return {
      ...extraFields,
      'id': id,
      'product': product,
      'date': date.toIso8601String(),
      'amount': amount,
      'currency': currency.toJson(),
      // Name and index both — see JsonCompat.enumByName.
      'allocationName': allocation.name,
      'allocation': allocation.index,
      'projectIds': projectIds,
      'periodStart': periodStart?.toIso8601String(),
      'periodEnd': periodEnd?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      // The flag is still written because an older build looks for it and
      // would read every record as alive without it. The registers are what
      // this build reads.
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'restoredAt': restoredAt?.toIso8601String(),
    };
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('expense without an id');

    final date = JsonCompat.date(json['date'], DateTime.now());
    // Older backups have no lastUpdated: fall back to the expense date so
    // merging still has a deterministic timestamp.
    final lastUpdated = JsonCompat.date(json['lastUpdated'], date);
    final tombstone = JsonCompat.tombstone(json, lastUpdated);

    return Expense(
      id: id,
      product: JsonCompat.string(json['product']),
      date: date,
      amount: JsonCompat.number(json['amount'], 0),
      currency: Currency.fromJson(json['currency']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      // Expenses saved before allocation existed behave as they did then:
      // charged to the month of their date.
      allocation: JsonCompat.enumByName(json, 'allocationName', 'allocation',
          ExpenseAllocation.values, ExpenseAllocation.month),
      projectIds: JsonCompat.strings(json['projectIds']),
      periodStart: JsonCompat.dateOrNull(json['periodStart']),
      periodEnd: JsonCompat.dateOrNull(json['periodEnd']),
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  @override
  Expense withTombstone({DateTime? deletedAt, DateTime? restoredAt}) => Expense(
        id: id,
        product: product,
        date: date,
        amount: amount,
        currency: currency,
        allocation: allocation,
        projectIds: projectIds,
        periodStart: periodStart,
        periodEnd: periodEnd,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );

  Expense copyWith({
    String? product,
    DateTime? date,
    double? amount,
    Currency? currency,
    ExpenseAllocation? allocation,
    List<String>? projectIds,
    DateTime? periodStart,
    DateTime? periodEnd,
    bool? isDeleted,
  }) {
    return Expense(
      id: id,
      product: product ?? this.product,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      allocation: allocation ?? this.allocation,
      projectIds: projectIds ?? this.projectIds,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      extraFields: extraFields,
    );
  }
}

/// Where a piece of work stands in proofreading.
///
/// Ordered as the work moves, so the order of declaration is the order of the
/// job. See [JsonCompat.enumByName] for why that order can never be changed.
enum ProofreadStage {
  /// Written, not yet sent. What is sitting on the sofer's desk.
  waiting,

  /// With the proofreader.
  sent,

  /// Back, with corrections to make.
  returned,

  /// Corrections made. Finished.
  done;

  String get label => switch (this) {
        ProofreadStage.waiting => 'ממתין להגהה',
        ProofreadStage.sent => 'אצל המגיה',
        ProofreadStage.returned => 'חזר לתיקון',
        ProofreadStage.done => 'הושלם',
      };

  /// Still someone's to act on.
  bool get isOpen => this != ProofreadStage.done;
}

/// A batch of work sent out to be proofread.
///
/// The one stage of the job the app knew nothing about, although it was already
/// charging for it: "הגהות מזוזות" and "הגהות תפילין" have been expense
/// categories all along, with nowhere to say what was sent, to whom, or what
/// came back.
///
/// A batch rather than a record per page, because that is how the work moves: a
/// sofer sends a stretch of pages or a run of mezuzot and it comes back
/// together. [scope] is free text for the same reason — a writer would put
/// "עמודים א-ל" or "12 מזוזות", and forcing either into a page range would
/// invent precision the job does not have.
class Proofread implements Mergeable<Proofread> {
  @override
  final String id;

  /// The commission this work belongs to.
  final String projectId;

  final ProofreadStage stage;

  /// What was sent, in the writer's own words.
  final String scope;

  /// Who has it. A name, not a record — a sofer knows his magiah.
  final String proofreader;

  final DateTime? sentAt;
  final DateTime? returnedAt;
  final DateTime? doneAt;

  /// What the proofreading cost, and what that is an amount of. On the record
  /// rather than read from a setting, for the reason given in [Project.currency].
  final double cost;
  final Currency currency;

  /// How many corrections came back. Null when nothing was written down, which
  /// is a different answer from a clean return and has to read differently.
  final int? findings;

  final String notes;

  @override
  final DateTime lastUpdated;
  @override
  final DateTime? deletedAt;
  @override
  final DateTime? restoredAt;

  bool get isDeleted {
    final deleted = deletedAt;
    if (deleted == null) return false;
    final restored = restoredAt;
    return restored == null || deleted.isAfter(restored);
  }

  /// Fields written by a newer version, carried through untouched.
  final Map<String, dynamic> extraFields;

  static const Set<String> _knownKeys = {
    'id',
    'projectId',
    'stage',
    'stageName',
    'scope',
    'proofreader',
    'sentAt',
    'returnedAt',
    'doneAt',
    'cost',
    'currency',
    'findings',
    'notes',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
  };

  Proofread({
    required this.id,
    required this.projectId,
    this.stage = ProofreadStage.waiting,
    this.scope = '',
    this.proofreader = '',
    this.sentAt,
    this.returnedAt,
    this.doneAt,
    this.cost = 0,
    this.currency = Currency.ils,
    this.findings,
    this.notes = '',
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.extraFields = const {},
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// How long it has been out, or how long it took. Null before it was sent.
  Duration? turnaround({DateTime? now}) {
    final sent = sentAt;
    if (sent == null) return null;
    return (returnedAt ?? now ?? DateTime.now()).difference(sent);
  }

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'id': id,
        'projectId': projectId,
        // Name and index both — see JsonCompat.enumByName.
        'stageName': stage.name,
        'stage': stage.index,
        'scope': scope,
        'proofreader': proofreader,
        'sentAt': sentAt?.toIso8601String(),
        'returnedAt': returnedAt?.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'cost': cost,
        'currency': currency.toJson(),
        'findings': findings,
        'notes': notes,
        'lastUpdated': lastUpdated.toIso8601String(),
        // Written for an older build that looks for the flag and would
        // otherwise read every record as alive. The registers are what this
        // build reads.
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.toIso8601String(),
        'restoredAt': restoredAt?.toIso8601String(),
      };

  factory Proofread.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('proofread without an id');

    final lastUpdated = JsonCompat.date(json['lastUpdated'], DateTime.now());
    final tombstone = JsonCompat.tombstone(json, lastUpdated);

    return Proofread(
      id: id,
      projectId: JsonCompat.string(json['projectId']),
      stage: JsonCompat.enumByName(json, 'stageName', 'stage',
          ProofreadStage.values, ProofreadStage.waiting),
      scope: JsonCompat.string(json['scope']),
      proofreader: JsonCompat.string(json['proofreader']),
      sentAt: JsonCompat.dateOrNull(json['sentAt']),
      returnedAt: JsonCompat.dateOrNull(json['returnedAt']),
      doneAt: JsonCompat.dateOrNull(json['doneAt']),
      cost: JsonCompat.number(json['cost'], 0),
      currency: Currency.fromJson(json['currency']),
      findings: json['findings'] == null
          ? null
          : JsonCompat.number(json['findings'], 0).round(),
      notes: JsonCompat.string(json['notes']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  @override
  Proofread withTombstone({DateTime? deletedAt, DateTime? restoredAt}) =>
      _copy(deletedAt: deletedAt, restoredAt: restoredAt, touch: false);

  Proofread copyWith({
    ProofreadStage? stage,
    String? scope,
    String? proofreader,
    DateTime? sentAt,
    DateTime? returnedAt,
    DateTime? doneAt,
    double? cost,
    Currency? currency,
    int? findings,
    String? notes,
    bool? isDeleted,
  }) =>
      _copy(
        stage: stage,
        scope: scope,
        proofreader: proofreader,
        sentAt: sentAt,
        returnedAt: returnedAt,
        doneAt: doneAt,
        cost: cost,
        currency: currency,
        findings: findings,
        notes: notes,
        // Deleting and restoring each move their own register, so a later edit
        // can never undo either by accident.
        deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
        restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      );

  Proofread _copy({
    ProofreadStage? stage,
    String? scope,
    String? proofreader,
    DateTime? sentAt,
    DateTime? returnedAt,
    DateTime? doneAt,
    double? cost,
    Currency? currency,
    int? findings,
    String? notes,
    DateTime? deletedAt,
    DateTime? restoredAt,
    bool touch = true,
  }) =>
      Proofread(
        id: id,
        projectId: projectId,
        stage: stage ?? this.stage,
        scope: scope ?? this.scope,
        proofreader: proofreader ?? this.proofreader,
        sentAt: sentAt ?? this.sentAt,
        returnedAt: returnedAt ?? this.returnedAt,
        doneAt: doneAt ?? this.doneAt,
        cost: cost ?? this.cost,
        currency: currency ?? this.currency,
        findings: findings ?? this.findings,
        notes: notes ?? this.notes,
        lastUpdated: touch ? DateTime.now() : lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );
}
