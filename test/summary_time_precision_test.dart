import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/models.dart';
import 'package:sofer_vmone/storage_service.dart';
import 'package:sofer_vmone/summary_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => StorageService.demoStore = null);

  testWidgets('daily summary calculates line average with seconds',
      (tester) async {
    tester.view.physicalSize = const Size(900, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final project = Project(
      id: 'p',
      name: 'ספר',
      type: ProjectType.sefer,
      price: 420,
      expenses: 0,
      targetDaily: 0,
      targetMonthly: 0,
      totalPages: 10,
      linesPerPage: 42,
    );
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10);
    final session = WorkSession(
      id: 'line',
      projectId: project.id,
      startTime: start,
      endTime: start.add(const Duration(minutes: 1, seconds: 30)),
      amount: 1,
      startLine: 1,
      endLine: 1,
      description: '',
      isManual: true,
      linesPerPageAtEntry: 42,
    );
    StorageService.demoStore = MemoryStore({
      'projects': jsonEncode([project.toJson()]),
      'history': jsonEncode([session.toJson()]),
    });

    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: SummaryScreen(
          projects: [project],
          history: [session],
          onHistoryUpdated: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1.50 דקות לשורה'), findsOneWidget);
  });
}
