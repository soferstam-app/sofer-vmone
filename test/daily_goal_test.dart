// Whether the day's target has been met.
//
// The app congratulates a writer on reaching their goal and stops nagging them
// for the evening, and this is what decides it. It sat inside the home screen
// reading that screen's fields, so the one question a sofer asks the app every
// evening could only be answered by writing for a day and looking.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/daily_goal.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  final today = DateTime(2026, 7, 20);
  const dayStart = DayStart.midnight;
  var seq = 0;

  Project project({
    ProjectType type = ProjectType.sefer,
    int targetDaily = 2,
    bool inLines = false,
    int linesPerPage = 10,
  }) =>
      Project(
        id: 'p',
        name: 'x',
        type: type,
        price: 100,
        expenses: 0,
        targetDaily: targetDaily,
        targetMonthly: 40,
        dailyGoalInLines: inLines,
        linesPerPage: linesPerPage,
      );

  WorkSession session({
    int amount = 1,
    int startLine = 1,
    int endLine = 10,
    DateTime? at,
    bool backlogOnly = false,
    bool deleted = false,
  }) =>
      WorkSession(
        id: 'w${seq++}',
        projectId: 'p',
        startTime: at ?? today.add(const Duration(hours: 9)),
        endTime: (at ?? today.add(const Duration(hours: 9)))
            .add(const Duration(hours: 1)),
        amount: amount,
        startLine: startLine,
        endLine: endLine,
        description: '',
        isManual: true,
        backlogOnly: backlogOnly,
        deletedAt: deleted ? DateTime(2026, 7, 21) : null,
      );

  bool met(Project p, List<WorkSession> history) => DailyGoal.isMet(
      project: p, history: history, day: today, dayStart: dayStart);

  group('a target set in pages', () {
    test('is counted in lines, because that is what sessions carry', () {
      // Two pages of ten lines is twenty lines, and a session records lines.
      expect(DailyGoal.targetFor(project(targetDaily: 2, linesPerPage: 10)), 20);
    });

    test('is not met by one page of two', () {
      expect(met(project(), [session(amount: 1, startLine: 1, endLine: 10)]),
          isFalse);
    });

    test('is met by two', () {
      expect(
        met(project(), [
          session(amount: 1, startLine: 1, endLine: 10),
          session(amount: 2, startLine: 1, endLine: 10),
        ]),
        isTrue,
      );
    });
  });

  group('a target set in lines', () {
    test('is taken as it stands', () {
      expect(DailyGoal.targetFor(project(targetDaily: 15, inLines: true)), 15);
    });

    test('is met by that many lines, whatever page they were on', () {
      final p = project(targetDaily: 15, inLines: true);
      expect(met(p, [session(startLine: 1, endLine: 10)]), isFalse);
      expect(
        met(p, [
          session(startLine: 1, endLine: 10),
          session(startLine: 1, endLine: 5),
        ]),
        isTrue,
      );
    });
  });

  group('work that does not count towards today', () {
    test('a backlog entry', () {
      // It records writing done before the app existed and carries a
      // placeholder date. For a while it was kept out only by accident.
      final p = project(targetDaily: 1, inLines: true);
      expect(met(p, [session(startLine: 1, endLine: 10, backlogOnly: true)]),
          isFalse);
    });

    test('a deleted record', () {
      final p = project(targetDaily: 1, inLines: true);
      expect(
          met(p, [session(startLine: 1, endLine: 10, deleted: true)]), isFalse);
    });

    test('another day', () {
      final p = project(targetDaily: 1, inLines: true);
      expect(
        met(p, [
          session(
              startLine: 1,
              endLine: 10,
              at: today.subtract(const Duration(days: 1)))
        ]),
        isFalse,
      );
    });

    test('another commission', () {
      final other = session(startLine: 1, endLine: 10);
      expect(
        DailyGoal.doneOn(
            project: Project(
              id: 'other',
              name: 'y',
              type: ProjectType.sefer,
              price: 0,
              expenses: 0,
              targetDaily: 1,
              targetMonthly: 1,
            ),
            history: [other],
            day: today,
            dayStart: dayStart),
        0,
      );
    });
  });

  group('a commission with no target', () {
    test('is always met, because there is nothing to fall short of', () {
      // Reporting a miss against a goal nobody set would be an invention.
      expect(met(project(targetDaily: 0), const []), isTrue);
    });
  });

  group('counted work rather than paginated', () {
    test('counts units, not lines', () {
      final p = project(type: ProjectType.mezuza, targetDaily: 3);
      expect(DailyGoal.targetFor(p), 3, reason: 'no page size to multiply by');
      expect(met(p, [session(amount: 2)]), isFalse);
      expect(met(p, [session(amount: 2), session(amount: 1)]), isTrue);
    });
  });
}
