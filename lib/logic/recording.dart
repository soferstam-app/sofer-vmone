import '../models.dart';
import 'session_logic.dart';

/// The records one save produced, gathered back into the entry they came from.
///
/// An entry rarely becomes one record. A page range becomes one per page; a
/// sitting in smart mode one per page it touched. The stretch of time entered
/// is divided between them and each keeps its own slice, which is a conclusion
/// stored in a raw field — the kind of thing that cannot be questioned later
/// unless what it was concluded from survives.
///
/// It does survive, in two halves. The slices are contiguous and exhaust the
/// stretch, so first-to-last recovers exactly what was entered; and
/// [WorkSession.entryId] says which records to run that over. Neither is any
/// use without the other, and together they are enough to divide the entry
/// again by a rule nobody has thought of yet.
///
/// Nothing in the app divides an entry a second time today, because no division
/// has been found wrong yet. That is the point: the day one is, the answer has
/// to already be in the file, since by then the writing is years old and there
/// is nobody left to ask.
class Recording {
  /// The save these records came from. Null for records written before the mark
  /// existed, each of which stands alone.
  final String? entryId;

  /// In the order their slices were laid down.
  final List<WorkSession> sessions;

  const Recording({required this.entryId, required this.sessions});

  /// When the entry began — the start of the first slice.
  DateTime get start => sessions.first.startTime;

  /// When it ended — the end of the last slice.
  ///
  /// The furthest any record reaches, not simply the end of the last of them.
  /// Untouched they are the same thing, the slices being contiguous. Once a
  /// record has been corrected by hand they need not be, and taking the
  /// furthest is what keeps [worked] from coming out negative and a division
  /// from running backwards through the day.
  DateTime get end => sessions
      .map((s) => s.endTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  /// How long the entry covered, before any of it was divided up.
  Duration get worked => end.difference(start);

  /// Whether a working time was given at all. False means the slices are all
  /// empty on purpose and dividing them again is arithmetic about nothing.
  bool get timeRecorded => sessions.any((s) => s.timeRecorded);

  /// Gathers records back into the entries that produced them.
  ///
  /// A record with no [WorkSession.entryId] comes back as an entry of its own:
  /// it is either older than the mark or genuinely was saved alone, and either
  /// way there is nothing it can be grouped with. Entries come back in the
  /// order their first record appears, and the records within each in
  /// chronological order, which is the order they were divided in.
  ///
  /// What goes in is the caller's decision, deleted records included or not.
  /// Left in, they keep the stretch as wide as the entry really was; taken out,
  /// [worked] narrows to what is still standing.
  static List<Recording> gather(Iterable<WorkSession> sessions) {
    final order = <String>[];
    final groups = <String, List<WorkSession>>{};
    final alone = <Recording>[];

    for (final session in sessions) {
      final entryId = session.entryId;
      if (entryId == null) {
        alone.add(Recording(entryId: null, sessions: [session]));
        continue;
      }
      if (!groups.containsKey(entryId)) order.add(entryId);
      groups.putIfAbsent(entryId, () => []).add(session);
    }

    return [
      for (final entryId in order)
        Recording(
          entryId: entryId,
          sessions: groups[entryId]!..sort(_bySlice),
        ),
      ...alone,
    ];
  }

  /// Divides the entry again, by weights of the caller's choosing.
  ///
  /// The stretch is the one recovered from the records themselves, so this is
  /// exact however many times it is repeated: dividing by the weights already
  /// used gives the records back unchanged in their times.
  ///
  /// Returns the records in the same order, each with its new slice. An entry
  /// that never had a working time comes back untouched — there is nothing to
  /// divide, and handing it empty slices would be inventing the claim that it
  /// was measured.
  List<WorkSession> divideBy(int Function(WorkSession) weight) {
    if (!timeRecorded || sessions.length < 2) return sessions;

    final slices = SessionLogic.splitByWeight(
      start: start,
      end: end,
      weights: [for (final s in sessions) weight(s)],
    );
    return [
      for (var i = 0; i < sessions.length; i++)
        sessions[i]
            .copyWith(startTime: slices[i].start, endTime: slices[i].end),
    ];
  }

  /// Chronological, and by id where two slices begin together — so that an
  /// entry with no working time, whose slices are all the same instant, still
  /// gathers in one settled order rather than whichever the file happened to
  /// hold.
  static int _bySlice(WorkSession a, WorkSession b) {
    final byTime = a.startTime.compareTo(b.startTime);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }
}
