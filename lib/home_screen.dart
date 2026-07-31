import 'dart:async';
import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'logic/id_generator.dart';
import 'entry/entry_sheet.dart';
import 'format.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/production_calculator.dart';
import 'logic/session_logic.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'projects_screen.dart';
import 'storage_service.dart';
import 'summary_screen.dart';
import 'features_screen.dart';
import 'notification_service.dart';
import 'hebrew_utils.dart';
import 'home/ruled_home_body.dart';
import 'logic/completion_estimator.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/profit_calculator.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';
import 'timer_foreground_task.dart';

class SoferHome extends StatefulWidget {
  const SoferHome({super.key, this.windowsFloatingMode});

  final ValueNotifier<bool>? windowsFloatingMode;

  @override
  State<SoferHome> createState() => _SoferHomeState();
}

class _SoferHomeState extends State<SoferHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  DateTime? _timerStartTime;
  DateTime? _timerEndTime;
  final Stopwatch _breakStopwatch = Stopwatch();
  int _accumulatedElapsedSeconds = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isPaused = false;
  bool _isSmartWorkflow = false;
  Duration _lastLapTime = Duration.zero;

  Duration _effectiveElapsed() {
    final sec = _accumulatedElapsedSeconds +
        (_timerStartTime != null
            ? DateTime.now().difference(_timerStartTime!).inSeconds
            : 0);
    return Duration(seconds: sec);
  }

  List<Project> projects = [];
  List<WorkSession> history = [];
  Duration _lastSessionTime = Duration.zero;
  final StorageService _storageService = StorageService();

  Project? _selectedProject;
  // Pages and lines are counted from one. There is no page 0 and no line 0, so
  // these never start at zero — a zero on screen is always a bug.
  int _smartCurrentPage = 1;
  int _smartCurrentLine = 1;
  int _smartStartPage = 1;
  int _smartStartLine = 1;

  /// Total break duration during current smart session (not counted in writing average).
  Duration _sessionBreakDuration = Duration.zero;

  DayStart _dayStart = DayStart.midnight;
  bool _useGregorianDates = false;

  /// Needed for the completion estimate the ruled home screen shows.
  WorkCalendarRules _workRules = WorkCalendarRules.standard;

  void _onWindowsFloatingModeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.windowsFloatingMode?.addListener(_onWindowsFloatingModeChanged);
    _storageService.getDayStart().then((d) {
      if (mounted) setState(() => _dayStart = d);
    });
    _storageService.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    NotificationService().scheduleDailyReminder();

    if (Platform.isAndroid) _initTimerForegroundService();

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

  DateTime _effectiveDate(DateTime now) =>
      DateLogic.effectiveDate(now, _dayStart);

  /// Freezes onto each session the working day it is being filed under.
  ///
  /// Every path that records work goes through here. The day is settled once,
  /// now, with the boundary the writer has set now — so that changing the
  /// boundary later cannot re-file work that was already counted under a
  /// different reckoning.
  List<WorkSession> _stampWorkingDay(List<WorkSession> sessions) => sessions
      .map((s) => s.workingDateAtEntry != null
          ? s
          : s.copyWith(
              workingDateAtEntry:
                  DateLogic.effectiveDate(s.startTime, _dayStart)))
      .toList();

  void _initAutoUpdater() async {
    if (Platform.isWindows || Platform.isMacOS) {
      String feedURL =
          'https://github.com/soferstam-app/sofer-vmone/releases/tag/APP';
      await autoUpdater.setFeedURL(feedURL);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.windowsFloatingMode?.removeListener(_onWindowsFloatingModeChanged);
    _pulseController.dispose();
    _timer?.cancel();
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
      _restoreTimerState();
    } catch (e) {
      debugPrint("Error loading data: $e");
    }
  }

  String _getDisplayDate(DateTime date) {
    return formatDisplayDate(date, _useGregorianDates);
  }

  /// Flips between the two workflows and remembers the choice.
  ///
  /// This used to live in settings. It is something a writer changes between
  /// sittings — smart when they are picking up where they left off, plain when
  /// they will say afterwards what they wrote — so it belongs where the work
  /// starts, not behind a settings screen.
  ///
  /// Refused mid-sitting: the two modes record a session differently, and
  /// switching underneath a running timer would leave it half in each.
  Future<void> _toggleWorkflowMode() async {
    if (_stopwatch.isRunning || _isPaused) {
      showAppError(context, "אפשר להחליף מצב רק כשהטיימר עצור");
      return;
    }
    final next = !_isSmartWorkflow;
    await _storageService.setSmartWorkflowEnabled(next);
    if (!mounted) return;
    setState(() => _isSmartWorkflow = next);
    // Switching into smart mode with a project already chosen: bring its stored
    // position along, so the position on screen is the real one immediately.
    if (next) await _loadSmartPosition();
  }

  /// Gathers what the ruled home screen shows.
  ///
  /// Built here because the figures come from the same sources the rest of the
  /// app uses — one pace calculation, one estimator — rather than from numbers
  /// the layout works out for itself.
  HomeSnapshot _buildHomeSnapshot() {
    final project = _selectedProject;
    final today = _effectiveDate(DateTime.now());

    var todayOutput = "—";
    String? hourlyRate;
    String? doneOfTotal;
    var progress = 0.0;
    String? completion;
    String? completionDetail;

    if (project != null) {
      final todaySessions = history
          .where((s) =>
              s.projectId == project.id &&
              !s.isDeleted &&
              !s.backlogOnly &&
              DateLogic.sessionIsOnDay(s, today, _dayStart))
          .toList();

      var worked = Duration.zero;
      for (final s in todaySessions) {
        if (s.duration > Duration.zero) worked += s.duration;
      }

      switch (project.type) {
        case ProjectType.sefer:
          final lines = ProductionCalculator.seferLinesTotal(todaySessions);
          todayOutput = "$lines שורות";
        case ProjectType.mezuza:
          final lines = ProductionCalculator.mezuzaLinesTotal(todaySessions);
          todayOutput =
              "${(lines / ProductionCalculator.linesPerMezuza).toStringAsFixed(1)} מזוזות";
        case ProjectType.tefillin:
          todayOutput =
              "${ProductionCalculator.parshiyotTotal(todaySessions)} פרשיות";
      }

      final rate =
          ProfitCalculator.profitPerHour(project, todaySessions, worked);
      if (rate != null) hourlyRate = "₪${rate.toStringAsFixed(0)}";

      final estimate = CompletionEstimator.estimate(
        project: project,
        history: history,
        rules: _workRules,
      );
      if (estimate != null) {
        progress = estimate.progress;
        final unit = switch (project.type) {
          ProjectType.sefer => "עמודים",
          ProjectType.mezuza => "מזוזות",
          ProjectType.tefillin => "סטים",
        };
        doneOfTotal = "${estimate.doneUnits.toStringAsFixed(0)} "
            "מתוך ${estimate.totalUnits.toStringAsFixed(0)} $unit";
        completion = formatDisplayDateWithWeekday(
            estimate.plan.completionDate, _useGregorianDates);
        completionDetail = "בעוד ${estimate.plan.calendarDays} ימים · "
            "${estimate.workDaysLeft.toStringAsFixed(0)} ימי עבודה";
      }
    }

    return HomeSnapshot(
      project: project,
      projects: projects,
      hebrewDate: _getDisplayDate(today),
      isRunning: _stopwatch.isRunning,
      isPaused: _isPaused,
      elapsed: formatClock(_effectiveElapsed()),
      // Clamped at the display boundary too: whatever goes wrong upstream, the
      // screen never shows a page or line zero.
      currentLine: _smartCurrentLine < 1 ? 1 : _smartCurrentLine,
      pageLabel: _positionPageLabel(project),
      positionUnit: project?.type == ProjectType.tefillin ? "פרשייה" : "שורה",
      todayOutput: todayOutput,
      hourlyRate: hourlyRate,
      doneOfTotal: doneOfTotal,
      progress: progress,
      completion: completion,
      completionDetail: completionDetail,
    );
  }

  /// Where the writer is, in the unit the commission is counted in.
  ///
  /// A sefer's pages read as Hebrew numerals, the way a sofer refers to them.
  /// Mezuzot and tefillin sets are counted, and a set is not a page — calling it
  /// one, as this screen used to, is simply wrong.
  String _positionPageLabel(Project? project) {
    final page = _smartCurrentPage < 1 ? 1 : _smartCurrentPage;
    return switch (project?.type) {
      ProjectType.mezuza => "מזוזה $page",
      ProjectType.tefillin => "סט $page",
      _ => "עמוד ${formatHebrewNumber(page)}",
    };
  }

  /// One app bar for every theme and both workflows.
  ///
  /// The workflow toggle sits immediately beside the tools button, which is
  /// where it was asked for: the two things a writer reaches for that are not
  /// about the sitting in front of them.
  PreferredSizeWidget _homeAppBar() {
    final t = SoferTokens.of(context);

    return AppBar(
      title: const Text('סופר ומונה'),
      centerTitle: t.isCards,
      actions: [
        IconButton(
          icon: Icon(_isSmartWorkflow ? Icons.my_location : Icons.timer_outlined),
          tooltip: _isSmartWorkflow
              ? "מצב חכם — עובד לפי המיקום. לחץ למצב רגיל"
              : "מצב רגיל — טיימר והזנה בסוף. לחץ למצב חכם",
          color: _isSmartWorkflow ? t.accent : null,
          // Left enabled while the timer runs: it explains why it will not
          // switch, which a greyed-out button cannot do.
          onPressed: _toggleWorkflowMode,
        ),
        IconButton(
          icon: const Icon(Icons.auto_awesome_mosaic),
          tooltip: "כלים",
          onPressed: _navigateToFeatures,
        ),
        if (Platform.isWindows)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
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
      ],
    );
  }

  Widget _homeBottomNav() {
    final t = SoferTokens.of(context);
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: t.paper,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.edit_outlined), label: "בית"),
        NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded), label: "סיכומים"),
        NavigationDestination(
            icon: Icon(Icons.folder_rounded), label: "פרויקטים"),
        NavigationDestination(
            icon: Icon(Icons.settings_rounded), label: "הגדרות"),
      ],
      onDestinationSelected: (i) {
        if (i == 1) _navigateToSummary();
        if (i == 2) _navigateToProjects();
        if (i == 3) _navigateToSettings();
      },
    );
  }

  HomeActions get _homeActions => HomeActions(
        // Smart mode picks up the stored position before the clock starts. Going
        // straight to the timer recorded the sitting from wherever the screen
        // happened to be — page one, on a fresh launch.
        onStart: _isSmartWorkflow ? _initSmartSession : _startTimer,
        onStop: _stopTimer,
        onBreak: _onBreakTap,
        onManualEntry: () => _openEntryDialog(isManual: true),
        onNextLine: _smartNextLine,
        onEditPosition: _showEditPositionDialog,
        onProjectChanged: _selectProject,
      );

  /// Choosing a commission in smart mode brings its stored position with it.
  ///
  /// Without this the screen showed — and the position dialog opened on — page
  /// one for every project until a sitting had been started.
  Future<void> _selectProject(Project? p) async {
    setState(() => _selectedProject = p);
    if (_isSmartWorkflow && p != null) await _loadSmartPosition();
  }

  /// Reads the stored position of the selected commission into the screen.
  Future<void> _loadSmartPosition() async {
    final project = _selectedProject;
    if (project == null) return;
    final lastPos = await _storageService.getLastPosition(project.id);
    if (!mounted) return;
    setState(() {
      // Clamped rather than trusted: a position stored by an older build, or a
      // hand-edited backup, could carry a zero.
      _smartCurrentPage = ((lastPos['page'] as int?) ?? 1).clamp(1, 1 << 20);
      _smartCurrentLine = ((lastPos['line'] as int?) ?? 1).clamp(1, 1 << 20);
      _smartStartPage = _smartCurrentPage;
      _smartStartLine = _smartCurrentLine;
    });
  }

  void _startTimer() {
    setState(() {
      _isPaused = false;
      if (!_stopwatch.isRunning) {
        if (_breakStopwatch.isRunning) {
          _sessionBreakDuration += _breakStopwatch.elapsed;
          _breakStopwatch.stop();
          _breakStopwatch.reset();
        }
        _stopwatch.start();
        _pulseController.repeat(reverse: true);
        _timerStartTime ??= DateTime.now();
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (mounted) setState(() {});
        });
        _storageService.clearTimerState();
      }
    });
  }

  void _pauseTimer() {
    setState(() {
      if (_timerStartTime != null) {
        _accumulatedElapsedSeconds +=
            DateTime.now().difference(_timerStartTime!).inSeconds;
        _timerStartTime = null;
      }
      _stopwatch.stop();
      _timer?.cancel();
      _pulseController.stop();
      _pulseController.value = 1.0;
      _isPaused = true;
      _breakStopwatch.start();
    });
    _persistTimerState();
  }

  void _stopTimer() {
    _lastSessionTime = _effectiveElapsed();
    final breakDuration = _sessionBreakDuration;
    setState(() {
      _stopwatch.stop();
      _timer?.cancel();
      _pulseController.stop();
      _pulseController.value = 1.0;
      _breakStopwatch.stop();
      _breakStopwatch.reset();
      _isPaused = false;
      _timerEndTime = DateTime.now();
      _stopwatch.reset();
      _lastLapTime = Duration.zero;
      _timerStartTime = null;
      _accumulatedElapsedSeconds = 0;
      _sessionBreakDuration = Duration.zero;
    });
    _storageService.clearTimerState();
    if (Platform.isAndroid) _stopTimerForegroundService();
    NotificationService().cancelBreakReminder();
    if (_isSmartWorkflow) {
      _finishSmartSession(breakDuration: breakDuration);
    } else {
      _openEntryDialog(isManual: false);
    }
  }

  Future<void> _persistTimerState() async {
    await _storageService.saveTimerState({
      'isPaused': _isPaused,
      'sessionStartTime': _timerStartTime?.toIso8601String(),
      'accumulatedElapsedSeconds': _accumulatedElapsedSeconds,
      'isSmart': _isSmartWorkflow,
      'projectId': _selectedProject?.id,
      'smartCurrentPage': _smartCurrentPage,
      'smartCurrentLine': _smartCurrentLine,
      'smartStartPage': _smartStartPage,
      'smartStartLine': _smartStartLine,
    });
  }

  Future<void> _restoreTimerState() async {
    final state = await _storageService.getTimerState();
    if (state.isEmpty) return;
    final isPaused = state['isPaused'] == true;
    final accumulated =
        (state['accumulatedElapsedSeconds'] as num?)?.toInt() ?? 0;
    final sessionStart = state['sessionStartTime'] as String?;
    final isSmart = state['isSmart'] == true;
    final projectId = state['projectId'] as String?;
    if (projectId == null && isSmart) return;
    if (!mounted) return;
    setState(() {
      _accumulatedElapsedSeconds = accumulated;
      _timerStartTime = sessionStart != null && !isPaused
          ? DateTime.tryParse(sessionStart)
          : null;
      _isPaused = isPaused;
      _isSmartWorkflow = isSmart;
      if (projectId != null) {
        _selectedProject = projects.cast<Project?>().firstWhere(
              (p) => p?.id == projectId,
              orElse: () => null,
            );
        _smartCurrentPage = (state['smartCurrentPage'] as num?)?.toInt() ?? 1;
        _smartCurrentLine = (state['smartCurrentLine'] as num?)?.toInt() ?? 1;
        _smartStartPage = (state['smartStartPage'] as num?)?.toInt() ?? 1;
        _smartStartLine = (state['smartStartLine'] as num?)?.toInt() ?? 1;
      }
      if (_timerStartTime != null) {
        _stopwatch.start();
        _pulseController.repeat(reverse: true);
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_timerStartTime != null || _isPaused) _persistTimerState();
      if (Platform.isAndroid && _timerStartTime != null) {
        _startTimerForegroundService();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid) _stopTimerForegroundService();
    }
  }

  Future<void> _initTimerForegroundService() async {
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sofer_vmone_timer',
        channelName: 'טיימר סופר ומונה',
        channelDescription: 'התראה כשהטיימר רץ ברקע',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  Future<void> _startTimerForegroundService() async {
    if (_timerStartTime == null) return;
    await FlutterForegroundTask.saveData(
      key: 'timerSessionStartTime',
      value: _timerStartTime!.toIso8601String(),
    );
    await FlutterForegroundTask.saveData(
      key: 'timerAccumulatedSeconds',
      value: _accumulatedElapsedSeconds,
    );
    await FlutterForegroundTask.startService(
      serviceId: 256,
      notificationTitle: 'סופר ומונה – טיימר פעיל',
      notificationText: formatClock(_effectiveElapsed()),
      callback: startTimerForegroundCallback,
    );
  }

  Future<void> _stopTimerForegroundService() async {
    await FlutterForegroundTask.stopService();
  }

  void _recordLap() {
    final currentElapsed = _effectiveElapsed();
    final lapDuration = currentElapsed - _lastLapTime;
    _lastLapTime = currentElapsed;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("סיימתי שורה! זמן שורה: ${formatClock(lapDuration)}"),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: SoferTokens.of(context).inkMuted,
      ),
    );
  }

  Future<void> _initSmartSession() async {
    if (_selectedProject == null) return;

    await _loadSmartPosition();
    if (!mounted) return;
    setState(() => _sessionBreakDuration = Duration.zero);
    _startTimer();
  }

  void _onBreakTap() {
    if (!_isSmartWorkflow) {
      _pauseTimer();
      return;
    }
    _showBreakStartDialog();
  }

  Future<void> _showBreakStartDialog() async {
    final minutesCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("הפסקת קפה"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("הזמן בהפסקה לא ייכנס בממוצע לכתיבה."),
            const SizedBox(height: 16),
            TextField(
              controller: minutesCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "התראה אחרי X דקות (אופציונלי – השאר ריק)",
                hintText: "למשל 10",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ביטול"),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.coffee),
            label: const Text("התחל הפסקה"),
          ),
        ],
      ),
    );
    final minutes = int.tryParse(minutesCtrl.text.trim());
    minutesCtrl.dispose();
    if (result != true || !mounted) return;
    if (minutes != null && minutes > 0) {
      await NotificationService().scheduleBreakReminder(minutes);
    }
    _pauseTimer();
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
        final int linesPerPage =
            ProductionCalculator.linesPerPageOf(_selectedProject!);

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
    final maxLines = isMezuza
        ? ProductionCalculator.linesPerMezuza
        : ProductionCalculator.linesPerPageOf(_selectedProject!);
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
    final page = isMezuza
        ? (int.tryParse(pageCtrl.text) ?? _smartCurrentPage)
        : parseHebrewPageToNumber(pageCtrl.text);
    final line = int.tryParse(lineCtrl.text) ?? _smartCurrentLine;
    pageCtrl.dispose();
    lineCtrl.dispose();
    if (ok != true || !mounted) return;
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

  Future<void> _finishSmartSession(
      {Duration breakDuration = Duration.zero}) async {
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
        showAppError(context, "לא נרשמה התקדמות בכתיבה");
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
        showAppError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      int numFullMezuzot = totalLinesWritten ~/ linesPerMezuza;
      int remainingLines = totalLinesWritten % linesPerMezuza;

      List<WorkSession> newSessions = [];
      if (numFullMezuzot > 0) {
        newSessions.add(WorkSession(
          id: IdGenerator.generate(),
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
          id: IdGenerator.generate(suffix: 'p'),
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

      setState(() => history.addAll(_stampWorkingDay(newSessions)));
      _storageService.saveHistory(history);
      _storageService.saveLastPosition(
          _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);

      showAppSuccess(
          context,
          breakDuration > Duration.zero
              ? "הסשן נשמר בהצלחה! סה\"כ נכתבו $totalLinesWritten שורות.\nזמן כתיבה נטו: ${formatClock(_lastSessionTime)}, זמן הפסקה: ${formatClock(breakDuration)}"
              : "הסשן נשמר בהצלחה! סה\"כ נכתבו $totalLinesWritten שורות.");
    } else {
      // --- Logic for Sefer Torah Projects ---
      final int linesPerPage =
          ProductionCalculator.linesPerPageOf(_selectedProject!);

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
        showAppError(context, "לא נרשמה התקדמות בכתיבה");
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
            id: IdGenerator.generate(suffix: '\$p'),
            projectId: _selectedProject!.id,
            startTime: DateTime.now(),
            endTime: DateTime.now(),
            amount: p,
            startLine: start,
            endLine: end,
            description: "כתיבה רציפה (עמוד ${formatHebrewNumber(p)})",
            isManual: false,
            linesPerPageAtEntry: linesPerPage,
          ));
        }
      }

      if (totalLinesWritten == 0) {
        showAppError(context, "לא נרשמה התקדמות בכתיבה");
        return;
      }

      // The smart flow wrote straight to history without ever checking for
      // duplicates, so using "edit position" to jump back and rewriting a
      // range produced a silent double entry.
      final overlapping = newSessions
          .where((s) => _checkOverlap(
              _selectedProject!.id, s.amount, s.startLine, s.endLine))
          .toList();
      if (overlapping.isNotEmpty) {
        final pages =
            overlapping.map((s) => formatHebrewNumber(s.amount)).join(', ');
        final confirm = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text("שים לב: כפילות"),
                content: Text(
                    "חלק מהשורות בעמוד $pages כבר נכתבו בעבר. האם לשמור בכל זאת?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text("ביטול")),
                  TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text("שמור בכל זאת")),
                ],
              ),
            ) ??
            false;
        if (!confirm || !mounted) return;
      }

      DateTime sessionEnd = DateTime.now();
      Duration totalNetTime = _lastSessionTime;
      double msPerLine = totalNetTime.inMilliseconds / totalLinesWritten;
      DateTime tempEndTime = sessionEnd;

      for (int i = newSessions.length - 1; i >= 0; i--) {
        WorkSession s = newSessions[i];
        int linesInThisSession = ProductionCalculator.seferLinesInSession(s);
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

      setState(() => history.addAll(_stampWorkingDay(newSessions)));
      _storageService.saveHistory(history);
      _storageService.saveLastPosition(
          _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);

      showAppSuccess(
          context,
          breakDuration > Duration.zero
              ? "הסשן נשמר בהצלחה! נכתבו $totalLinesWritten שורות.\nזמן כתיבה נטו: ${formatClock(_lastSessionTime)}, זמן הפסקה: ${formatClock(breakDuration)}"
              : "הסשן נשמר בהצלחה! נכתבו $totalLinesWritten שורות.");
    }
  }

  /// Empties every field of the entry form.
  ///
  /// One place, because two of the six were being missed: after "הוסף" the page
  /// and line the writer had reached stayed behind while the ones they started
  /// from were cleared.
  /// Opens the form that records work.
  ///
  /// The form owns its own fields and its own rules. What is left here is what
  /// only this screen can answer: which working day a record is filed under,
  /// where the stored position goes next, and whether a daily target has just
  /// been met.
  Future<void> _openEntryDialog({required bool isManual}) async {
    final used = await showEntrySheet(
      context: context,
      isManual: isManual,
      projects: projects,
      history: history,
      useGregorianDates: _useGregorianDates,
      dayStart: _dayStart,
      initialProject: _selectedProject,
      measuredTime: _lastSessionTime,
      measuredEnd: _timerEndTime,
      onProjectCreated: (project) {
        setState(() => projects.add(project));
        _storageService.saveProjects(projects);
      },
      onSave: _recordEntry,
    );
    // The commission the form was last used on stays selected here, so the two
    // screens never disagree about what is being worked on.
    if (used != null && mounted) setState(() => _selectedProject = used);
  }

  /// Files what the entry form produced.
  Future<void> _recordEntry(EntrySave save) async {
    setState(() {
      history.addAll(_stampWorkingDay(save.sessions));
      _storageService.saveHistory(history);
    });

    // Keeps the smart-workflow position in step with entries made by hand.
    // Otherwise typing pages in and then starting a smart session resumes from
    // wherever the writer was before, and rewrites work already recorded.
    await _advanceSmartPositionAfterEntry(
      project: save.project,
      page: save.reachedPage,
      lastLine: save.reachedLine,
      backlogOnly: save.backlogOnly,
    );

    if (Platform.isAndroid && _checkDailyGoalMet(save.project)) {
      NotificationService().cancelDailyReminder();
    }
  }

  /// Moves the stored smart-workflow position forward when a manual entry ends
  /// past it. Never moves it backwards, so filling in an earlier gap does not
  /// rewind the writer's place.
  Future<void> _advanceSmartPositionAfterEntry({
    required Project project,
    required int page,
    required int lastLine,
    required bool backlogOnly,
  }) async {
    // Backlog entries describe work done before the app existed and say
    // nothing about where the writer is now.
    if (backlogOnly) return;
    if (project.type != ProjectType.sefer && project.type != ProjectType.mezuza) {
      return;
    }
    if (page <= 0) return;

    final maxLines = project.type == ProjectType.mezuza
        ? ProductionCalculator.linesPerMezuza
        : ProductionCalculator.linesPerPageOf(project);

    // Next line after the one just recorded, rolling onto the next page.
    var nextPage = page;
    var nextLine = lastLine + 1;
    if (nextLine > maxLines) {
      nextPage += 1;
      nextLine = 1;
    }

    final stored = await _storageService.getLastPosition(project.id);
    final storedPage = (stored['page'] as int?) ?? 0;
    final storedLine = (stored['line'] as int?) ?? 0;
    final isAhead =
        nextPage > storedPage || (nextPage == storedPage && nextLine > storedLine);
    if (!isAhead) return;

    await _storageService.saveLastPosition(project.id, nextPage, nextLine);
    if (!mounted) return;
    if (_selectedProject?.id == project.id) {
      setState(() {
        _smartCurrentPage = nextPage;
        _smartCurrentLine = nextLine;
      });
    }
  }

  bool _checkOverlap(String projId, int page, int start, int end) =>
      SessionLogic.hasSeferOverlap(
        history: history,
        projectId: projId,
        page: page,
        startLine: start,
        endLine: end,
        projectType: _selectedProject?.type ?? ProjectType.sefer,
      );

  bool _checkDailyGoalMet(Project project) {
    if (project.targetDaily <= 0) return true;

    final now = DateTime.now();
    final todaySessions = history
        .where((s) =>
            s.projectId == project.id &&
            // Backlog entries record work done before the app existed and must
            // not count towards today's goal. They carry a placeholder date, so
            // this used to be filtered out only by accident.
            !s.backlogOnly &&
            DateLogic.sessionIsOnDay(s, now, _dayStart))
        .toList();

    int totalDone = 0;
    int target = project.targetDaily;
    for (var s in todaySessions) {
      if (project.type == ProjectType.sefer) {
        final int linesPerPage = ProductionCalculator.linesPerPageOf(project);
        totalDone += ProductionCalculator.seferLinesInSession(s);
        target = project.dailyGoalInLines
            ? project.targetDaily
            : (project.targetDaily * linesPerPage);
        if (totalDone >= target) return true;
      } else {
        totalDone += s.amount;
      }
    }
    return totalDone >= target;
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
          },
          onProjectDeleted: (p) {
            setState(() {
              projects.removeWhere((element) => element.id == p.id);
              history.removeWhere((session) => session.projectId == p.id);
            });
            _storageService.saveProjects(projects);
          },
          onResetAllData: _resetAllData,
        ),
      ),
    );
  }

  Future<void> _refreshSettingsFromStorage() async {
    final smartEnabled = await _storageService.getSmartWorkflowEnabled();
    final dayStart = await _storageService.getDayStart();
    final useGregorian = await _storageService.getUseGregorianDates();
    final workRules = await _storageService.getWorkCalendarRules();
    if (!mounted) return;
    setState(() {
      _isSmartWorkflow = smartEnabled;
      _dayStart = dayStart;
      _useGregorianDates = useGregorian;
      _workRules = workRules;
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

  void _navigateToFeatures() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            FeaturesScreen(projects: projects, history: history),
      ),
    );
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
                formatClock(_effectiveElapsed()),
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

    // The ruled themes share one home screen for both workflows; the cards
    // theme keeps the two it has always had.
    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: _homeAppBar(),
        body: RuledHomeBody(
          snapshot: _buildHomeSnapshot(),
          actions: _homeActions,
          isSmart: _isSmartWorkflow,
        ),
        bottomNavigationBar: _homeBottomNav(),
      );
    }

    if (_isSmartWorkflow) {
      return _buildSmartWorkflowUI();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FF),
      appBar: _homeAppBar(),
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
                              formatClock(_effectiveElapsed()),
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
                                    color: const Color(0xFFFFF5E6),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.brown.shade300,
                                        width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.brown.withValues(alpha: 0.2),
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
      // The same four destinations as the ruled layout, in the same order. With
      // three, "סיכומים" sat at index 0 and was drawn as the selected tab while
      // the writer was looking at the home screen.
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.deepPurple.shade50,
        selectedItemColor: Colors.deepPurple.shade800,
        unselectedItemColor: Colors.grey.shade700,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_outlined),
            label: "בית",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: "סיכומים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: "פרויקטים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: "הגדרות",
          ),
        ],
        onTap: (index) {
          if (index == 1) _navigateToSummary();
          // Expenses moved into the projects screen: costs are attributed to
          // the work they belong to, so that is where they are managed.
          if (index == 2) _navigateToProjects();
          if (index == 3) _navigateToSettings();
        },
      ),
    );
  }

  Widget _buildSmartWorkflowUI() {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF7FF),
      // The same app bar as plain mode, so the switch back is always in the
      // same place. Before this, smart mode had no way out but settings.
      appBar: _homeAppBar(),
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
                    onChanged: _selectProject,
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
                      formatClock(_effectiveElapsed()),
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
                              color: const Color(0xFFFFF5E6),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.brown.shade300, width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.brown.withValues(alpha: 0.2),
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
                    "בהפסקה: ${formatClock(_breakStopwatch.elapsed)}",
                    style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                        fontSize: 20),
                  )
                else if (_stopwatch.isRunning)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.blueGrey.shade200, width: 1),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "הקפה שורה נוכחית",
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatClock(_effectiveElapsed() - _lastLapTime),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 40),
                if (!_stopwatch.isRunning && !_isPaused)
                  ElevatedButton.icon(
                    onPressed: _initSmartSession,
                    icon: const Icon(Icons.login),
                    label: const Text("כניסה"),
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
                            onPressed: _isPaused ? _startTimer : _onBreakTap,
                            icon: Icon(
                                _isPaused ? Icons.play_arrow : Icons.coffee),
                            label: Text(_isPaused ? "המשך כתיבה" : "הפסקת קפה"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 20),
                          ElevatedButton.icon(
                            onPressed: _stopTimer,
                            icon: const Icon(Icons.logout),
                            label: const Text("יציאה"),
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
      // The same four destinations as the ruled layout, in the same order. With
      // three, "סיכומים" sat at index 0 and was drawn as the selected tab while
      // the writer was looking at the home screen.
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.deepPurple.shade50,
        selectedItemColor: Colors.deepPurple.shade800,
        unselectedItemColor: Colors.grey.shade700,
        type: BottomNavigationBarType.fixed,
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.edit_outlined),
            label: "בית",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_rounded),
            label: "סיכומים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.folder_rounded),
            label: "פרויקטים",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: "הגדרות",
          ),
        ],
        onTap: (index) {
          if (index == 1) _navigateToSummary();
          // Expenses moved into the projects screen: costs are attributed to
          // the work they belong to, so that is where they are managed.
          if (index == 2) _navigateToProjects();
          if (index == 3) _navigateToSettings();
        },
      ),
    );
  }
}
