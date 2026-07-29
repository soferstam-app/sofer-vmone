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
  final DateTime lastUpdated;
  final bool isDeleted;
  final String? clientEmail;
  final DateTime? targetCompletionDate;

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

class Expense {
  final String id;
  final String product;
  final DateTime date;
  final double amount;
  final DateTime lastUpdated;
  final bool isDeleted;

  Expense({
    required this.id,
    required this.product,
    required this.date,
    required this.amount,
    DateTime? lastUpdated,
    this.isDeleted = false,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product,
      'date': date.toIso8601String(),
      'amount': amount,
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
    );
  }

  Expense copyWith({
    String? product,
    DateTime? date,
    double? amount,
    bool? isDeleted,
  }) {
    return Expense(
      id: id,
      product: product ?? this.product,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      lastUpdated: DateTime.now(),
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
