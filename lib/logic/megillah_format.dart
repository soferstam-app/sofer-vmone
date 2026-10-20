import '../models.dart';

/// The supported Megillah page layouts.
///
/// Do not infer the comic layout from its geometry. Its stable id is the
/// deletion seam that lets us remove the joke later without leaving special
/// cases scattered through ordinary Megillah calculations.
class MegillahFormat {
  static const String lines11 = 'lines11';
  static const String lines21 = 'lines21';
  static const String lines28 = 'lines28';
  static const String satire14_5 = 'satire14_5';

  static const List<String> values = [lines11, lines21, lines28, satire14_5];

  static String normalize(String? value) =>
      values.contains(value) ? value! : lines11;

  static int totalPages(String value) => switch (normalize(value)) {
        lines11 => 38,
        lines21 => 20,
        lines28 => 16,
        satire14_5 => 399,
        _ => 38,
      };

  /// The joke layout is entered as fifteen selectable writing rows. The half
  /// is deliberately presentation-only; ordinary line-range storage stays
  /// integral and remains fully compatible with all existing correction code.
  static int storedLinesPerPage(String value) => switch (normalize(value)) {
        lines11 => 11,
        lines21 => 21,
        lines28 => 28,
        satire14_5 => 15,
        _ => 11,
      };

  static String displayLines(String value) =>
      normalize(value) == satire14_5 ? '14.5' : '${storedLinesPerPage(value)}';

  static bool isSatire(Project project) =>
      project.type == ProjectType.megillah &&
      project.megillahFormat == satire14_5;

  /// A purposely backwards progress figure: the first progress is almost
  /// 150%, and it drifts down to 100% as the 399-page commission is completed.
  /// Zero remains zero so an untouched project does not claim an achievement.
  static double displayedProgress(Project project, double realProgress) {
    if (!isSatire(project) || realProgress <= 0) return realProgress;
    final clamped = realProgress.clamp(0.0, 1.0);
    return 1.5 - (0.5 * clamped);
  }
}
