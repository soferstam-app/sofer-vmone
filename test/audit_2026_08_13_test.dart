// The six findings from the 13.08.2026 audit that were fixed before release.
//
// Each test is the auditor's own reproduction, kept so the fix cannot quietly
// come undone. Where the audit reported a number, that number is asserted.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/logic/annual_report.dart';
import 'package:sofer_vmone/logic/currency.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/measured_work.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/onboarding/onboarding_screen.dart';
import 'package:sofer_vmone/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Currency has no `usd` constant -- only ils is named, the rest are built
  // from their code, which is the point of the class.
  const usd = Currency('USD');

  Project project({Currency currency = Currency.ils}) => Project(
        id: 'p1',
        name: 'ספר תורה',
        type: ProjectType.sefer,
        price: 40000,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 20,
        linesPerPage: 42,
        totalPages: 245,
        currency: currency,
      );

  group('P1-01 — the annual report must see recorded payments', () {
    test('a payment of 1,234 reaches the year it was received in', () {
      final report = AnnualReport.forYear(
        year: 2026,
        projects: [project()],
        history: const [],
        expenses: const [],
        payments: [
          Payment(
            id: 'pay1',
            projectId: 'p1',
            amount: 1234,
            currency: Currency.ils,
            receivedAt: DateTime(2026, 3, 4),
          ),
        ],
        dayStart: DayStart.midnight,
      );

      expect(report.income.single(Currency.ils)!.amount, 1234);
    });
  });

  group('P1-12 — one currency must not read as more than one', () {
    test('an expense in dollars and no income at all still nets', () {
      // The empty side used to become zero in the *default* currency and then
      // disagree with the side that had data, so the screen said "more than
      // one currency" about a year that held exactly one.
      final report = AnnualReport.forYear(
        year: 2026,
        projects: [project(currency: usd)],
        history: const [],
        expenses: [
          Expense(
            id: 'e1',
            product: 'קלף',
            amount: 90,
            currency: usd,
            date: DateTime(2026, 5, 2),
          ),
        ],
        dayStart: DayStart.midnight,
      );

      final net = report.net(Currency.ils);
      expect(net, isNotNull, reason: 'only dollars were recorded');
      expect(net!.currency, usd);
      expect(net.amount, -90);
    });

    test('income in dollars and no expenses, the other way round', () {
      final report = AnnualReport.forYear(
        year: 2026,
        projects: [project(currency: usd)],
        history: const [],
        expenses: const [],
        payments: [
          Payment(
            id: 'pay1',
            projectId: 'p1',
            amount: 500,
            currency: usd,
            receivedAt: DateTime(2026, 6, 1),
          ),
        ],
        dayStart: DayStart.midnight,
      );

      final net = report.net(Currency.ils);
      expect(net, isNotNull);
      expect(net!.currency, usd);
      expect(net.amount, 500);
    });

    test('two real currencies still refuse to net', () {
      final report = AnnualReport.forYear(
        year: 2026,
        projects: [project()],
        history: const [],
        expenses: [
          Expense(
              id: 'e1',
              product: 'קלף',
              amount: 90,
              currency: usd,
              date: DateTime(2026, 5, 2)),
        ],
        payments: [
          Payment(
              id: 'pay1',
              projectId: 'p1',
              amount: 500,
              currency: Currency.ils,
              receivedAt: DateTime(2026, 6, 1)),
        ],
        dayStart: DayStart.midnight,
      );

      expect(report.net(Currency.ils), isNull,
          reason: 'there genuinely is no single number here');
    });

    test('an empty year is zero in whatever was asked for', () {
      final report = AnnualReport.forYear(
        year: 2026,
        projects: [project()],
        history: const [],
        expenses: const [],
        dayStart: DayStart.midnight,
      );
      expect(report.net(Currency.ils)!.amount, 0);
    });
  });

  group('P1-10 — a negative duration must not shrink an honest hour', () {
    test('MeasuredWork drops it rather than subtracting it', () {
      // The audit's case: a good hour plus an imported record of minus thirty
      // minutes was displayed as thirty minutes.
      final good = WorkSession(
        id: 's1',
        projectId: 'p1',
        startTime: DateTime(2026, 8, 1, 9),
        endTime: DateTime(2026, 8, 1, 10),
        amount: 1,
        startLine: 1,
        endLine: 42,
        linesPerPageAtEntry: 42,
        description: '',
        isManual: true,
        workingDateAtEntry: DateTime(2026, 8, 1),
      );
      final corrupt = WorkSession(
        id: 's2',
        projectId: 'p1',
        startTime: DateTime(2026, 8, 2, 10),
        endTime: DateTime(2026, 8, 2, 9, 30),
        amount: 1,
        startLine: 1,
        endLine: 42,
        linesPerPageAtEntry: 42,
        description: '',
        isManual: true,
        workingDateAtEntry: DateTime(2026, 8, 2),
      );

      expect(corrupt.duration.isNegative, isTrue, reason: 'sanity');
      expect(MeasuredWork.time([good, corrupt]), const Duration(hours: 1));
      expect(MeasuredWork.only([good, corrupt]).length, 1);
    });
  });

  group('P2-06 — the last button must do what it says', () {
    Widget harness({required bool fromSettings}) => MaterialApp(
          theme: AppThemeBuilder.build(AppTheme.klaf),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: OnboardingScreen(
              fromSettings: fromSettings,
              onDone: ({required createProject}) {},
            ),
          ),
        );

    Future<void> toLastPage(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('הבא'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('on a first launch it offers to open a project',
        (tester) async {
      await tester.pumpWidget(harness(fromSettings: false));
      await toLastPage(tester);
      expect(find.text('פתיחת פרויקט ראשון'), findsOneWidget);
    });

    testWidgets('opened from settings it just closes', (tester) async {
      // He already has projects; offering to open his first one and then
      // returning him to settings reads as a press that did nothing.
      await tester.pumpWidget(harness(fromSettings: true));
      await toLastPage(tester);
      expect(find.text('פתיחת פרויקט ראשון'), findsNothing);
      expect(find.text('סיום'), findsOneWidget);
    });
  });
}
