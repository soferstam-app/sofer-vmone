enum ProjectType { sefer, mezuza, tefillin }

class Project {
  final String id;
  final String name;
  final ProjectType type;
  final double price;
  final double expenses;
  final int targetDaily;
  final int targetMonthly;
  final int? totalPages; // לספר תורה
  final int? linesPerPage; // לספר תורה

  Project({
    required this.id,
    required this.name,
    required this.type,
    required this.price,
    required this.expenses,
    required this.targetDaily,
    required this.targetMonthly,
    this.totalPages,
    this.linesPerPage,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.index,
      'price': price,
      'expenses': expenses,
      'targetDaily': targetDaily,
      'targetMonthly': targetMonthly,
      'totalPages': totalPages,
      'linesPerPage': linesPerPage,
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
      totalPages: json['totalPages'],
      linesPerPage: json['linesPerPage'],
    );
  }
}

class WorkSession {
  final String id;
  final String projectId;
  final DateTime startTime;
  final DateTime endTime;
  final int amount;
  final int startLine;
  final int endLine;
  final String? tefillinType; // 'head' or 'hand'
  final int? parshiya; // 1-4
  final String description;
  final bool isManual;

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
  });

  Duration get duration => endTime.difference(startTime);

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
    );
  }
}
