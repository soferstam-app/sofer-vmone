import 'dart:convert';

/// Reading the file an older version left on disk.
///
/// Versions up to 0.3.1 had no backup screen at all, so a writer moving to a
/// new computer — or reinstalling after a wipe — had nothing to bring with him
/// except the file the app itself keeps. On Windows that file is plainly there
/// and readable:
///
///     %APPDATA%\com.example\stamsofer\shared_preferences.json
///
/// It is not a backup file and never claimed to be. It is the app's own store:
/// every key prefixed with `flutter.`, and the three record lists held as JSON
/// text inside string values. Converting it to the shape the restore flow
/// already understands costs nothing and closes the one route those users had.
///
/// This is a Windows and desktop rescue in practice. Android keeps the same
/// file inside the app sandbox, where nobody can reach it without root — which
/// is exactly why the signing key must not change there.
class LegacyImport {
  const LegacyImport._();

  /// The prefix `shared_preferences` puts on everything it stores.
  static const String _prefix = 'flutter.';

  /// Keys whose stored value is JSON text rather than a plain value.
  static const Set<String> _encodedLists = {
    'projects',
    'history',
    'expenses',
  };

  static const Set<String> _encodedMaps = {
    'last_positions',
  };

  /// Whether this looks like an app store file rather than a backup.
  ///
  /// Checked on the shape rather than the file name, because the writer may
  /// well have renamed it while copying it off the old machine.
  static bool looksLikeStore(Map<String, dynamic> json) =>
      json.keys.any((k) => k.startsWith(_prefix));

  /// Turns the store file into the shape a backup has.
  ///
  /// Anything unreadable is left out rather than taken as a reason to refuse
  /// the whole file: a writer restoring a broken export wants whatever survived
  /// it, and a refusal hands him nothing at all.
  static Map<String, dynamic> toBackup(
    Map<String, dynamic> store, {
    required String appId,
    required int formatVersion,
  }) {
    List<dynamic> listAt(String key) {
      final raw = store['$_prefix$key'];
      if (raw is! String || raw.isEmpty) return const [];
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded : const [];
      } catch (_) {
        return const [];
      }
    }

    Map<String, dynamic> mapAt(String key) {
      final raw = store['$_prefix$key'];
      if (raw is! String || raw.isEmpty) return const {};
      try {
        final decoded = jsonDecode(raw);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
      } catch (_) {
        return const {};
      }
    }

    // Everything that is not a record list is a setting. Carried through
    // unprefixed and untouched, including keys this build has never heard of —
    // a store written by a newer version must not lose them on the way in.
    final settings = <String, dynamic>{};
    for (final entry in store.entries) {
      if (!entry.key.startsWith(_prefix)) continue;
      final name = entry.key.substring(_prefix.length);
      if (_encodedLists.contains(name) || _encodedMaps.contains(name)) continue;
      settings[name] = entry.value;
    }

    return {
      'app': appId,
      'formatVersion': formatVersion,
      // Nothing in the store says when it was written. Claiming a date would
      // be inventing one, and the preview says "unknown" for a null.
      'exportedAt': null,
      'exportedFrom': 'התקנה קודמת',
      'projects': listAt('projects'),
      'history': listAt('history'),
      'expenses': listAt('expenses'),
      'lastPositions': mapAt('last_positions'),
      'settings': settings,
    };
  }
}
