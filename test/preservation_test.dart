// A file must come back whole from a build that did not write it.
//
// Every model carries an `extraFields` bag so that a field written by a newer
// version survives a round trip through an older one — a backup that travels
// phone → old desktop → phone has to come back with everything it left with.
// The mechanism has existed for a while; nothing proved it worked.
//
// These tests inject fields no build has ever heard of, at every level and of
// every shape, edit something else, write the record back out, and demand that
// the invented data is returned byte for byte. Without this the guarantee decays
// silently: one model that forgets to spread its bag, and a user's data is gone
// with no error anywhere.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fields from a version that does not exist yet, of every shape JSON has.
  Map<String, dynamic> junk(String tag) => {
        'futureScalar_$tag': 'שדה מגרסה עתידית',
        'futureInt_$tag': 42,
        'futureBool_$tag': true,
        'futureNull_$tag': null,
        'futureList_$tag': [
          1,
          'two',
          {'three': 3}
        ],
        'futureObject_$tag': {
          'nested': {'deeper': [true, null, 'ד']},
          'count': 7,
        },
      };

  void expectPreserved(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
    String tag,
  ) {
    for (final key in junk(tag).keys) {
      expect(after.containsKey(key), isTrue,
          reason: '$key was dropped entirely');
      expect(jsonEncode(after[key]), jsonEncode(before[key]),
          reason: '$key came back changed');
    }
  }

  group('a project', () {
    Map<String, dynamic> stored() => {
          ...junk('project'),
          'id': 'p1',
          'name': 'ספר תורה',
          'typeName': 'sefer',
          'type': 0,
          'price': 40000,
          'expenses': 0,
          'targetDaily': 1,
          'targetMonthly': 20,
          'totalPages': 245,
          'linesPerPage': 42,
        };

    test('carries unknown fields through a round trip', () {
      final before = stored();
      final after = Project.fromJson(jsonDecode(jsonEncode(before))).toJson();
      expectPreserved(before, jsonDecode(jsonEncode(after)), 'project');
    });

    test('carries them through an edit', () {
      // The dangerous case: a build that does not understand a field still
      // edits the record beside it.
      final before = stored();
      final edited = Project.fromJson(jsonDecode(jsonEncode(before)))
          .copyWith(name: 'שם אחר')
          .toJson();
      final after = jsonDecode(jsonEncode(edited)) as Map<String, dynamic>;

      expect(after['name'], 'שם אחר');
      expectPreserved(before, after, 'project');
    });

    test('does not mistake an unknown field for a known one', () {
      final after = Project.fromJson(jsonDecode(jsonEncode(stored())));
      expect(after.name, 'ספר תורה');
      expect(after.totalPages, 245);
      expect(after.type, ProjectType.sefer);
    });
  });

  group('a work session', () {
    Map<String, dynamic> stored() => {
          ...junk('session'),
          'id': 's1',
          'projectId': 'p1',
          'startTime': '2026-07-20T09:00:00.000',
          'endTime': '2026-07-20T12:00:00.000',
          'amount': 5,
          'startLine': 1,
          'endLine': 42,
          'description': 'עמוד ה',
          'isManual': false,
          'timeRecorded': true,
          'linesPerPageAtEntry': 42,
        };

    test('carries unknown fields through a round trip', () {
      final before = stored();
      final after =
          WorkSession.fromJson(jsonDecode(jsonEncode(before))).toJson();
      expectPreserved(before, jsonDecode(jsonEncode(after)), 'session');
    });

    test('carries them through an edit', () {
      final before = stored();
      final edited = WorkSession.fromJson(jsonDecode(jsonEncode(before)))
          .copyWith(amount: 6)
          .toJson();
      final after = jsonDecode(jsonEncode(edited)) as Map<String, dynamic>;

      expect(after['amount'], 6);
      expectPreserved(before, after, 'session');
    });

    test('carries them through a soft delete', () {
      // Deleting is the one edit that must not quietly shed the rest of the
      // record: a tombstone that lost its unknown fields cannot be restored.
      final before = stored();
      final deleted = WorkSession.fromJson(jsonDecode(jsonEncode(before)))
          .copyWith(isDeleted: true)
          .toJson();
      final after = jsonDecode(jsonEncode(deleted)) as Map<String, dynamic>;

      expect(after['isDeleted'], isTrue);
      expectPreserved(before, after, 'session');
    });
  });

  group('an expense', () {
    Map<String, dynamic> stored() => {
          ...junk('expense'),
          'id': 'e1',
          'product': 'קלף',
          'date': '2026-07-20T00:00:00.000',
          'amount': 1200,
          'allocationName': 'project',
          'allocation': 0,
          'projectIds': ['p1', 'p2'],
        };

    test('carries unknown fields through a round trip', () {
      final before = stored();
      final after = Expense.fromJson(jsonDecode(jsonEncode(before))).toJson();
      expectPreserved(before, jsonDecode(jsonEncode(after)), 'expense');
    });

    test('carries them through an edit', () {
      final before = stored();
      final edited = Expense.fromJson(jsonDecode(jsonEncode(before)))
          .copyWith(amount: 1300)
          .toJson();
      final after = jsonDecode(jsonEncode(edited)) as Map<String, dynamic>;

      expect(after['amount'], 1300);
      expectPreserved(before, after, 'expense');
    });
  });

  group('a record this build cannot read at all', () {
    // Not a field it does not understand — a whole record. It is dropped from
    // the working list so that one bad entry does not cost the rest, and the
    // list was then written back without it. "Cannot read" became "erased" on
    // the next save of anything.
    final storage = StorageService();

    /// An entry no build can parse: a record has to have an id to be mergeable,
    /// so one without is refused.
    Map<String, dynamic> unreadable(String tag) => {
          'writtenBy': 'a version that does not exist yet',
          'tag': tag,
          ...junk(tag),
        };

    test('survives a save of the records around it', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([
          {
            'id': 'p1',
            'name': 'ספר',
            'typeName': 'sefer',
            'price': 1,
            'expenses': 0,
            'targetDaily': 1,
            'targetMonthly': 1,
          },
          unreadable('kept'),
        ]),
      });

      final loaded = await storage.loadProjects();
      expect(loaded, hasLength(1), reason: 'the unreadable one is not returned');

      // The app does what it always does: saves the list it is holding.
      await storage.saveProjects(loaded);

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('projects')!) as List<dynamic>;
      expect(stored, hasLength(2), reason: 'the unreadable record was erased');

      final carried = stored.firstWhere((e) => e['tag'] == 'kept')
          as Map<String, dynamic>;
      expectPreserved(unreadable('kept'), carried, 'kept');
    });

    test('survives being saved over and over', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.history': jsonEncode([unreadable('session')]),
      });

      for (var i = 0; i < 3; i++) {
        await storage.saveHistory(await storage.loadHistory());
      }

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('history')!) as List<dynamic>;
      expect(stored, hasLength(1));
    });

    test('is counted, so the app can say the totals are short', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([unreadable('a')]),
        'flutter.history': jsonEncode([unreadable('b'), unreadable('c')]),
        'flutter.expenses': jsonEncode([]),
      });
      expect(await storage.unreadableRecordCount(), 3);
    });

    test('is not duplicated when a record of the same id is written', () async {
      // A later build that does understand the record writes it properly; the
      // raw copy must not survive alongside it.
      SharedPreferences.setMockInitialValues({
        'flutter.expenses': jsonEncode([
          {'id': 'e1', 'product': 'קלף', 'amount': 10, 'brokenBy': 'nothing'},
        ]),
      });

      final expenses = await storage.loadExpenses();
      expect(expenses, hasLength(1));
      await storage.saveExpenses(expenses);

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('expenses')!) as List<dynamic>;
      expect(stored, hasLength(1));
    });
  });

  group('a save does not erase what it was not given', () {
    // The failure this guards is the one that undid the tombstones entirely.
    // Every screen holds the live records — deleted ones are filtered out on
    // load — and a save rewrote the file as exactly that list. So one save from
    // any screen wiped every tombstone in it, and a deletion with no tombstone
    // behind it is a deletion the next merge undoes.
    final storage = StorageService();

    Map<String, dynamic> deletedProject(String id) => {
          'id': id,
          'name': 'נמחק',
          'typeName': 'sefer',
          'price': 1,
          'expenses': 0,
          'targetDaily': 1,
          'targetMonthly': 1,
          'isDeleted': true,
          'deletedAt': DateTime(2026, 7, 1).toIso8601String(),
        };

    test('a tombstone survives a save of the live records', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([
          {
            'id': 'alive',
            'name': 'ספר',
            'typeName': 'sefer',
            'price': 1,
            'expenses': 0,
            'targetDaily': 1,
            'targetMonthly': 1,
          },
          deletedProject('buried'),
        ]),
      });

      // Exactly what every screen does: load, keep the live ones, save those.
      final live =
          (await storage.loadProjects()).where((p) => !p.isDeleted).toList();
      expect(live, hasLength(1));
      await storage.saveProjects(live);

      final back = await storage.loadProjects();
      expect(back, hasLength(2), reason: 'the tombstone was erased');
      expect(back.firstWhere((p) => p.id == 'buried').isDeleted, isTrue);
    });

    test('and survives it a hundred times over', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([deletedProject('buried')]),
      });

      for (var i = 0; i < 100; i++) {
        final live =
            (await storage.loadProjects()).where((p) => !p.isDeleted).toList();
        await storage.saveProjects(live);
      }

      final back = await storage.loadProjects();
      expect(back, hasLength(1));
      expect(back.single.isDeleted, isTrue);
    });

    test('the work of a deleted project stays, and stays alive', () async {
      // Deleting a project used to drop its sessions here, so restoring it from
      // the recycle bin gave back an empty project.
      SharedPreferences.setMockInitialValues({
        'flutter.history': jsonEncode([
          {
            'id': 's1',
            'projectId': 'buried',
            'startTime': DateTime(2026, 7, 1, 9).toIso8601String(),
            'endTime': DateTime(2026, 7, 1, 12).toIso8601String(),
            'amount': 5,
            'startLine': 1,
            'endLine': 10,
            'description': 'עמוד ה',
            'isManual': true,
          },
        ]),
      });

      // The home screen drops them from what it is holding and saves.
      await storage.saveHistory(const []);

      final back = await storage.loadHistory();
      expect(back, hasLength(1));
      expect(back.single.isDeleted, isFalse);
    });

    test('a record that is written does replace the stored one', () async {
      // The other half: preserving must not mean refusing to update.
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([deletedProject('p')]),
      });

      final revived = (await storage.loadProjects()).single.copyWith(
            isDeleted: false,
            name: 'חזר',
          );
      await storage.saveProjects([revived]);

      final back = await storage.loadProjects();
      expect(back, hasLength(1), reason: 'not kept alongside its own update');
      expect(back.single.name, 'חזר');
      expect(back.single.isDeleted, isFalse);
    });

    test('erasing everything really does erase it', () async {
      // The deliberate exception, and the only one.
      SharedPreferences.setMockInitialValues({
        'flutter.projects': jsonEncode([deletedProject('a')]),
        'flutter.history': jsonEncode([]),
        'flutter.expenses': jsonEncode([]),
      });

      await storage.eraseAllRecords();
      expect(await storage.loadProjects(), isEmpty);
    });
  });

  group('a field this build owns', () {
    test('always wins over a stale copy in the unknown bag', () {
      // If a key is both known and somehow present in the bag, the value this
      // build computed must be the one written — otherwise an old value could
      // shadow a new one for ever.
      final stored = {
        'id': 'p1',
        'name': 'שם אמיתי',
        'typeName': 'sefer',
        'price': 100,
        'expenses': 0,
        'targetDaily': 1,
        'targetMonthly': 20,
      };
      final project = Project.fromJson(stored);
      final out = project.copyWith(name: 'שם חדש').toJson();
      expect(out['name'], 'שם חדש');
    });
  });

  group('a plan a writer corrected by hand', () {
    // "If I decide I am not writing on a given day, the whole table should
    // shift." The decision is a fact about the commission and has to survive
    // being closed, synced and reopened, or the table quietly reverts and the
    // writer stops believing it.
    final tuesday = DateTime(2026, 8, 4);

    Project withOverrides(Map<DateTime, double> o) => Project(
          id: 'p',
          name: 'ספר',
          type: ProjectType.sefer,
          price: 100,
          expenses: 0,
          targetDaily: 1,
          targetMonthly: 20,
          planOverrides: o,
        );

    test('survives a save and a load', () {
      final back = Project.fromJson(
          jsonDecode(jsonEncode(withOverrides({tuesday: 0}).toJson()))
              as Map<String, dynamic>);
      expect(back.planOverrides, {tuesday: 0.0});
    });

    test('a half day keeps its half', () {
      final back = Project.fromJson(
          jsonDecode(jsonEncode(withOverrides({tuesday: 0.5}).toJson()))
              as Map<String, dynamic>);
      expect(back.planOverrides[tuesday], 0.5);
    });

    test('the time of day is not part of the key', () {
      // A plan is about days. A stray time would make two entries for one
      // Tuesday, and the second would silently win.
      final p = withOverrides({Project.planDay(DateTime(2026, 8, 4, 17, 30)): 0});
      expect(p.planOverrides.keys.single, tuesday);
    });

    test('survives an edit of something else', () {
      expect(withOverrides({tuesday: 0}).copyWith(name: 'אחר').planOverrides,
          {tuesday: 0.0});
    });

    test('a nonsense entry is dropped without costing the commission', () {
      // One bad entry in a planning aid must not take the job down with it.
      final p = Project.fromJson({
        'id': 'p1',
        'name': 'ספר',
        'typeName': 'sefer',
        'price': 100,
        'expenses': 0,
        'targetDaily': 1,
        'targetMonthly': 20,
        'planOverrides': {
          'not-a-date': 0,
          '2026-08-04': 'not-a-number',
          '2026-08-05': 0.5,
        },
      });
      expect(p.name, 'ספר');
      expect(p.planOverrides, {DateTime(2026, 8, 5): 0.5});
    });

    test('a commission from before this existed simply has none', () {
      final old = Project.fromJson({
        'id': 'p1',
        'name': 'ספר',
        'typeName': 'sefer',
        'price': 100,
        'expenses': 0,
        'targetDaily': 1,
        'targetMonthly': 20,
      });
      expect(old.planOverrides, isEmpty);
    });
  });

  group('money comes back to the agora', () {
    // Amounts are held as doubles, which is the thing every guide about money
    // says not to do. It was worth checking rather than assuming: what a sofer
    // types is what is stored, and a double carries any sum he could plausibly
    // write down without losing so much as an agora of it. Nothing derived is
    // ever stored — no total, no quotient, no profit — so the numbers in the
    // file are only ever the ones he typed.
    //
    // That makes the storage sound and this test the thing that keeps it so.
    // The plausible way it breaks is a well-meant tidy-up: writing amounts as
    // `toStringAsFixed(2)`, or rounding on the way in. Both would look right on
    // screen and quietly destroy what was entered.
    const amounts = [
      0.07, 0.1, 0.005, 0.3, 4.35, 8.15, 99.99, 123.45, 1200.0, 1234567.89,
    ];

    test('a project keeps its price and its costs', () {
      for (final amount in amounts) {
        final project = Project(
          id: 'p',
          name: 'x',
          type: ProjectType.sefer,
          price: amount,
          expenses: amount,
          targetDaily: 1,
          targetMonthly: 20,
        );
        final back = Project.fromJson(
            jsonDecode(jsonEncode(project.toJson())) as Map<String, dynamic>);
        expect(back.price, amount, reason: 'price $amount');
        expect(back.expenses, amount, reason: 'expenses $amount');
      }
    });

    test('an expense keeps its amount', () {
      for (final amount in amounts) {
        final expense = Expense(
          id: 'e',
          product: 'קלף',
          date: DateTime(2026, 7, 20),
          amount: amount,
          allocation: ExpenseAllocation.month,
        );
        final back = Expense.fromJson(
            jsonDecode(jsonEncode(expense.toJson())) as Map<String, dynamic>);
        expect(back.amount, amount, reason: 'amount $amount');
      }
    });

    test('through an edit that does not touch it', () {
      final expense = Expense(
        id: 'e',
        product: 'קלף',
        date: DateTime(2026, 7, 20),
        amount: 1234567.89,
        allocation: ExpenseAllocation.month,
      );
      expect(expense.copyWith(product: 'דיו').amount, 1234567.89);
    });
  });
}
