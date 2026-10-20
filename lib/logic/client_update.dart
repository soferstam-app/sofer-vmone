import '../models.dart';
import 'production_calculator.dart';
import 'megillah_format.dart';

/// The progress update a sofer sends a client.
///
/// The one thing the app writes that leaves it and is read by someone else, and
/// it was built inside a screen where nothing could check a word of it. A
/// figure that came out wrong here would go out over the writer's name.
///
/// Written as something that can be sent as-is: what was written, how far along
/// it is, and when it is expected to be finished — the last being what a client
/// actually wants to know. A figure the app cannot compute for a given kind of
/// work is left out rather than sent as an empty line.
class ClientUpdate {
  const ClientUpdate._();

  static String compose({
    required Project project,
    required String totalWritten,
    required String estimatedEnd,
    required int linesWritten,
    required String soferName,
    required DateTime today,
    required String Function(DateTime) formatDate,
    bool english = false,
  }) {
    final lines = <String>[
      if (!english) ...['בס"ד', ''],
      english ? 'Hello,' : 'שלום וברכה,',
      '',
      english
          ? 'Here is a progress update for the project "${project.name}", as of ${formatDate(today)}:'
          : 'להלן עדכון על התקדמות העבודה בפרויקט "${project.name}", נכון לתאריך ${formatDate(today)}:',
      '',
    ];

    // A percentage needs a whole to be a fraction of, and only a sefer whose
    // length is known has one. Quoting one without is inventing a denominator.
    final totalPages = project.totalPages;
    if (project.type.isPaged && totalPages != null) {
      final linesPerPage = ProductionCalculator.linesPerPageOf(project);
      final totalLines = totalPages * linesPerPage;
      lines.add(english
          ? '• Written so far: $totalWritten (of $totalPages pages)'
          : '• נכתב עד כה: $totalWritten (מתוך $totalPages עמודים)');
      if (totalLines > 0) {
        final realProgress = (linesWritten / totalLines).clamp(0.0, 1.0);
        final percent =
            MegillahFormat.displayedProgress(project, realProgress) * 100;
        lines.add(english
            ? '• Progress: ${percent.toStringAsFixed(0)}%'
            : '• התקדמות: ${percent.toStringAsFixed(0)}%');
      }
    } else {
      lines.add(english
          ? '• Written so far: $totalWritten'
          : '• נכתב עד כה: $totalWritten');
    }

    if (estimatedEnd.isNotEmpty) {
      lines.add(english
          ? '• Estimated completion: $estimatedEnd'
          : '• צפי סיום משוער: $estimatedEnd');
    }
    final target = project.targetCompletionDate;
    if (target != null) {
      lines.add(english
          ? '• Agreed target date: ${formatDate(target)}'
          : '• תאריך יעד מוסכם: ${formatDate(target)}');
    }

    lines.addAll([
      '',
      english
          ? 'Please feel free to contact me with any questions.'
          : 'אשמח לעמוד לרשותכם בכל שאלה.',
      '',
      english ? 'Best regards,' : 'בברכה,',
    ]);
    // Unset in settings, and signing with an empty line is worse than not
    // signing: it reads as a name that failed to print.
    if (soferName.isNotEmpty) lines.add(soferName);

    return lines.join('\n');
  }
}
