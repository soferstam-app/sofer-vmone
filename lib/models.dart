enum ProjectType { sefer, mezuza, tefillin }

class Project {
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

  final DateTime lastUpdated;
  final bool isDeleted;
  final String? clientEmail;
  final DateTime? targetCompletionDate;

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
    this.isDeleted = false,
    this.clientEmail,
    this.targetCompletionDate,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
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
      'isDeleted': isDeleted,
      'clientEmail': clientEmail,
      'targetCompletionDate': targetCompletionDate?.toIso8601String(),
    };
  }

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['id'],
      name: json['name'],
      type: ProjectType.values[json['type']],
      price: (json['price'] as num).toDouble(),
      expenses: (json['expenses'] as num).toDouble(),
      targetDaily: json['targetDaily'],
      targetMonthly: json['targetMonthly'],
      dailyGoalInLines: json['dailyGoalInLines'] ?? false,
      totalPages: json['totalPages'],
      linesPerPage: json['linesPerPage'],
      targetUnits: json['targetUnits'],
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
      isDeleted: json['isDeleted'] ?? false,
      clientEmail: json['clientEmail'] as String?,
      targetCompletionDate: json['targetCompletionDate'] != null
          ? DateTime.parse(json['targetCompletionDate'])
          : null,
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
      isDeleted: isDeleted ?? this.isDeleted,
      clientEmail: clientEmail ?? this.clientEmail,
      targetCompletionDate: targetCompletionDate ?? this.targetCompletionDate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class WorkSession {
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

  /// Lines per page as configured when this session was recorded (sefer only).
  ///
  /// Production and profit are derived from lines divided by page size, so
  /// changing the project setting later would otherwise rewrite what the
  /// writer earned in past months. Snapshotting the value keeps history
  /// stable. Null on sessions recorded before this field existed, which fall
  /// back to the project's current setting.
  final int? linesPerPageAtEntry;
  final DateTime lastUpdated;
  final bool isDeleted;

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
    this.linesPerPageAtEntry,
    DateTime? lastUpdated,
    this.isDeleted = false,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

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
      'linesPerPageAtEntry': linesPerPageAtEntry,
      'lastUpdated': lastUpdated.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory WorkSession.fromJson(Map<String, dynamic> json) {
    return WorkSession(
      id: json['id'],
      projectId: json['projectId'],
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      amount: json['amount'],
      startLine: json['startLine'],
      endLine: json['endLine'],
      tefillinType: json['tefillinType'],
      parshiya: json['parshiya'],
      description: json['description'],
      isManual: json['isManual'],
      backlogOnly: json['backlogOnly'] ?? false,
      linesPerPageAtEntry: json['linesPerPageAtEntry'] as int?,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : DateTime.now(),
      isDeleted: json['isDeleted'] ?? false,
    );
  }

  WorkSession copyWith({
    DateTime? startTime,
    DateTime? endTime,
    int? amount,
    int? startLine,
    int? endLine,
    String? description,
    bool? backlogOnly,
    bool? isDeleted,
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
      linesPerPageAtEntry: linesPerPageAtEntry,
      lastUpdated: DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
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

class Expense {
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

  final DateTime lastUpdated;
  final bool isDeleted;

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
    this.isDeleted = false,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  /// Share of this expense borne by one project, when split across several.
  double get amountPerProject =>
      projectIds.isEmpty ? amount : amount / projectIds.length;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product,
      'date': date.toIso8601String(),
      'amount': amount,
      'allocation': allocation.index,
      'projectIds': projectIds,
      'periodStart': periodStart?.toIso8601String(),
      'periodEnd': periodEnd?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'isDeleted': isDeleted,
    };
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      product: json['product'] ?? '',
      date:
          json['date'] != null ? DateTime.parse(json['date']) : DateTime.now(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      // Older backups have no lastUpdated: fall back to the expense date so
      // merging still has a deterministic timestamp.
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'])
          : (json['date'] != null
              ? DateTime.parse(json['date'])
              : DateTime.now()),
      isDeleted: json['isDeleted'] ?? false,
      // Expenses saved before allocation existed behave as they did then:
      // charged to the month of their date.
      allocation: json['allocation'] != null &&
              (json['allocation'] as int) < ExpenseAllocation.values.length
          ? ExpenseAllocation.values[json['allocation']]
          : ExpenseAllocation.month,
      projectIds: json['projectIds'] is List
          ? List<String>.from(json['projectIds'])
          : const [],
      periodStart: json['periodStart'] != null
          ? DateTime.tryParse(json['periodStart'])
          : null,
      periodEnd: json['periodEnd'] != null
          ? DateTime.tryParse(json['periodEnd'])
          : null,
    );
  }

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
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
