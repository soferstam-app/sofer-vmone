/// A record that two devices can both hold, edit and delete independently.
///
/// The two tombstone registers are part of this interface because they are the
/// only fields whose merged value is not simply the winner's. Everything else
/// about a record travels together — one device's version of it wins whole —
/// but a deletion and a restore each carry their own moment, and merging takes
/// the later of each side independently.
///
/// That is what makes a deletion impossible to undo by accident. With a single
/// flag resolved by whichever device wrote last, an edit made on a stale copy
/// beat a deletion made elsewhere and the record came back from the dead. A
/// deletion is now undone only by a restore that is genuinely later than it.
abstract interface class Mergeable<T> {
  String get id;

  /// When this version of the record was written. Decides which side's payload
  /// wins; it does not decide whether the record is deleted.
  DateTime get lastUpdated;

  DateTime? get deletedAt;
  DateTime? get restoredAt;

  /// This record carrying the registers merged from both sides.
  T withTombstone({DateTime? deletedAt, DateTime? restoredAt});
}

/// The later of two moments, either of which may be absent.
DateTime? laterOf(DateTime? a, DateTime? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.isAfter(b) ? a : b;
}
