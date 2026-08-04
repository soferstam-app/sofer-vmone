// The plan as a file that leaves the app.
//
// What each cell says is settled in plan_table_test; here the question is only
// whether the rendering produces a real file. A PDF that will not open, or a
// workbook Excel refuses, fails on the writer's desk rather than here — and
// Hebrew in a PDF is the usual way it happens, because a viewer cannot be
// assumed to have a font and an unembedded one comes out as empty boxes.

import 'package:flutter_test/flutter_test.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/hebrew_work_calendar.dart';
import 'package:sofer_vmone/logic/plan_table.dart';
import 'package:sofer_vmone/logic/production_plan.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/plan/plan_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final project = Project(
    id: 'p',
    name: 'ספר תורה למשפחת כהן',
    type: ProjectType.sefer,
    price: 100,
    expenses: 0,
    targetDaily: 1,
    targetMonthly: 20,
    linesPerPage: 10,
  );

  PlanTable table() {
    final first = JewishDate.initDate(
            jewishYear: 5786, jewishMonth: JewishDate.IYAR, jewishDayOfMonth: 1)
        .getGregorianCalendar();
    return PlanTable.of(
      project: project,
      plan: ProductionPlan.forMonth(
        project: project,
        history: const [],
        anyDayInMonth: first,
        rules: WorkCalendarRules.standard,
        dayStart: DayStart.midnight,
        now: first,
      ),
      periodLabel: 'אייר תשפ״ו',
      useGregorianDates: false,
    );
  }

  group('as a PDF', () {
    test('produces a real document', () async {
      final bytes = await PlanExport.toPdf(table());
      // Every PDF begins with this. Anything else is not one.
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(2000));
    });

    test('carries a font with it', () async {
      // Hebrew without an embedded font prints as empty boxes, and the writer
      // finds out at the printer.
      final bytes = await PlanExport.toPdf(table());
      final text = String.fromCharCodes(bytes);
      expect(text, contains('FontFile2'),
          reason: 'no embedded font in the document');
    });

    test('twice over, without the cached fonts breaking the second', () async {
      await PlanExport.toPdf(table());
      final again = await PlanExport.toPdf(table());
      expect(String.fromCharCodes(again.take(5)), '%PDF-');
    });
  });

  group('as a workbook', () {
    test('produces a real xlsx', () async {
      final bytes = await PlanExport.toXlsx(table());
      // An xlsx is a zip, and a zip begins with PK.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
      expect(bytes.length, greaterThan(1000));
    });
  });

  group('the file name', () {
    test('says what the file is', () {
      final name = PlanExport.fileName(table(), 'pdf');
      expect(name, contains('ספר תורה למשפחת כהן'));
      expect(name, endsWith('.pdf'));
    });

    test('carries nothing a filesystem will refuse', () {
      final awkward = Project(
        id: 'p',
        name: 'ספר: א/ב "מיוחד"',
        type: ProjectType.sefer,
        price: 1,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 1,
        linesPerPage: 10,
      );
      final t = PlanTable(
        title: awkward.name,
        headings: const [],
        rows: const [],
        summary: '',
      );
      final name = PlanExport.fileName(t, 'xlsx');
      for (final bad in r'\/:*?"<>|'.split('')) {
        expect(name, isNot(contains(bad)), reason: 'kept $bad');
      }
    });
  });
}
