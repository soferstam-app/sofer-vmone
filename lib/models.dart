import 'logic/currency.dart';
import 'logic/hebrew_clock.dart';
import 'logic/json_compat.dart';
import 'logic/mergeable.dart';

// Append new values only: older backups also carry the numeric enum index.
enum ProjectType { sefer, mezuza, tefillin, megillah }

extension ProjectTypeGeometry on ProjectType {
  bool get isPaged => this == ProjectType.sefer || this == ProjectType.megillah;
}

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

  /// For paged work (Sefer Torah or Megillah): when true, [targetDaily] is in
  /// lines; when false, in pages.
  final bool dailyGoalInLines;
  final int? totalPages;
  final int? linesPerPage;

  /// The selected Megillah layout. Kept separately from page geometry so the
  /// intentionally comic 14.5 layout can be removed without hunting for
  /// projects that merely happen to have the same numbers.
  final String? megillahFormat;

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

  /// Tefillin slots that are neither unwritten nor finished, keyed
  /// `"pair:side:parshiya"` — `"5:head:2"` — and valued `stuck` or `void`.
  ///
  /// How far a parshiya got is derived from the sessions and never stored.
  /// These two are not: a parshiya stopped on until it can be corrected, and
  /// one written off altogether, are facts about the work that no session
  /// records. They are also rare, which is why a small map on the commission
  /// is enough.
  ///
  /// It lives here rather than in a list of its own because
  /// [StorageService.exportAll] builds a file from the keys it knows: a new
  /// top-level list would be dropped by an older build's import, while an
  /// unknown field on a commission travels through [extraFields] and comes
  /// back whole.
  final Map<String, String> tefillinFlags;

  /// The key a slot is flagged under.
  static String slotKey(int pair, String side, int parshiya) =>
      '$pair:$side:$parshiya';

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
    'megillahFormat',
    'targetUnits',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
    'clientEmail',
    'targetCompletionDate',
    'planOverrides',
    'tefillinFlags',
  };

  /// The physical size of the job — pages, mezuzot or sets. A Megillah is
  /// priced as one commission but its physical plan is still stated in pages.
  /// Null when unknown.
  double? get plannedUnits => switch (type) {
        ProjectType.sefer || ProjectType.megillah => totalPages?.toDouble(),
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
    this.megillahFormat,
    this.targetUnits,
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.clientEmail,
    this.targetCompletionDate,
    this.planOverrides = const {},
    this.tefillinFlags = const {},
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
      'megillahFormat': megillahFormat,
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
      'tefillinFlags': tefillinFlags,
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
      megillahFormat: JsonCompat.string(json['megillahFormat']).isEmpty
          ? null
          : JsonCompat.string(json['megillahFormat']),
      targetUnits: JsonCompat.intOrNull(json['targetUnits']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      clientEmail:
          json['clientEmail'] is String ? json['clientEmail'] as String : null,
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
      // A flag that is not a string is dropped rather than taken down with the
      // commission it belongs to.
      tefillinFlags: switch (json['tefillinFlags']) {
        final Map raw => {
            for (final e in raw.entries)
              if (e.value is String) '${e.key}': e.value as String,
          },
        _ => const <String, String>{},
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
    String? megillahFormat,
    int? targetUnits,
    bool? isDeleted,
    Object? clientEmail = _keep,
    Object? targetCompletionDate = _keep,
    Map<DateTime, double>? planOverrides,
    Map<String, String>? tefillinFlags,
    Map<String, dynamic>? extraFields,
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
      megillahFormat: megillahFormat ?? this.megillahFormat,
      targetUnits: targetUnits ?? this.targetUnits,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      clientEmail: identical(clientEmail, _keep)
          ? this.clientEmail
          : clientEmail as String?,
      targetCompletionDate: identical(targetCompletionDate, _keep)
          ? this.targetCompletionDate
          : targetCompletionDate as DateTime?,
      planOverrides: planOverrides ?? this.planOverrides,
      tefillinFlags: tefillinFlags ?? this.tefillinFlags,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  /// Distinguishes an omitted nullable field from an explicit request to clear
  /// it. Without this, editing a project could never remove an old email or
  /// target date once it had been entered.
  static const Object _keep = Object();

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
        megillahFormat: megillahFormat,
        targetUnits: targetUnits,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        clientEmail: clientEmail,
        targetCompletionDate: targetCompletionDate,
        planOverrides: planOverrides,
        tefillinFlags: tefillinFlags,
        extraFields: extraFields,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Project && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// The lifecycle of a customer's order. Delivery can also be partial: the
/// quantities on [OrderItem] are the source of truth for the progress shown.
enum OrderStatus { open, partial, supplied, cancelled }

/// One kind of work inside an order. An order is deliberately not limited to
/// one project type or one project: a customer may ask for mezuzot, a
/// Megillah and tefillin together.
class OrderItem {
  final String id;
  final ProjectType type;
  final int quantity;
  final int suppliedQuantity;
  final String notes;
  final String? projectId;
  final Map<String, dynamic> extraFields;

  const OrderItem({
    required this.id,
    required this.type,
    required this.quantity,
    this.suppliedQuantity = 0,
    this.notes = '',
    this.projectId,
    this.extraFields = const {},
  });

  int get remainingQuantity =>
      (quantity - suppliedQuantity).clamp(0, quantity).toInt();

  bool get isSupplied => remainingQuantity == 0;

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'id': id,
        'typeName': type.name,
        'type': type.index,
        'quantity': quantity,
        'suppliedQuantity': suppliedQuantity,
        'notes': notes,
        'projectId': projectId,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('order item without an id');
    final quantity =
        JsonCompat.integer(json['quantity'], 1).clamp(1, 100000).toInt();
    final supplied = JsonCompat.integer(json['suppliedQuantity'], 0)
        .clamp(0, quantity)
        .toInt();
    return OrderItem(
      id: id,
      type: JsonCompat.enumByName(
          json, 'typeName', 'type', ProjectType.values, ProjectType.sefer),
      quantity: quantity,
      suppliedQuantity: supplied,
      notes: JsonCompat.string(json['notes']),
      projectId:
          json['projectId'] is String ? json['projectId'] as String : null,
      extraFields: JsonCompat.unknownKeys(json, {
        'id',
        'typeName',
        'type',
        'quantity',
        'suppliedQuantity',
        'notes',
        'projectId',
      }),
    );
  }

  OrderItem copyWith({
    ProjectType? type,
    int? quantity,
    int? suppliedQuantity,
    String? notes,
    Object? projectId = _keep,
  }) {
    final nextQuantity = (quantity ?? this.quantity).clamp(1, 100000).toInt();
    return OrderItem(
      id: id,
      type: type ?? this.type,
      quantity: nextQuantity,
      suppliedQuantity: (suppliedQuantity ?? this.suppliedQuantity)
          .clamp(0, nextQuantity)
          .toInt(),
      notes: notes ?? this.notes,
      projectId:
          identical(projectId, _keep) ? this.projectId : projectId as String?,
      extraFields: extraFields,
    );
  }

  static const Object _keep = Object();
}

/// A customer's commitment, separate from a writing [Project].
///
/// Keeping this as its own record means one order can contain mixed work and
/// can exist before the writer decides how to split it into projects.
class Order implements Mergeable<Order> {
  @override
  final String id;
  final String customerName;
  final String phone;
  final String email;
  final DateTime orderedAt;
  final DateTime dueDate;
  final String requirements;
  final double price;
  final Currency currency;
  final List<OrderItem> items;

  /// Nested records this version cannot interpret, retained verbatim on save.
  final List<dynamic> unreadableItems;
  final OrderStatus status;
  final DateTime? suppliedAt;

  @override
  final DateTime lastUpdated;
  @override
  final DateTime? deletedAt;
  @override
  final DateTime? restoredAt;
  final Map<String, dynamic> extraFields;

  bool get isDeleted {
    final deleted = deletedAt;
    if (deleted == null) return false;
    final restored = restoredAt;
    return restored == null || deleted.isAfter(restored);
  }

  bool get isFullySupplied =>
      status == OrderStatus.supplied ||
      (unreadableItems.isEmpty &&
          items.isNotEmpty &&
          items.every((item) => item.isSupplied));

  int get totalQuantity => items.fold(0, (sum, item) => sum + item.quantity);
  int get suppliedQuantity =>
      items.fold(0, (sum, item) => sum + item.suppliedQuantity);

  const Order({
    required this.id,
    required this.customerName,
    this.phone = '',
    this.email = '',
    required this.orderedAt,
    required this.dueDate,
    this.requirements = '',
    this.price = 0,
    this.currency = Currency.ils,
    this.items = const [],
    this.unreadableItems = const [],
    this.status = OrderStatus.open,
    this.suppliedAt,
    required this.lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.extraFields = const {},
  });

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'id': id,
        'customerName': customerName,
        'phone': phone,
        'email': email,
        'orderedAt': orderedAt.toIso8601String(),
        'dueDate': dueDate.toIso8601String(),
        'requirements': requirements,
        'price': price,
        'currency': currency.toJson(),
        'items': [for (final item in items) item.toJson(), ...unreadableItems],
        'statusName': status.name,
        'status': status.index,
        'suppliedAt': suppliedAt?.toIso8601String(),
        'lastUpdated': lastUpdated.toIso8601String(),
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.toIso8601String(),
        'restoredAt': restoredAt?.toIso8601String(),
      };

  factory Order.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('order without an id');
    final orderedAt = JsonCompat.date(json['orderedAt'], DateTime.now());
    final dueDate = JsonCompat.date(json['dueDate'], orderedAt);
    final lastUpdated = JsonCompat.date(json['lastUpdated'], orderedAt);
    final tombstone = JsonCompat.tombstone(json, lastUpdated);
    final rawItems = json['items'];
    if (rawItems != null && rawItems is! List) {
      throw const FormatException('Unreadable order items');
    }
    final items = <OrderItem>[];
    final unreadableItems = <dynamic>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        try {
          if (raw is Map) {
            items.add(OrderItem.fromJson(Map<String, dynamic>.from(raw)));
          } else {
            unreadableItems.add(raw);
          }
        } catch (_) {
          unreadableItems.add(raw);
        }
      }
    }
    return Order(
      id: id,
      customerName: JsonCompat.string(json['customerName']),
      phone: JsonCompat.string(json['phone']),
      email: JsonCompat.string(json['email']),
      orderedAt: orderedAt,
      dueDate: dueDate,
      requirements: JsonCompat.string(json['requirements']),
      price: JsonCompat.number(json['price'], 0),
      currency: Currency.fromJson(json['currency']),
      items: items,
      unreadableItems: unreadableItems,
      status: JsonCompat.enumByName(
          json, 'statusName', 'status', OrderStatus.values, OrderStatus.open),
      suppliedAt: JsonCompat.dateOrNull(json['suppliedAt']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      extraFields: JsonCompat.unknownKeys(json, {
        'id',
        'customerName',
        'phone',
        'email',
        'orderedAt',
        'dueDate',
        'requirements',
        'price',
        'currency',
        'items',
        'statusName',
        'status',
        'suppliedAt',
        'lastUpdated',
        'isDeleted',
        'deletedAt',
        'restoredAt',
      }),
    );
  }

  Order copyWith({
    String? customerName,
    String? phone,
    String? email,
    DateTime? orderedAt,
    DateTime? dueDate,
    String? requirements,
    double? price,
    Currency? currency,
    List<OrderItem>? items,
    OrderStatus? status,
    Object? suppliedAt = _keep,
    bool? isDeleted,
  }) {
    final now = DateTime.now();
    return Order(
      id: id,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      orderedAt: orderedAt ?? this.orderedAt,
      dueDate: dueDate ?? this.dueDate,
      requirements: requirements ?? this.requirements,
      price: price ?? this.price,
      currency: currency ?? this.currency,
      items: items ?? this.items,
      unreadableItems: unreadableItems,
      status: status ?? this.status,
      suppliedAt: identical(suppliedAt, _keep)
          ? this.suppliedAt
          : suppliedAt as DateTime?,
      lastUpdated: now,
      deletedAt: isDeleted == true ? now : deletedAt,
      restoredAt: isDeleted == false ? now : restoredAt,
      extraFields: extraFields,
    );
  }

  @override
  Order withTombstone({DateTime? deletedAt, DateTime? restoredAt}) => Order(
        id: id,
        customerName: customerName,
        phone: phone,
        email: email,
        orderedAt: orderedAt,
        dueDate: dueDate,
        requirements: requirements,
        price: price,
        currency: currency,
        items: items,
        unreadableItems: unreadableItems,
        status: status,
        suppliedAt: suppliedAt,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) => other is Order && other.id == id;

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
  /// * sefer/megillah → the **page number** this session was written on
  /// * mezuza   → the **count** of mezuzot
  /// * tefillin → the **count** of sets, head/hand units, or parshiyot,
  ///              depending on [tefillinType] and [parshiya]
  ///
  /// The three meanings share one field for historical reasons; changing the
  /// storage shape would break every existing backup.
  final int amount;
  final int startLine;
  final int endLine;

  /// Which mezuza in the commission this work belongs to, 1-based.
  ///
  /// Null on records written before individual mezuzot could be left and
  /// resumed. Older builds carry the unknown field through [extraFields] and
  /// still count [amount], so adding the identity does not change the storage
  /// meaning they already understand.
  final int? mezuzaIndex;
  final String? tefillinType; // 'head' or 'hand'
  final int? parshiya; // 1-4

  /// Which pair of the commission this belongs to, 1-based. Tefillin only.
  ///
  /// A session used to know it was the second parshiya of a head, but not
  /// whose head, so a commission of ten pairs was eighty indistinguishable
  /// slots and "pair three is waiting on a correction, I am moving to pair
  /// seven" was a sentence the app could not hold.
  ///
  /// Null on everything recorded before this existed, and on work a writer
  /// records without caring which pair it lands in. Those fill the commission
  /// in writing order, which is exactly what an older build showed.
  ///
  /// An older build reading a record that carries this keeps it in
  /// [extraFields] and writes it back untouched, and still counts the record
  /// correctly from [amount] — so a phone on this version and a PC on the last
  /// one can go on exchanging files.
  final int? pairIndex;
  final String description;
  final bool isManual;

  /// When true: counts only for project total written (הספק); excluded from profit, averages, daily goal.
  final bool backlogOnly;

  /// Work that was genuinely written but cannot count as valid output.
  ///
  /// This differs from deletion: a mistaken entry goes to the recycle bin,
  /// while invalid work keeps the time the sofer actually spent on it. Older
  /// records have no such field and therefore remain valid.
  final bool isInvalid;

  /// Time spent on the line named by [partialPositionPage] and
  /// [partialPositionLine] without claiming that the line was completed.
  ///
  /// Smart writing can end half way through a line.  Keeping that time as a
  /// real session preserves the day on which it was worked, while production,
  /// profit and progress must treat it as zero output.  Once the line is
  /// completed the fragment remains for time totals and is marked
  /// [partialLineCompleted], so it is no longer carried into the line clock.
  /// Older records have no such field and remain ordinary completed output.
  final bool isPartialLine;
  final bool partialLineCompleted;

  /// The smart-mode coordinate this time belongs to.  `page` is also the
  /// mezuza index or the folded tefillin slot, matching [SmartPosition].
  final int? partialPositionPage;
  final int? partialPositionLine;

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
    'mezuzaIndex',
    'tefillinType',
    'parshiya',
    'pairIndex',
    'description',
    'isManual',
    'backlogOnly',
    'isInvalid',
    'isPartialLine',
    'partialLineCompleted',
    'partialPositionPage',
    'partialPositionLine',
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
    this.mezuzaIndex,
    this.tefillinType,
    this.parshiya,
    this.pairIndex,
    required this.description,
    required this.isManual,
    this.backlogOnly = false,
    this.isInvalid = false,
    this.isPartialLine = false,
    this.partialLineCompleted = false,
    this.partialPositionPage,
    this.partialPositionLine,
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

  /// Word ranges carry the legacy time-only flag so older apps preserve the
  /// time without guessing complete parshiyot. This reader understands their
  /// explicit production extension; unknown versions yield zero in calculators.
  bool get isTefillinWordRecord => extraFields.containsKey('tefillinWords');
  bool get isTimeOnly => isPartialLine && !isTefillinWordRecord;
  bool get countsAsOutput => !isTimeOnly;

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
      'mezuzaIndex': mezuzaIndex,
      'tefillinType': tefillinType,
      'parshiya': parshiya,
      'pairIndex': pairIndex,
      'description': description,
      'isManual': isManual,
      'backlogOnly': backlogOnly,
      'isInvalid': isInvalid,
      'isPartialLine': isPartialLine,
      'partialLineCompleted': partialLineCompleted,
      'partialPositionPage': partialPositionPage,
      'partialPositionLine': partialPositionLine,
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
      mezuzaIndex: JsonCompat.intOrNull(json['mezuzaIndex']),
      tefillinType: json['tefillinType'] is String
          ? json['tefillinType'] as String
          : null,
      parshiya: JsonCompat.intOrNull(json['parshiya']),
      pairIndex: JsonCompat.intOrNull(json['pairIndex']),
      description: JsonCompat.string(json['description']),
      isManual: JsonCompat.boolean(json['isManual'], false),
      backlogOnly: JsonCompat.boolean(json['backlogOnly'], false),
      isInvalid: JsonCompat.boolean(json['isInvalid'], false),
      isPartialLine: JsonCompat.boolean(json['isPartialLine'], false),
      partialLineCompleted:
          JsonCompat.boolean(json['partialLineCompleted'], false),
      partialPositionPage: JsonCompat.intOrNull(json['partialPositionPage']),
      partialPositionLine: JsonCompat.intOrNull(json['partialPositionLine']),
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
        mezuzaIndex: mezuzaIndex,
        tefillinType: tefillinType,
        parshiya: parshiya,
        pairIndex: pairIndex,
        description: description,
        isManual: isManual,
        backlogOnly: backlogOnly,
        isInvalid: isInvalid,
        isPartialLine: isPartialLine,
        partialLineCompleted: partialLineCompleted,
        partialPositionPage: partialPositionPage,
        partialPositionLine: partialPositionLine,
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
    String? entryId,
    DateTime? startTime,
    DateTime? endTime,
    int? amount,
    int? startLine,
    int? endLine,
    String? description,
    bool? backlogOnly,
    bool? isInvalid,
    bool? isPartialLine,
    bool? partialLineCompleted,
    bool? timeRecorded,
    bool? timeOfDayKnown,
    bool? isDeleted,
    DayStart? dayRule,
    DateTime? workingDateAtEntry,
    Map<String, dynamic>? extraFields,
  }) {
    return WorkSession(
      id: id,
      projectId: projectId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      amount: amount ?? this.amount,
      startLine: startLine ?? this.startLine,
      endLine: endLine ?? this.endLine,
      mezuzaIndex: mezuzaIndex,
      tefillinType: tefillinType,
      parshiya: parshiya,
      pairIndex: pairIndex,
      description: description ?? this.description,
      isManual: isManual,
      backlogOnly: backlogOnly ?? this.backlogOnly,
      isInvalid: isInvalid ?? this.isInvalid,
      isPartialLine: isPartialLine ?? this.isPartialLine,
      partialLineCompleted: partialLineCompleted ?? this.partialLineCompleted,
      partialPositionPage: partialPositionPage,
      partialPositionLine: partialPositionLine,
      // Carried through rather than re-derived: editing an amount must not turn
      // a session that never had a time into one that did, or the other way
      // round.
      timeRecorded: timeRecorded ?? this.timeRecorded,
      timeOfDayKnown: timeOfDayKnown ?? this.timeOfDayKnown,
      linesPerPageAtEntry: linesPerPageAtEntry,
      // Kept through an edit. A corrected record is still one of the records
      // that save produced, and losing the mark would strand the rest of the
      // group with a stretch that no longer accounts for it.
      entryId: entryId ?? this.entryId,
      dayRule: dayRule ?? this.dayRule,
      workingDateAtEntry: workingDateAtEntry ?? this.workingDateAtEntry,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      extraFields: extraFields ?? this.extraFields,
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
    Object? periodStart = _keep,
    Object? periodEnd = _keep,
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
      periodStart: identical(periodStart, _keep)
          ? this.periodStart
          : periodStart as DateTime?,
      periodEnd:
          identical(periodEnd, _keep) ? this.periodEnd : periodEnd as DateTime?,
      lastUpdated: DateTime.now(),
      // Deleting and restoring each move their own register, so a later edit
      // can never undo either of them by accident.
      deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
      restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
      extraFields: extraFields,
    );
  }

  static const Object _keep = Object();
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

  /// How long it has been out, or how long it took.
  ///
  /// Null before it was sent, and null when the two dates contradict each other
  /// — a return recorded before the send is a typo, and reporting it as minus
  /// nine days would put a negative number on a screen and in an average.
  Duration? turnaround({DateTime? now}) {
    final sent = sentAt;
    if (sent == null) return null;
    final end = returnedAt ?? now ?? DateTime.now();
    if (end.isBefore(sent)) return null;
    return end.difference(sent);
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

  /// Distinguishes "leave this alone" from "set this to nothing".
  ///
  /// With a plain `DateTime?` the two are the same value, so `copyWith` could
  /// never clear a field — a date typed into the wrong row could be changed but
  /// not removed, and neither could a correction count entered by mistake.
  static const Object _keep = Object();

  Proofread copyWith({
    String? projectId,
    ProofreadStage? stage,
    String? scope,
    String? proofreader,
    Object? sentAt = _keep,
    Object? returnedAt = _keep,
    Object? doneAt = _keep,
    double? cost,
    Currency? currency,
    Object? findings = _keep,
    String? notes,
    bool? isDeleted,
  }) =>
      _copy(
        projectId: projectId,
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
    String? projectId,
    ProofreadStage? stage,
    String? scope,
    String? proofreader,
    Object? sentAt = _keep,
    Object? returnedAt = _keep,
    Object? doneAt = _keep,
    double? cost,
    Currency? currency,
    Object? findings = _keep,
    String? notes,
    DateTime? deletedAt,
    DateTime? restoredAt,
    bool touch = true,
  }) =>
      Proofread(
        id: id,
        projectId: projectId ?? this.projectId,
        stage: stage ?? this.stage,
        scope: scope ?? this.scope,
        proofreader: proofreader ?? this.proofreader,
        sentAt: identical(sentAt, _keep) ? this.sentAt : sentAt as DateTime?,
        returnedAt: identical(returnedAt, _keep)
            ? this.returnedAt
            : returnedAt as DateTime?,
        doneAt: identical(doneAt, _keep) ? this.doneAt : doneAt as DateTime?,
        cost: cost ?? this.cost,
        currency: currency ?? this.currency,
        findings: identical(findings, _keep) ? this.findings : findings as int?,
        notes: notes ?? this.notes,
        lastUpdated: touch ? DateTime.now() : lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );
}

