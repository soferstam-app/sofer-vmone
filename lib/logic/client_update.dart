import '../models.dart';
import 'production_calculator.dart';

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
  }) {
    final lines = <String>[
      'בס"ד',
      '',
      'שלום וברכה,',
      '',
      'להלן עדכון על התקדמות העבודה בפרויקט "${project.name}", '
          'נכון לתאריך ${formatDate(today)}:',
      '',
    ];

    // A percentage needs a whole to be a fraction of, and only a sefer whose
    // length is known has one. Quoting one without is inventing a denominator.
    final totalPages = project.totalPages;
    if (project.type == ProjectType.sefer && totalPages != null) {
      final linesPerPage = ProductionCalculator.linesPerPageOf(project);
      final totalLines = totalPages * linesPerPage;
      lines.add('• נכתב עד כה: $totalWritten (מתוך $totalPages עמודים)');
      if (totalLines > 0) {
        final percent = (linesWritten / totalLines * 100).clamp(0, 100);
        lines.add('• התקדמות: ${percent.toStringAsFixed(0)}%');
      }
    } else {
      lines.add('• נכתב עד כה: $totalWritten');
    }

    if (estimatedEnd.isNotEmpty) {
      lines.add('• צפי סיום משוער: $estimatedEnd');
    }
    final target = project.targetCompletionDate;
    if (target != null) {
      lines.add('• תאריך יעד מוסכם: ${formatDate(target)}');
    }

    lines.addAll([
      '',
      'אשמח לעמוד לרשותכם בכל שאלה.',
      '',
      'בברכה,',
    ]);
    // Unset in settings, and signing with an empty line is worse than not
    // signing: it reads as a name that failed to print.
    if (soferName.isNotEmpty) lines.add(soferName);

    return lines.join('\n');
  }
}
