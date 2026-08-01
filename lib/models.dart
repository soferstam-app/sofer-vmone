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
    this.extraFields = const {},
  }) : lastUpdated = lastUpdated ?? DateTime.now();

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
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  Project copyWith({
    String? name,
    double? price,
    double? expenses,
    int? targetDaily,
    int? targetMonthly,
    bool? dailyGoalInLines,
    int? totalPages,
    int? linesPerPage,
    int? targetUnits,
    bool? isDeleted,
    String? clientEmail,
    DateTime? targetCompletionDate,
  }) {
    return Project(
      id: id,
      name: name ?? this.name,
      type: type,
      price: price ?? this.price,
      expenses: expenses ?? this.expenses,
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

  /// Lines per page as configured when this session was recorded (sefer only).
  ///
  /// Production and profit are derived from lines divided by page size, so
  /// changing the project setting later would otherwise rewrite what the
  /// writer earned in past months. Snapshotting the value keeps history
  /// stable. Null on sessions recorded before this field existed, which fall
  /// back to the project's current setting.
  final int? linesPerPageAtEntry;

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
    'linesPerPageAtEntry',
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
    this.linesPerPageAtEntry,
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
      'linesPerPageAtEntry': linesPerPageAtEntry,
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
      linesPerPageAtEntry: JsonCompat.intOrNull(json['linesPerPageAtEntry']),
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
        linesPerPageAtEntry: linesPerPageAtEntry,
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
      linesPerPageAtEntry: linesPerPageAtEntry,
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