/// Money actually received against a commission.
///
/// The annual report used to call units-written times price "income". It is not
/// income; it is the value of work done. Work finished in Elul and paid for in
/// Tishrei landed in the wrong year, work never paid for landed in the report
/// at all, and a price raised after the fact rewrote a year that had already
/// been filed.
///
/// A record per payment rather than a "paid" field, because a sefer torah is
/// paid for in stages — an advance, something on delivery of the first third,
/// the rest at the end. One amount and one date could describe none of that.
class Payment implements Mergeable<Payment> {
  @override
  final String id;

  /// The commission this was paid against.
  final String projectId;

  final double amount;

  /// What [amount] is an amount of. On the record, as everywhere else: see
  /// [Project.currency].
  final Currency currency;

  /// When the money arrived. This is what puts it in a tax year, and it is the
  /// only date that can.
  final DateTime receivedAt;

  /// Cash, transfer, cheque — whatever the writer wants to remember. Free text
  /// rather than a list, because the list would be wrong for somebody.
  final String method;

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
    'amount',
    'currency',
    'receivedAt',
    'method',
    'notes',
    'lastUpdated',
    'isDeleted',
    'deletedAt',
    'restoredAt',
  };

  Payment({
    required this.id,
    required this.projectId,
    required this.amount,
    this.currency = Currency.ils,
    required this.receivedAt,
    this.method = '',
    this.notes = '',
    DateTime? lastUpdated,
    this.deletedAt,
    this.restoredAt,
    this.extraFields = const {},
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        ...extraFields,
        'id': id,
        'projectId': projectId,
        'amount': amount,
        'currency': currency.toJson(),
        'receivedAt': receivedAt.toIso8601String(),
        'method': method,
        'notes': notes,
        'lastUpdated': lastUpdated.toIso8601String(),
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.toIso8601String(),
        'restoredAt': restoredAt?.toIso8601String(),
      };

  factory Payment.fromJson(Map<String, dynamic> json) {
    final id = JsonCompat.string(json['id']);
    if (id.isEmpty) throw const FormatException('payment without an id');

    final receivedAt = JsonCompat.date(json['receivedAt'], DateTime.now());
    final lastUpdated = JsonCompat.date(json['lastUpdated'], receivedAt);
    final tombstone = JsonCompat.tombstone(json, lastUpdated);

    return Payment(
      id: id,
      projectId: JsonCompat.string(json['projectId']),
      amount: JsonCompat.number(json['amount'], 0),
      currency: Currency.fromJson(json['currency']),
      receivedAt: receivedAt,
      method: JsonCompat.string(json['method']),
      notes: JsonCompat.string(json['notes']),
      lastUpdated: lastUpdated,
      deletedAt: tombstone.deletedAt,
      restoredAt: tombstone.restoredAt,
      extraFields: JsonCompat.unknownKeys(json, _knownKeys),
    );
  }

  @override
  Payment withTombstone({DateTime? deletedAt, DateTime? restoredAt}) => Payment(
        id: id,
        projectId: projectId,
        amount: amount,
        currency: currency,
        receivedAt: receivedAt,
        method: method,
        notes: notes,
        lastUpdated: lastUpdated,
        deletedAt: deletedAt,
        restoredAt: restoredAt,
        extraFields: extraFields,
      );

  Payment copyWith({
    String? projectId,
    double? amount,
    Currency? currency,
    DateTime? receivedAt,
    String? method,
    String? notes,
    bool? isDeleted,
  }) =>
      Payment(
        id: id,
        projectId: projectId ?? this.projectId,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        receivedAt: receivedAt ?? this.receivedAt,
        method: method ?? this.method,
        notes: notes ?? this.notes,
        lastUpdated: DateTime.now(),
        // Each register moves on its own, so a later edit never revives a
        // deleted record.
        deletedAt: isDeleted == true ? DateTime.now() : deletedAt,
        restoredAt: isDeleted == false ? DateTime.now() : restoredAt,
        extraFields: extraFields,
      );
}
