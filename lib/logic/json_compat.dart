/// Reading stored records without assuming they were written by this build.
///
/// The app is meant to be updated for a long time, and users move their data
/// between a phone and a PC by hand. The two devices will regularly be on
/// different versions, so a saved record has to survive drift in both
/// directions:
///
/// * **Older file, newer app** — a field that did not exist yet is missing.
///   Every reader here takes a fallback rather than throwing.
/// * **Newer file, older app** — a field the reader has never heard of is
///   present. [unknownKeys] captures those and the model writes them back out,
///   so exporting from the older device does not quietly delete them.
///
/// Without the second half, a round trip through an older build would silently
/// strip data: export from the phone, import on the PC, export back, and the
/// newer fields are gone.
/// A stored record this build cannot interpret, and must not guess at.
///
/// A record that throws this is dropped from the working set and kept in
/// storage exactly as it was, so a build that does understand it still can. The
/// app counts them and says so, because a total that is quietly short is worse
/// than one that admits what it left out.
class UnreadableRecord implements Exception {
  final String reason;
  const UnreadableRecord(this.reason);

  @override
  String toString() => 'UnreadableRecord: $reason';
}

class JsonCompat {
  const JsonCompat._();

  static String string(Object? value, [String fallback = '']) =>
      value is String ? value : fallback;

  /// Null when absent or unparseable. Accepts a number written as a string,
  /// which some JSON producers do.
  static int? intOrNull(Object? value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v),
        _ => null,
      };

  static int integer(Object? value, int fallback) =>
      intOrNull(value) ?? fallback;

  static double? doubleOrNull(Object? value) => switch (value) {
        num v => v.toDouble(),
        String v => double.tryParse(v),
        _ => null,
      };

  static double number(Object? value, double fallback) =>
      doubleOrNull(value) ?? fallback;

  static bool boolean(Object? value, bool fallback) =>
      value is bool ? value : fallback;

  /// Accepts an ISO-8601 string or epoch milliseconds.
  static DateTime? dateOrNull(Object? value) => switch (value) {
        String v => DateTime.tryParse(v),
        int v => DateTime.fromMillisecondsSinceEpoch(v),
        _ => null,
      };

  static DateTime date(Object? value, DateTime fallback) =>
      dateOrNull(value) ?? fallback;

  static List<String> strings(Object? value) =>
      value is List ? value.whereType<String>().toList() : const [];

  /// A stored record this build cannot interpret.
  ///
  /// Thrown rather than guessed at. The record is kept in storage untouched and
  /// simply takes no part in anything the app computes, which is recoverable;
  /// substituting a default would make it silently the wrong kind of work, and
  /// every figure it feeds silently wrong with it.
  static Never unreadable(String why) => throw UnreadableRecord(why);

  /// Reads an enum written as its name, falling back to the index a older file
  /// carries.
  ///
  /// An index is a promise that the enum's declaration order will never change,
  /// and nothing in the language keeps that promise: inserting a value into
  /// `ProjectType` would silently turn every sefer in an existing backup into a
  /// mezuza. A name means what it says.
  ///
  /// Both are written, which is what makes the change safe in both directions.
  /// A build that only understands the old shape still finds the index where it
  /// expects it, and carries the name through untouched in `extraFields`; a
  /// build that understands names prefers the name and ignores the index.
  ///
  /// [nameKey] is read first, then [indexKey].
  static T enumByName<T extends Enum>(
    Map<String, dynamic> json,
    String nameKey,
    String indexKey,
    List<T> values,
    T fallback,
  ) {
    final name = json[nameKey];
    if (name is String && name.isNotEmpty) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      // A name this build does not know — a kind of work added by a newer
      // version. The index beside it is no more trustworthy, and neither is any
      // default: a mezuza read as a sefer is not a smaller mistake than a
      // record left out, it is a bigger one, because it is invisible.
      unreadable('$nameKey "$name" is not a value this version knows');
    }

    final index = intOrNull(json[indexKey]);
    // Neither key is there at all: written before the field existed, and the
    // documented default is what it meant.
    if (index == null) return fallback;
    if (index < 0 || index >= values.length) {
      unreadable('$indexKey $index is outside what this version knows');
    }
    return values[index];
  }

  /// Reads the two tombstone registers, migrating a record that carried only a
  /// flag.
  ///
  /// A record written before the registers existed says `isDeleted: true` and
  /// nothing more. The moment the flag was set is not recorded anywhere, and
  /// `lastUpdated` is the closest thing to it that exists — the write that set
  /// the flag was, by definition, the last write. The reading is exact for
  /// every record that has not been edited since it was deleted, and no worse
  /// than the flag itself for any other.
  static ({DateTime? deletedAt, DateTime? restoredAt}) tombstone(
    Map<String, dynamic> json,
    DateTime lastUpdated,
  ) {
    final deletedAt = dateOrNull(json['deletedAt']);
    final restoredAt = dateOrNull(json['restoredAt']);
    if (deletedAt != null || restoredAt != null) {
      return (deletedAt: deletedAt, restoredAt: restoredAt);
    }
    return boolean(json['isDeleted'], false)
        ? (deletedAt: lastUpdated, restoredAt: null)
        : (deletedAt: null, restoredAt: null);
  }

  /// Everything in [json] that is not in [known].
  ///
  /// Returned as a plain map so a model can hold it and spread it back into its
  /// own `toJson`. Empty — and shared — when there is nothing unknown, so the
  /// common case allocates nothing.
  static Map<String, dynamic> unknownKeys(
      Map<String, dynamic> json, Set<String> known) {
    Map<String, dynamic>? extra;
    for (final entry in json.entries) {
      if (known.contains(entry.key)) continue;
      (extra ??= <String, dynamic>{})[entry.key] = entry.value;
    }
    return extra ?? const <String, dynamic>{};
  }
}
