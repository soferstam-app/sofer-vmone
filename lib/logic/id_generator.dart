import 'dart:math';

/// Generates record identifiers that stay unique across devices.
///
/// Every id in the app used to be a bare timestamp
/// (`DateTime.now().millisecondsSinceEpoch`). Two devices creating a record in
/// the same millisecond produced the same id, and a merge would treat them as
/// one record and drop whichever lost the comparison. Rare with cloud sync,
/// but likely once users deliberately exchange backup files between a phone
/// and a computer.
///
/// The format is `<millis>-<random>`, optionally with a caller-supplied
/// suffix. The timestamp prefix keeps ids roughly sortable and readable in a
/// backup file; the random part removes the collision.
class IdGenerator {
  const IdGenerator._();

  static final Random _random = Random();

  /// A new unique id.
  ///
  /// [suffix] distinguishes several records created in one operation, such as
  /// one session per page in a page range.
  static String generate({String? suffix}) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    // 32 bits of randomness, base36 — short, and collision-free in practice
    // for a single user's record volume.
    final random = _random.nextInt(1 << 32).toRadixString(36);
    final base = '$millis-$random';
    return suffix == null ? base : '$base-$suffix';
  }
}
