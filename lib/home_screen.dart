import 'dart:async';
import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'projects_screen.dart';
import 'storage_service.dart';
import 'package:kosher_dart/kosher_dart.dart';
import 'summary_screen.dart';
import 'expenses_screen.dart';
import 'sync_service.dart';
import 'notification_service.dart';
import 'hebrew_utils.dart';

class SoferHome extends StatefulWidget {
  const SoferHome({super.key, this.windowsFloatingMode});

  final ValueNotifier<bool>? windowsFloatingMode;

  @override
  State<SoferHome> createState() => _SoferHomeState();
}

class _SoferHomeState extends State<SoferHome>
    with SingleTickerProviderStateMixin {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  DateTime? _timerStartTime;
  DateTime? _timerEndTime;
  final Stopwatch _breakStopwatch = Stopwatch();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isPaused = false;
  bool _isSmartWorkflow = false;
  Duration _lastLapTime = Duration.zero;

  List<Project> projects = [];
  List<WorkSession> history = [];
  Duration _lastSessionTime = Duration.zero;
  final StorageService _storageService = StorageService();

  Project? _selectedProject;
  final _pageCtrl = TextEditingController();
  final _lineFromCtrl = TextEditingController();
  final _lineToCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _mezuzaLineCtrl = TextEditingController();

  DateTime? _manualDate;
  TimeOfDay _manualStartTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _manualEndTime = const TimeOfDay(hour: 10, minute: 0);
  bool _manualIncludeTime = true;

  String _tefillinMode = 'set';
  String _tefillinPartType = 'head';
  int _tefillinParshiyaIndex = 1;

  int _smartCurrentPage = 0;
  int _smartCurrentLine = 0;
  int _smartStartPage = 0;
  int _smartStartLine = 0;

  int _dayRolloverHour = 0;
  bool _useGregorianDates = false;

  void _onWindowsFloatingModeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.windowsFloatingMode?.addListener(_onWindowsFloatingModeChanged);
    SyncService.instance.init().then((_) {
      SyncService.instance.syncData().then((_) => _loadData());
    });
    _storageService.getDayRolloverHour().then((h) {
      if (mounted) setState(() => _dayRolloverHour = h);
    });
    _storageService.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    NotificationService().scheduleDailyReminder();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadData();
    _initAutoUpdater();
  }

  @override
  void didUpdateWidget(covariant SoferHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.windowsFloatingMode != widget.windowsFloatingMode) {
      oldWidget.windowsFloatingMode
          ?.removeListener(_onWindowsFloatingModeChanged);
      widget.windowsFloatingMode?.addListener(_onWindowsFloatingModeChanged);
    }
  }

  DateTime _effectiveDate(DateTime now) {
    if (now.hour < _dayRolloverHour) {
      return DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
    }
    return DateTime(now.year, now.month, now.day);
  }

  void _initAutoUpdater() async {
    if (Platform.isWindows || Platform.isMacOS) {
      String feedURL =
          'https://github.com/soferstam-app/sofer-vmone/releases/tag/APP';
      await autoUpdater.setFeedURL(feedURL);
    }
  }

  @override
  void dispose() {
    widget.windowsFloatingMode?.removeListener(_onWindowsFloatingModeChanged);
    _pulseController.dispose();
    _timer?.cancel();
    _pageCtrl.dispose();
    _lineFromCtrl.dispose();
    _lineToCtrl.dispose();
    _amountCtrl.dispose();
    _mezuzaLineCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final loadedProjects = await _storageService.loadProjects();
      var activeProjects = loadedProjects.where((p) => !p.isDeleted).toList();
      activeProjects = activeProjects.toSet().toList();

      final loadedHistory = await _storageService.loadHistory();
      final activeHistory = loadedHistory.where((h) => !h.isDeleted).toList();
      final smartEnabled = await _storageService.getSmartWorkflowEnabled();
      if (!mounted) return;
      setState(() {
        projects = activeProjects;
        history = activeHistory;
        _isSmartWorkflow = smartEnabled;
      });
    } catch (e) {
      debugPrint("Error loading data: $e");
    }
  }

  Future<void> _testConnection() async {
    try {
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('https://netfree.link/'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close();

      if (!mounted) return;
      if (response.statusCode == 200) {
        _showSuccess(context, "החיבור הצליח! תעודת האבטחה נטענה כראוי.");
      } else {
        _showError(context, "התקבל קוד שגיאה מהשרת: ${response.statusCode}");
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint("Connection test failed: $e");
      _showError(context,
          "שגיאת חיבור: וודא שאתה מחובר לאינטרנט ושתוכן התעודה תקין.\n($e)");
    }
  }

  String _getDisplayDate(DateTime date) {
    return formatDisplayDate(date, _useGregorianDates);
  }

  void _startTimer() {
    setState(() {
      _isPaused = false;
      if (!_stopwatch.isRunning) {
        _stopwatch.start();
        if (_breakStopwatch.isRunning) {
          _breakStopwatch.stop();
          _breakStopwatch.reset();
        }
        _pulseController.repeat(reverse: true);
        _timerStartTime ??= DateTime.now();
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  void _pauseTimer() {
    setState(() {
      _stopwatch.stop();
      _timer?.cancel();
      _pulseController.stop();
      _pulseController.value = 1.0;
      _isPaused = true;
      _breakStopwatch.start();
    });
  }

  void _stopTimer() {
    setState(() {
      _stopwatch.stop();
      _timer?.cancel();
      _pulseController.stop();
      _pulseController.value = 1.0;
      _breakStopwatch.stop();
      _breakStopwatch.reset();
      _isPaused = false;
      _timerEndTime = DateTime.now();
      _lastSessionTime = _stopwatch.elapsed;
      _stopwatch.reset();
      _lastLapTime = Duration.zero;

      if (_isSmartWorkflow) {
        _finishSmartSession();
      } else {
        _openEntryDialog(isManual: false);
      }
      _timerStartTime = null;
    });
  }

  void _recordLap() {
    final currentElapsed = _stopwatch.elapsed;
    final lapDuration = currentElapsed - _lastLapTime;
    _lastLapTime = currentElapsed;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("סיימתי שורה! זמן שורה: ${_formatTime(lapDuration)}"),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.blueGrey,
      ),
    );
  }

  Future<void> _initSmartSession() async {
    if (_selectedProject == null) return;

    final lastPos = await _storageService.getLastPosition(_selectedProject!.id);
    setState(() {
      if (lastPos.isNotEmpty) {
        _smartCurrentPage = lastPos['page'];
        _smartCurrentLine = lastPos['line'];
      } else {
        _smartCurrentPage = 1;
        _smartCurrentLine = 1;
      }
      _smartStartPage = _smartCurrentPage;
      _smartStartLine = _smartCurrentLine;
    });

    _startTimer();
  }

  void _smartNextLine() {
    _recordLap();

    setState(() {
      _smartCurrentLine++;

      if (_selectedProject?.type == ProjectType.mezuza) {
        if (_smartCurrentLine > 22) {
          _smartCurrentLine = 1;
          _smartCurrentPage++; // Move to the next mezuza
        }
      } else {
        int linesPerPage = _selectedProject!.linesPerPage ?? 42;
        if (linesPerPage == 0) linesPerPage = 42;

        if (_smartCurrentLine > linesPerPage) {
          _smartCurrentLine = 1;
          _smartCurrentPage++;
        }
      }
    });

    _storageService.saveLastPosition(
        _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);
  }

  Future<void> _showEditPositionDialog() async {
    if (_selectedProject == null) return;
    final isMezuza = _selectedProject!.type == ProjectType.mezuza;
    final pageCtrl = TextEditingController(
        text: isMezuza
            ? _smartCurrentPage.toString()
            : formatHebrewNumber(_smartCurrentPage));
    final lineCtrl = TextEditingController(text: _smartCurrentLine.toString());
    final maxLines = isMezuza ? 22 : (_selectedProject!.linesPerPage ?? 42);
    final maxPages = isMezuza ? 999 : (_selectedProject!.totalPages ?? 245);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("עריכת מיקום בפרויקט"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pageCtrl,
              decoration: InputDecoration(
                labelText: isMezuza ? "מזוזה מספר" : "עמוד",
                hintText: isMezuza ? "1-$maxPages" : "אותיות (למשל: יא)",
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lineCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "שורה",
                hintText: "1-$maxLines",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("ביטול")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("שמור")),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final page = isMezuza
        ? (int.tryParse(pageCtrl.text) ?? _smartCurrentPage)
        : parseHebrewPageToNumber(pageCtrl.text);
    final line = int.tryParse(lineCtrl.text) ?? _smartCurrentLine;
    final p = (page <= 0 ? _smartCurrentPage : page).clamp(1, maxPages);
    final l = line.clamp(1, maxLines);
    setState(() {
      _smartCurrentPage = p;
      _smartCurrentLine = l;
      if (!_stopwatch.isRunning && !_isPaused) {
        _smartStartPage = p;
        _smartStartLine = l;
      }
    });
    await _storageService.saveLastPosition(_selectedProject!.id, p, l);
  }

  void _finishSmartSession() {
    if (_selectedProject == null) return;

    // --- Logic for Mezuza Projects ---
    if (_selectedProject!.type == ProjectType.mezuza) {
      const int linesPerMezuza = 22;

      int finalMezuza = _smartCurrentPage;
      int finalLine = _smartCurrentLine - 1;

      if (finalLine < 1) {
        if (finalMezuza > _smartStartPage) {
          finalMezuza--;
          finalLine = linesPerMezuza;
        } else {
          finalLine = _smartStartLine - 1; // No progress
        }
      }

      if (finalMezuza < _smartStartPage ||
          (finalMezuza == _smartStartPage && finalLine < _smartStartLine)) {
        _showError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      int totalLinesWritten = 0;
      if (finalMezuza == _smartStartPage) {
        totalLinesWritten = finalLine - _smartStartLine + 1;
      } else {
        // Lines in the first mezuza
        totalLinesWritten += (linesPerMezuza - _smartStartLine + 1);
        // Lines in full mezuzot between start and final
        totalLinesWritten +=
            (finalMezuza - _smartStartPage - 1) * linesPerMezuza;
        // Lines in the final mezuza
        totalLinesWritten += finalLine;
      }

      if (totalLinesWritten <= 0) {
        _showError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      int numFullMezuzot = totalLinesWritten ~/ linesPerMezuza;
      int remainingLines = totalLinesWritten % linesPerMezuza;

      List<WorkSession> newSessions = [];
      if (numFullMezuzot > 0) {
        newSessions.add(WorkSession(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          projectId: _selectedProject!.id,
          startTime: DateTime.now(), // Placeholder
          endTime: DateTime.now(), // Placeholder
          amount: numFullMezuzot,
          startLine: 0,
          endLine: 0,
          description: "$numFullMezuzot מזוזות",
          isManual: false,
        ));
      }

      if (remainingLines > 0) {
        newSessions.add(WorkSession(
          id: "${DateTime.now().millisecondsSinceEpoch}_p",
          projectId: _selectedProject!.id,
          startTime: DateTime.now(), // Placeholder
          endTime: DateTime.now(), // Placeholder
          amount: 1,
          startLine: 1, // Assumption for partial
          endLine: remainingLines,
          description: "מזוזה (עד שורה $remainingLines)",
          isManual: false,
        ));
      }
      // --- Time Distribution ---
      DateTime sessionEnd = DateTime.now();
      Duration totalNetTime = _lastSessionTime;
      double msPerLine = totalNetTime.inMilliseconds / totalLinesWritten;
      DateTime tempEndTime = sessionEnd;

      for (int i = newSessions.length - 1; i >= 0; i--) {
        WorkSession s = newSessions[i];
        int linesInThisSession =
            (s.endLine > 0) ? s.endLine : s.amount * linesPerMezuza;

        Duration partDuration =
            Duration(milliseconds: (msPerLine * linesInThisSession).round());
        DateTime partStartTime = tempEndTime.subtract(partDuration);

        newSessions[i] = WorkSession(
            id: s.id,
            projectId: s.projectId,
            startTime: partStartTime,
            endTime: tempEndTime,
            amount: s.amount,
            startLine: s.startLine,
            endLine: s.endLine,
            description: s.description,
            isManual: s.isManual);
        tempEndTime = partStartTime;
      }

      setState(() => history.addAll(newSessions));
      _storageService.saveHistory(history);
      _storageService.saveLastPosition(
          _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);
      SyncService.instance.syncData();

      _showSuccess(
          context, "הסשן נשמר בהצלחה! סה\"כ נכתבו $totalLinesWritten שורות.");
    } else {
      // --- Logic for Sefer Torah Projects ---
      int linesPerPage = _selectedProject!.linesPerPage ?? 42;
      if (linesPerPage == 0) linesPerPage = 42;

      int finalPage = _smartCurrentPage;
      int finalLine = _smartCurrentLine - 1;

      if (finalLine < 1) {
        if (finalPage > _smartStartPage) {
          finalPage--;
          finalLine = linesPerPage;
        } else {
          finalLine = _smartStartLine - 1;
        }
      }

      if (finalPage < _smartStartPage ||
          (finalPage == _smartStartPage && finalLine < _smartStartLine)) {
        _showError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      List<WorkSession> newSessions = [];
      int totalLinesWritten = 0;

      for (int p = _smartStartPage; p <= finalPage; p++) {
        int start = (p == _smartStartPage) ? _smartStartLine : 1;
        int end = (p == finalPage) ? finalLine : linesPerPage;

        if (end >= start) {
          int linesInThisPage = end - start + 1;
          totalLinesWritten += linesInThisPage;

          newSessions.add(WorkSession(
            id: "${DateTime.now().millisecondsSinceEpoch}_$p",
            projectId: _selectedProject!.id,
            startTime: DateTime.now(),
            endTime: DateTime.now(),
            amount: p,
            startLine: start,
            endLine: end,
            description: "כתיבה רציפה (עמוד ${formatHebrewNumber(p)})",
            isManual: false,
          ));
        }
      }

      if (totalLinesWritten == 0) {
        _showError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      DateTime sessionEnd = DateTime.now();
      Duration totalNetTime = _lastSessionTime;
      double msPerLine = totalNetTime.inMilliseconds / totalLinesWritten;
      DateTime tempEndTime = sessionEnd;

      for (int i = newSessions.length - 1; i >= 0; i--) {
        WorkSession s = newSessions[i];
        int linesInThisSession = s.endLine - s.startLine + 1;
        Duration partDuration =
            Duration(milliseconds: (msPerLine * linesInThisSession).round());

        DateTime partStartTime = tempEndTime.subtract(partDuration);

        newSessions[i] = WorkSession(
            id: s.id,
            projectId: s.projectId,
            startTime: partStartTime,
            endTime: tempEndTime,
            amount: s.amount,
            startLine: s.startLine,
            endLine: s.endLine,
            description: s.description,
            isManual: s.isManual);

        tempEndTime = partStartTime;
      }

      setState(() => history.addAll(newSessions));
      _storageService.saveHistory(history);
      _storageService.saveLastPosition(
          _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);
      SyncService.instance.syncData();

      _showSuccess(
          context, "הסשן נשמר בהצלחה! נכתבו $totalLinesWritten שורות.");
    }
  }

  void _openEntryDialog({required bool isManual}) {
    _selectedProject = null;
    _pageCtrl.clear();
    _lineFromCtrl.clear();
    _lineToCtrl.clear();
    _amountCtrl.clear();
    _mezuzaLineCtrl.clear();
    _manualDate = _effectiveDate(DateTime.now());
    _manualStartTime = const TimeOfDay(hour: 9, minute: 0);
    _manualEndTime = const TimeOfDay(hour: 10, minute: 0);
    _manualIncludeTime = true;
    _tefillinMode = 'set';
    _tefillinPartType = 'head';
    _tefillinParshiyaIndex = 1;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isManual ? "הזנה ידנית" : "סיכום כתיבה"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isManual)
                      Text(
                        "זמן עבודה: ${_formatTime(_lastSessionTime)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    else
                      _buildManualTimePicker(setDialogState),
                    const SizedBox(height: 15),
                    if (projects.isEmpty)
                      const Text(
                        "אין פרויקטים. לחץ על 'פרויקטים' בתחתית כדי להוסיף.",
                        style: TextStyle(color: Colors.red),
                      )
                    else
                      DropdownButton<Project>(
                        hint: const Text("בחר פרויקט"),
                        value: _selectedProject,
                        isExpanded: true,
                        items: projects
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(p.name),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() => _selectedProject = val);
                        },
                      ),
                    const SizedBox(height: 10),
                    if (_selectedProject != null)
                      _buildDynamicForm(_selectedProject!, setDialogState),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "מחיקה / ביטול",
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton(
                  onPressed: _selectedProject == null
                      ? null
                      : () async {
                          if (await _validateAndSave(context, isManual)) {
                            if (!context.mounted) return;
                            _pageCtrl.clear();
                            _lineFromCtrl.clear();
                            _lineToCtrl.clear();
                            _amountCtrl.clear();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "נוסף! ניתן להזין עוד נתונים לאותו זמן.",
                                ),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                  child: const Text("הוסף"),
                ),
                ElevatedButton(
                  onPressed: _selectedProject == null
                      ? null
                      : () async {
                          if (!context.mounted) return;
                          final messenger = ScaffoldMessenger.of(context);

                          if (await _validateAndSave(context, isManual)) {
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text("הנתונים נשמרו בהצלחה!"),
                              ),
                            );
                          }
                        },
                  child: const Text("אישור וסגירה"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildManualTimePicker(StateSetter setDialogState) {
    String durationText = "";
    if (_manualIncludeTime) {
      final now = DateTime.now();
      DateTime start = DateTime(now.year, now.month, now.day,
          _manualStartTime.hour, _manualStartTime.minute);
      DateTime end = DateTime(now.year, now.month, now.day, _manualEndTime.hour,
          _manualEndTime.minute);
      if (end.isBefore(start)) {
        end = end.add(const Duration(days: 1));
      }
      Duration d = end.difference(start);
      durationText =
          "סה\"כ זמן מחושב: ${d.inHours} שעות ו-${d.inMinutes % 60} דקות";
    }

    return Column(
      children: [
        SwitchListTile(
          title: const Text("חישוב זמן כתיבה"),
          value: _manualIncludeTime,
          onChanged: (val) {
            setDialogState(() => _manualIncludeTime = val);
          },
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
        if (_manualIncludeTime)
          Row(
            children: [
              const Text("התחלה: "),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _manualStartTime,
                  );
                  if (t != null) {
                    setDialogState(() => _manualStartTime = t);
                  }
                },
                child: Text(_manualStartTime.format(context)),
              ),
              const Spacer(),
              const Text("סיום: "),
              TextButton(
                onPressed: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _manualEndTime,
                  );
                  if (t != null) {
                    setDialogState(() => _manualEndTime = t);
                  }
                },
                child: Text(_manualEndTime.format(context)),
              ),
            ],
          ),
        Text(
          durationText,
          style: const TextStyle(
              fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text("תאריך: "),
            TextButton(
              onPressed: () async {
                await _showHebrewDatePickerDialog(setDialogState);
              },
              child: Text(
                _manualDate == null
                    ? "ללא תאריך (כללי)"
                    : _getDisplayDate(_manualDate!),
              ),
            ),
            if (_manualDate != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setDialogState(() => _manualDate = null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _showHebrewDatePickerDialog(StateSetter setParentState) async {
    DateTime currentGregorian = _manualDate ?? DateTime.now();
    JewishDate jewishDate = JewishDate.fromDateTime(currentGregorian);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            int currentYear = jewishDate.getJewishYear();
            int currentMonth = jewishDate.getJewishMonth();
            int currentDay = jewishDate.getJewishDayOfMonth();
            bool isLeap = jewishDate.isJewishLeapYear();
            int daysInMonth = jewishDate.getDaysInJewishMonth();

            List<int> years = List.generate(21, (i) => (currentYear - 10) + i);

            List<int> months;
            if (isLeap) {
              months = [7, 8, 9, 10, 11, 12, 13, 1, 2, 3, 4, 5, 6];
            } else {
              months = [7, 8, 9, 10, 11, 12, 1, 2, 3, 4, 5, 6];
            }

            List<int> days = List.generate(daysInMonth, (i) => i + 1);

            return AlertDialog(
              title: const Text("בחר תאריך עברי"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<int>(
                    value: years.contains(currentYear) ? currentYear : years[0],
                    items: years.map((y) {
                      return DropdownMenuItem(
                        value: y,
                        child: Text(formatHebrewYear(y)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        JewishDate temp = JewishDate();
                        temp.setJewishDate(val, 1, 1);
                        bool newIsLeap = temp.isJewishLeapYear();

                        int newMonth = currentMonth;
                        if (!newIsLeap && currentMonth == 13) {
                          newMonth = 12;
                        }

                        temp.setJewishDate(val, newMonth, 1);
                        int maxDays = temp.getDaysInJewishMonth();
                        int newDay =
                            currentDay > maxDays ? maxDays : currentDay;

                        jewishDate.setJewishDate(val, newMonth, newDay);
                        setState(() {});
                      }
                    },
                  ),
                  DropdownButton<int>(
                    value: months.contains(currentMonth) ? currentMonth : 1,
                    items: months.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(getHebrewMonthName(m, isLeap)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        jewishDate.setJewishDate(currentYear, val, 1);
                        int maxDays = jewishDate.getDaysInJewishMonth();
                        int newDay =
                            currentDay > maxDays ? maxDays : currentDay;

                        jewishDate.setJewishDate(currentYear, val, newDay);
                        setState(() {});
                      }
                    },
                  ),
                  DropdownButton<int>(
                    value: days.contains(currentDay) ? currentDay : 1,
                    items: days.map((d) {
                      return DropdownMenuItem(
                        value: d,
                        child: Text(formatHebrewNumber(d)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        jewishDate.setJewishDate(
                          currentYear,
                          currentMonth,
                          val,
                        );
                        setState(() {});
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("ביטול"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setParentState(() {
                      _manualDate = jewishDate.getGregorianCalendar();
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("בחר"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDynamicForm(Project p, StateSetter setDialogState) {
    if (p.type == ProjectType.sefer) {
      return Column(
        children: [
          TextField(
            controller: _pageCtrl,
            decoration: const InputDecoration(
              labelText: "עמוד (למשל: יא)",
              prefixIcon: Icon(Icons.auto_stories),
              hintText: "אותיות או מספרים",
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lineFromCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "משורה",
                    prefixIcon: Icon(Icons.vertical_align_top),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _lineToCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "עד שורה",
                    prefixIcon: Icon(Icons.vertical_align_bottom),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    } else if (p.type == ProjectType.mezuza) {
      return Column(
        children: [
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "כמות מזוזות",
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mezuzaLineCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "עד שורה (אופציונלי)",
              prefixIcon: Icon(Icons.format_align_left),
              hintText: "השאר ריק למזוזה שלמה",
            ),
          ),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<String>(
            value: _tefillinMode,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'set', child: Text("סט שלם (ראש+יד)")),
              DropdownMenuItem(
                value: 'head',
                child: Text("תפילין של ראש (4 פרשיות)"),
              ),
              DropdownMenuItem(
                value: 'hand',
                child: Text("תפילין של יד (4 פרשיות)"),
              ),
              DropdownMenuItem(
                value: 'parshiya',
                child: Text("פרשייה בודדת (ראש/יד)"),
              ),
            ],
            onChanged: (v) => setDialogState(() => _tefillinMode = v!),
          ),
          const SizedBox(height: 10),
          if (_tefillinMode == 'parshiya') ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _tefillinPartType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'head',
                        child: Text("תפילין של ראש"),
                      ),
                      DropdownMenuItem(
                        value: 'hand',
                        child: Text("תפילין של יד"),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => _tefillinPartType = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<int>(
                    value: _tefillinParshiyaIndex,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text("1. קדש")),
                      DropdownMenuItem(
                        value: 2,
                        child: Text("2. והיה כי יביאך"),
                      ),
                      DropdownMenuItem(value: 3, child: Text("3. שמע")),
                      DropdownMenuItem(
                        value: 4,
                        child: Text("4. והיה אם שמוע"),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => _tefillinParshiyaIndex = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _mezuzaLineCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "עד שורה (השאר ריק לפרשייה מלאה)",
                prefixIcon: const Icon(Icons.format_align_left),
                hintText:
                    _tefillinPartType == 'head' ? "עד 4 שורות" : "עד 7 שורות",
              ),
            ),
          ] else ...[
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "כמות יחידות",
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
          ],
        ],
      );
    }
  }

  Future<bool> _validateAndSave(
    BuildContext dialogContext,
    bool isManual,
  ) async {
    DateTime sessionStart;
    DateTime sessionEnd;

    if (isManual) {
      final date = _manualDate ?? DateTime.now();
      if (_manualIncludeTime) {
        sessionStart = DateTime(
          date.year,
          date.month,
          date.day,
          _manualStartTime.hour,
          _manualStartTime.minute,
        );
        sessionEnd = DateTime(
          date.year,
          date.month,
          date.day,
          _manualEndTime.hour,
          _manualEndTime.minute,
        );
        if (sessionEnd.isBefore(sessionStart)) {
          sessionEnd = sessionEnd.add(
            const Duration(days: 1),
          );
        }
      } else {
        sessionStart = DateTime(date.year, date.month, date.day, 12, 0);
        sessionEnd = sessionStart;
      }
    } else {
      sessionEnd = _timerEndTime ?? DateTime.now();
      sessionStart = sessionEnd.subtract(_lastSessionTime);
    }

    if (_selectedProject == null) return false;

    int amount = 0;
    int startLine = 0;
    int endLine = 0;
    String desc = "";
    String? tefillinType;
    int? parshiya;

    if (_selectedProject!.type == ProjectType.sefer) {
      String pageInput = _pageCtrl.text.trim();
      int pageNum =
          int.tryParse(pageInput) ?? parseHebrewPageToNumber(pageInput);
      startLine = int.tryParse(_lineFromCtrl.text) ?? 0;
      endLine = int.tryParse(_lineToCtrl.text) ?? 0;

      if (pageNum == 0 || startLine == 0 || endLine == 0) {
        _showError(dialogContext, "יש להזין עמוד ושורות תקינים");
        return false;
      }
      if (_selectedProject!.totalPages != null &&
          pageNum > _selectedProject!.totalPages!) {
        _showError(
          dialogContext,
          "מספר העמוד חורג מהגדרת הספר (${_selectedProject!.totalPages})",
        );
        return false;
      }
      if (_selectedProject!.linesPerPage != null &&
          (startLine > _selectedProject!.linesPerPage! ||
              endLine > _selectedProject!.linesPerPage!)) {
        _showError(
          dialogContext,
          "מספר השורות חורג מהגדרת העמוד (${_selectedProject!.linesPerPage})",
        );
        return false;
      }
      if (startLine > endLine) {
        _showError(dialogContext, "שורה התחלה חייבת להיות קטנה משורה סיום");
        return false;
      }

      bool hasOverlap = _checkOverlap(
        _selectedProject!.id,
        pageNum,
        startLine,
        endLine,
      );
      if (hasOverlap) {
        bool confirm = await showDialog(
              context: dialogContext,
              builder: (c) => AlertDialog(
                title: const Text("שים לב: כפילות"),
                content: const Text(
                  "חלק מהשורות בעמוד זה כבר נכתבו בעבר. האם לשמור בכל זאת?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text("ביטול"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text("שמור בכל זאת"),
                  ),
                ],
              ),
            ) ??
            false;
        if (!confirm) return false;
      }

      amount = pageNum;
      desc = "עמוד ${formatHebrewNumber(pageNum)} ($startLine-$endLine)";
    } else {
      if (_selectedProject!.type == ProjectType.tefillin &&
          _tefillinMode == 'parshiya') {
        amount = 1;
        endLine = int.tryParse(_mezuzaLineCtrl.text) ?? 0;

        tefillinType = _tefillinPartType;
        parshiya = _tefillinParshiyaIndex;

        int maxLines = _tefillinPartType == 'head' ? 4 : 7;
        if (endLine > maxLines) {
          _showError(
            dialogContext,
            "בתפילין ${_tefillinPartType == 'head' ? 'של ראש' : 'של יד'} יש עד $maxLines שורות",
          );
          return false;
        }

        String part = _tefillinPartType == 'head' ? "ראש" : "יד";
        String parshiyaName = "";
        switch (_tefillinParshiyaIndex) {
          case 1:
            parshiyaName = "קדש";
            break;
          case 2:
            parshiyaName = "והיה כי יביאך";
            break;
          case 3:
            parshiyaName = "שמע";
            break;
          case 4:
            parshiyaName = "והיה אם שמוע";
            break;
        }
        desc = "פרשיית $parshiyaName של $part";
        if (endLine > 0) desc += " (עד שורה $endLine)";
      } else {
        amount = int.tryParse(_amountCtrl.text) ?? 0;
        if (amount == 0) {
          _showError(dialogContext, "יש להזין כמות");
          return false;
        }

        if (_selectedProject!.type == ProjectType.mezuza) {
          int line = int.tryParse(_mezuzaLineCtrl.text) ?? 0;
          if (line > 22) {
            _showError(dialogContext, "במזוזה יש רק 22 שורות");
            return false;
          }
          endLine = line;
          if (line > 0) {
            desc = "$amount מזוזות (עד שורה $line)";
          } else {
            desc = "$amount מזוזות";
          }
        } else {
          if (_tefillinMode == 'set') {
            desc = "$amount סטים של תפילין";
          } else if (_tefillinMode == 'head') {
            desc = "$amount תפילין של ראש";
            tefillinType = 'head';
          } else if (_tefillinMode == 'hand') {
            desc = "$amount תפילין של יד";
            tefillinType = 'hand';
          } else {
            desc = "$amount יחידות";
          }
        }
      }
    }

    setState(() {
      history.add(
        WorkSession(
          id: DateTime.now().toString(),
          projectId: _selectedProject!.id,
          startTime: sessionStart,
          endTime: sessionEnd,
          amount: amount,
          startLine: startLine,
          endLine: endLine,
          tefillinType: tefillinType,
          parshiya: parshiya,
          description: desc,
          isManual: isManual,
        ),
      );
      _storageService.saveHistory(history);
    });

    SyncService.instance.syncData();

    if (Platform.isAndroid && _checkDailyGoalMet(_selectedProject!)) {
      NotificationService().cancelDailyReminder();
    }

    return true;
  }

  bool _checkOverlap(String projId, int page, int start, int end) {
    for (var session in history) {
      if (session.projectId == projId && session.amount == page) {
        if (start <= session.endLine && end >= session.startLine) {
          return true;
        }
      }
    }
    return false;
  }

  bool _checkDailyGoalMet(Project project) {
    if (project.targetDaily <= 0) return true;

    final now = DateTime.now();
    final todaySessions = history
        .where((s) =>
            s.projectId == project.id &&
            s.startTime.year == now.year &&
            s.startTime.month == now.month &&
            s.startTime.day == now.day)
        .toList();

    int totalDone = 0;
    for (var s in todaySessions) {
      if (project.type == ProjectType.sefer) {
        int linesPerPage = project.linesPerPage ?? 42;
        totalDone += (s.endLine - s.startLine + 1);
        if (totalDone >= project.targetDaily * linesPerPage) return true;
      } else {
        totalDone += s.amount;
      }
    }
    return totalDone >= project.targetDaily;
  }

  void _showSuccess(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.red)),
      ),
    );
  }

  String _formatTime(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void _resetAllData() async {
    await _storageService.saveProjects([]);
    await _storageService.saveHistory([]);
    if (!mounted) return;
    setState(() {
      projects = [];
      history = [];
    });
  }

  void _navigateToProjects() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectsScreen(
          projects: projects,
          onProjectAdded: (p) {
            setState(() => projects.add(p));
            _storageService.saveProjects(projects);
            SyncService.instance.syncData();
          },
          onProjectUpdated: (p) {
            setState(() {
              if (p.isDeleted) {
                projects.removeWhere((element) => element.id == p.id);
                history.removeWhere((session) => session.projectId == p.id);
              } else {
                int index =
                    projects.indexWhere((element) => element.id == p.id);
                if (index != -1) projects[index] = p;
              }
            });
            _storageService.saveProjects(projects);
            SyncService.instance.syncData();
          },
          onProjectDeleted: (p) {
            setState(() {
              projects.removeWhere((element) => element.id == p.id);
              history.removeWhere((session) => session.projectId == p.id);
            });
            _storageService.saveProjects(projects);
            SyncService.instance.syncData();
          },
          onResetAllData: _resetAllData,
        ),
      ),
    );
  }

  Future<void> _refreshSettingsFromStorage() async {
    final smartEnabled = await _storageService.getSmartWorkflowEnabled();
    final rollover = await _storageService.getDayRolloverHour();
    final useGregorian = await _storageService.getUseGregorianDates();
    if (!mounted) return;
    setState(() {
      _isSmartWorkflow = smartEnabled;
      _dayRolloverHour = rollover;
      _useGregorianDates = useGregorian;
    });
  }

  void _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
    await _refreshSettingsFromStorage();
  }

  void _navigateToSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryScreen(
          projects: projects,
          history: history,
          onHistoryUpdated: (updatedHistory) {
            setState(() => history = updatedHistory);
            _storageService.saveHistory(history);
            SyncService.instance.syncData();
          },
          useGregorianDates: _useGregorianDates,
        ),
      ),
    );
  }

  Future<void> _restoreFromFloatingWindow() async {
    if (!Platform.isWindows || widget.windowsFloatingMode == null) return;
    widget.windowsFloatingMode!.value = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setSize(const Size(1280, 720));
    await windowManager.center();
  }

  Widget _buildWindowsFloatingOverlay() {
    return Material(
      color: Colors.deepPurple.shade900,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(_stopwatch.elapsed),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w200,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: _isPaused ? _startTimer : _pauseTimer,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    tooltip: _isPaused ? "המשך" : "הפסקה",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _stopTimer,
                    icon: const Icon(Icons.stop),
                    tooltip: "סיום",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!_isPaused)
                    IconButton.filled(
                      onPressed: _recordLap,
                      icon: const Icon(Icons.flag),
                      tooltip: "Lap",
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _restoreFromFloatingWindow,
                    icon: const Icon(Icons.open_in_full),
                    tooltip: "החזר חלון",
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows && (widget.windowsFloatingMode?.value ?? false)) {
      return _buildWindowsFloatingOverlay();
    }
    if (_isSmartWorkflow) {
      return _buildSmartWorkflowUI();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FF),
      appBar: AppBar(
        title: const Text('סופר ומונה'),
        centerTitle: true,
        actions: [
          if (Platform.isWindows)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 22),
                label: const Text("חלון צף"),
                onPressed: () async {
                  await windowManager.setSize(const Size(320, 260));
                  await windowManager.setAlwaysOnTop(true);
                  await windowManager.setAlignment(Alignment.bottomRight);
                  widget.windowsFloatingMode?.value = true;
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.network_check),
            onPressed: _testConnection,
            tooltip: "בדוק חיבור נטפרי",
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today,
                              color: Colors.deepPurple.shade300, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            _getDisplayDate(_effectiveDate(DateTime.now())),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.deepPurple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: FadeTransition(
                            opacity: _pulseAnimation,
                            child: Text(
                              _formatTime(_stopwatch.elapsed),
                              style: const TextStyle(
                                  fontSize: 80, fontWeight: FontWeight.w200),
                            ),
                          ),
                        ),
                      ),
                      if (_stopwatch.isRunning && !_isPaused)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: FadeTransition(
                            opacity: _pulseAnimation,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5E6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.brown.shade300,
                                        width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.brown.withOpacity(0.2),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.brush,
                                          color: Colors.brown.shade800,
                                          size: 26),
                                      const SizedBox(width: 8),
                                      Text("כותב...",
                                          style: TextStyle(
                                              color: Colors.brown.shade800,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (!_stopwatch.isRunning && !_isPaused)
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.92, end: 1.0),
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutBack,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: child,
                            );
                          },
                          child: ElevatedButton.icon(
                            onPressed: _startTimer,
                            icon: const Icon(Icons.play_arrow, size: 28),
                            label: const Text("תחילת כתיבה"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[400],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 50, vertical: 25),
                              textStyle: const TextStyle(fontSize: 20),
                            ),
                          ),
                        )
                      else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed:
                                      _isPaused ? _startTimer : _pauseTimer,
                                  icon: Icon(_isPaused
                                      ? Icons.play_arrow
                                      : Icons.coffee),
                                  label: Text(_isPaused ? "המשך" : "הפסקת קפה"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[300],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 15),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                ElevatedButton.icon(
                                  onPressed: _stopTimer,
                                  icon: const Icon(Icons.stop),
                                  label: const Text("סיום ושמירה"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[400],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 15),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            if (!_isPaused)
                              OutlinedButton.icon(
                                onPressed: _recordLap,
                                icon: const Icon(Icons.flag),
                                label: const Text("סיימתי שורה (Lap)"),
                              ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      if (!_stopwatch.isRunning && !_isPaused)
                        OutlinedButton.icon(
                          onPressed: () => _openEntryDialog(isManual: true),
                          icon: const Icon(Icons.edit_calendar),
                          label: const Text("הוספת כתיבה ידנית (ללא טיימר)"),
                        ),
                      const SizedBox(height: 12),
                      if (history.isNotEmpty)
                        Text(
                          "נשמרו ${history.length} רשומות בסשן זה",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      IconButton(
                        icon: const Icon(Icons.coffee),
                        tooltip: "תרום לפיתוח האפליקציה",
                        onPressed: () => launchUrl(
                            Uri.parse('https://buymeacoffee.com/soferstam')),
                        style: IconButton.styleFrom(
                          foregroundColor: Colors.brown.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.deepPurple.shade50,
        selectedItemColor: Colors.deepPurple.shade800,
        unselectedItemColor: Colors.grey.shade700,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: "סיכומים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: "פרויקטים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: "הוצאות",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: "הגדרות",
          ),
        ],
        onTap: (index) {
          if (index == 0) _navigateToSummary();
          if (index == 1) _navigateToProjects();
          if (index == 2) _navigateToExpenses();
          if (index == 3) _navigateToSettings();
        },
      ),
    );
  }

  void _navigateToExpenses() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ExpensesScreen(),
      ),
    );
  }

  Widget _buildSmartWorkflowUI() {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FF),
      appBar: AppBar(
        title: const Text('סופר ומונה - מצב חכם'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_stopwatch.isRunning && !_isPaused)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: DropdownButtonFormField<Project>(
                    decoration: const InputDecoration(
                      labelText: "בחר פרויקט להתחלת עבודה",
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _selectedProject,
                    items: projects
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p.name)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedProject = val),
                  ),
                ),
              if (_selectedProject != null) ...[
                if (_stopwatch.isRunning || _isPaused)
                  Column(
                    children: [
                      Text(
                        _selectedProject?.type == ProjectType.mezuza
                            ? "מזוזה ${formatHebrewNumber(_smartCurrentPage)}"
                            : "עמוד ${formatHebrewNumber(_smartCurrentPage)}",
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "שורה $_smartCurrentLine",
                        style: const TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showEditPositionDialog,
                        icon: const Icon(Icons.edit_location_alt, size: 20),
                        label: const Text("ערוך מיקום"),
                      ),
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FutureBuilder<Map<String, dynamic>>(
                        future: _storageService
                            .getLastPosition(_selectedProject!.id),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            final unitLabel =
                                _selectedProject?.type == ProjectType.mezuza
                                    ? "מזוזה"
                                    : "עמוד";
                            return Text(
                                "מיקום אחרון: $unitLabel ${formatHebrewNumber(snapshot.data!['page'])}, שורה ${snapshot.data!['line']}");
                          }
                          return const Text("התחלה חדשה בפרויקט זה");
                        },
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _showEditPositionDialog,
                        icon: const Icon(Icons.edit_location_alt, size: 20),
                        label: const Text("ערוך מיקום"),
                      ),
                    ],
                  ),
                const SizedBox(height: 30),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: FadeTransition(
                    opacity: _pulseAnimation,
                    child: Text(
                      _formatTime(_stopwatch.elapsed),
                      style: const TextStyle(
                          fontSize: 80, fontWeight: FontWeight.w200),
                    ),
                  ),
                ),
                if (_stopwatch.isRunning && !_isPaused)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FadeTransition(
                      opacity: _pulseAnimation,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5E6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.brown.shade300, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.brown.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.brush,
                                    color: Colors.brown.shade800, size: 26),
                                const SizedBox(width: 8),
                                Text("כותב...",
                                    style: TextStyle(
                                        color: Colors.brown.shade800,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isPaused)
                  Text(
                    "בהפסקה: ${_formatTime(_breakStopwatch.elapsed)}",
                    style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  )
                else if (_stopwatch.isRunning)
                  Text(
                    "זמן שורה נוכחית: ${_formatTime(_stopwatch.elapsed - _lastLapTime)}",
                    style:
                        const TextStyle(fontSize: 18, color: Colors.blueGrey),
                  ),
                const SizedBox(height: 40),
                if (!_stopwatch.isRunning && !_isPaused)
                  ElevatedButton.icon(
                    onPressed: _initSmartSession,
                    icon: const Icon(Icons.login),
                    label: const Text("כניסה (התחל כתיבה)"),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 20),
                      textStyle: const TextStyle(fontSize: 20),
                    ),
                  )
                else
                  Column(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isPaused ? null : _smartNextLine,
                        icon: const Icon(Icons.arrow_downward),
                        label: const Text("מעבר שורה (סיימתי)"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 60, vertical: 25),
                          textStyle: const TextStyle(fontSize: 22),
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isPaused ? _startTimer : _pauseTimer,
                            icon: Icon(
                                _isPaused ? Icons.play_arrow : Icons.coffee),
                            label:
                                Text(_isPaused ? "חזרה לכתיבה" : "הפסקת קפה"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            onPressed: _stopTimer,
                            icon: const Icon(Icons.logout),
                            label: const Text("יציאה (סיכום)"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.deepPurple.shade50,
        selectedItemColor: Colors.deepPurple.shade800,
        unselectedItemColor: Colors.grey.shade700,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: "סיכומים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: "פרויקטים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: "הוצאות",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: "הגדרות",
          ),
        ],
        onTap: (index) {
          if (index == 0) _navigateToSummary();
          if (index == 1) _navigateToProjects();
          if (index == 2) _navigateToExpenses();
          if (index == 3) _navigateToSettings();
        },
      ),
    );
  }
}
