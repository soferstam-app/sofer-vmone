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

  /// Reads an enum stored by index, clamping anything out of range.
  ///
  /// A newer build may add a value an older one cannot name; falling back is
  /// better than crashing on the whole import.
  static T enumByIndex<T>(Object? value, List<T> values, T fallback) {
    final index = intOrNull(value);
    if (index == null || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

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
      // version. The index beside it is no more trustworthy in that case, so
      // fall back rather than guess.
      return fallback;
    }
    return enumByIndex(json[indexKey], values, fallback);
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
