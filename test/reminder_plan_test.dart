// What a reminder should say, and when it should arrive.
//
// All of it is decided when the reminder is booked, never when it fires:
// zonedSchedule hands the notification to the operating system and no Dart runs
// at the moment it appears. So today's reminder can be specific — the app knows
// this minute how much is left — and the days after it cannot be, and must say
// something true of any day rather than a guess that will be stale on arrival.

import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/logic/hebrew_clock.dart';
import 'package:sofer_vmone/logic/reminder_plan.dart';
import 'package:sofer_vmone/models.dart';

void main() {
  const dayStart = DayStart.midnight;
  final today = DateTime(2026, 7, 20);
  var seq = 0;

  Project project({
    int targetDaily = 2,
    bool inLines = false,
    String id = 'p',
  }) =>
      Project(
        id: id,
        name: 'ספר',
        type: ProjectType.sefer,
        price: 100,
        expenses: 0,
        targetDaily: targetDaily,
        targetMonthly: 40,
        dailyGoalInLines: inLines,
        linesPerPage: 10,
      );

  WorkSession sitting({
    required int hour,
    int lines = 10,
    DateTime? day,
    Duration took = const Duration(hours: 1),
    bool timeRecorded = true,
    bool backlog = false,
    bool deleted = false,
    String projectId = 'p',
  }) {
    final d = day ?? today;
    final start = DateTime(d.year, d.month, d.day, hour);
    return WorkSession(
      id: 'w${seq++}',
      projectId: projectId,
      startTime: start,
      endTime: start.add(timeRecorded ? took : Duration.zero),
      amount: 1,
      startLine: 1,
      endLine: lines,
      description: '',
      isManual: true,
      timeRecorded: timeRecorded,
      backlogOnly: backlog,
      deletedAt: deleted ? DateTime(2026, 8) : null,
      linesPerPageAtEntry: 10,
    );
  }

  group('the hour a writer usually begins', () {
    test('is the one he sits down at most often', () {
      // Not the hour he writes fastest — a different question. A nudge at eight
      // in the evening is no use to someone who has always finished by noon.
      final history = [
        for (var i = 0; i < 5; i++)
          sitting(hour: 6, day: DateTime(2026, 7, i + 1)),
        for (var i = 0; i < 2; i++)
          sitting(hour: 21, day: DateTime(2026, 7, i + 1)),
      ];
      expect(ReminderPlan.usualStartHour(history, dayStart), 6);
    });

    test('is nothing at all until there is a pattern', () {
      // A habit guessed from three sittings is not a habit, and a reminder at
      // the wrong hour is worse than one at a dull hour he chose himself.
      final history = [for (var i = 0; i < 3; i++) sitting(hour: 6)];
      expect(ReminderPlan.usualStartHour(history, dayStart), isNull);
    });

    test('ignores records that say nothing about when he works', () {
      final history = [
        for (var i = 0; i < 5; i++) sitting(hour: 6, timeRecorded: false),
        for (var i = 0; i < 5; i++) sitting(hour: 7, backlog: true),
        for (var i = 0; i < 5; i++) sitting(hour: 8, deleted: true),
        for (var i = 0; i < 5; i++)
          sitting(hour: 9, took: const Duration(minutes: 1)),
      ];
      expect(ReminderPlan.usualStartHour(history, dayStart), isNull);
    });

    test('a tie goes to the earlier hour', () {
      // One that comes too early can still be acted on; one that comes too
      // late cannot.
      final history = [
        for (var i = 0; i < 4; i++) sitting(hour: 7),
        for (var i = 0; i < 4; i++) sitting(hour: 20),
      ];
      expect(ReminderPlan.usualStartHour(history, dayStart), 7);
    });
  });

  group('which hour is booked', () {
    test('the one he set, when he has not asked for anything cleverer', () {
      final history = [for (var i = 0; i < 8; i++) sitting(hour: 6)];
      expect(
        ReminderPlan.hourFor(
            smart: false, chosenHour: 20, history: history, dayStart: dayStart),
        20,
      );
    });

    test('his own habit when he has', () {
      final history = [for (var i = 0; i < 8; i++) sitting(hour: 6)];
      expect(
        ReminderPlan.hourFor(
            smart: true, chosenHour: 20, history: history, dayStart: dayStart),
        6,
      );
    });

    test('and falls back to his choice when there is no habit yet', () {
      // Always a real answer, never no reminder at all.
      expect(
        ReminderPlan.hourFor(
            smart: true, chosenHour: 20, history: const [], dayStart: dayStart),
        20,
      );
    });
  });

  group('what the reminder for today says', () {
    String message(List<WorkSession> history, {Project? p}) =>
        ReminderPlan.todaysMessage(
          project: p ?? project(),
          history: history,
          day: today,
          dayStart: dayStart,
        );

    test('names what is left when some has been done', () {
      // A target of two pages is twenty lines; ten written leaves ten.
      expect(message([sitting(hour: 9, lines: 10)]), contains('10'));
      expect(message([sitting(hour: 9, lines: 10)]), contains('שורות'));
    });

    test('does not say "10 left" to someone who has not started', () {
      // Wrong-footed rather than wrong: it reads as though he is nearly there.
      expect(message(const []), 'עוד לא נרשמה כתיבה היום. מתחילים?');
    });

    test('says something plain when there is no goal to speak of', () {
      expect(message(const [], p: project(targetDaily: 0)),
          ReminderPlan.generalMessage);
    });

    test('and when the goal is already met', () {
      // The caller drops today's reminder outright in that case; this is the
      // belt to that pair of braces.
      expect(
          message([sitting(hour: 9, lines: 10), sitting(hour: 12, lines: 10)]),
          ReminderPlan.generalMessage);
    });

    test('the general message presumes nothing about the day', () {
      // What it replaced asked "did you meet your daily target?" of writers who
      // had met it hours earlier, and of writers who had never set one.
      expect(ReminderPlan.generalMessage, isNot(contains('יעד')));
    });
  });

  group('which commission it speaks about', () {
    test('the one worked on most recently', () {
      // A writer with three open jobs is not helped by being told about the one
      // he has not touched in a month.
      final projects = [project(id: 'a'), project(id: 'b')];
      final history = [
        sitting(hour: 9, projectId: 'a', day: DateTime(2026, 6, 1)),
        sitting(hour: 9, projectId: 'b', day: DateTime(2026, 7, 18)),
      ];
      expect(ReminderPlan.mostRecent(projects, history)!.id, 'b');
    });

    test('nothing at all before any work is recorded', () {
      expect(ReminderPlan.mostRecent([project()], const []), isNull);
    });

    test('and nothing when the commission has since been deleted', () {
      final deleted = Project(
        id: 'p',
        name: 'ספר',
        type: ProjectType.sefer,
        price: 1,
        expenses: 0,
        targetDaily: 1,
        targetMonthly: 1,
        deletedAt: DateTime(2026),
      );
      expect(ReminderPlan.mostRecent([deleted], [sitting(hour: 9)]), isNull);
    });
  });

  group('whether to send at all', () {
    test('not once the day has been met', () {
      expect(
        ReminderPlan.isWorthSending(
          project: project(),
          history: [sitting(hour: 9, lines: 10), sitting(hour: 12, lines: 10)],
          day: today,
          dayStart: dayStart,
        ),
        isFalse,
      );
    });

    test('yes while it has not', () {
      expect(
        ReminderPlan.isWorthSending(
          project: project(),
          history: [sitting(hour: 9, lines: 5)],
          day: today,
          dayStart: dayStart,
        ),
        isTrue,
      );
    });

    test('and yes when there is no goal, since nothing can be met', () {
      expect(
        ReminderPlan.isWorthSending(
          project: project(targetDaily: 0),
          history: const [],
          day: today,
          dayStart: dayStart,
        ),
        isTrue,
      );
    });
  });
}
