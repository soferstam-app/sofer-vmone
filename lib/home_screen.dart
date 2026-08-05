import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'entry/entry_sheet.dart';
import 'format.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/production_calculator.dart';
import 'logic/timer_controller.dart';
import 'logic/smart_session.dart';
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
import 'widgets/confirm.dart';
import 'logic/daily_goal.dart';
import 'home/floating_window.dart';
import 'home/cards_smart_body.dart';
import 'backup_service.dart';

class SoferHome extends StatefulWidget {
  const SoferHome({super.key, this.windowsFloatingMode});

  final ValueNotifier<bool>? windowsFloatingMode;

  @override
  State<SoferHome> createState() => _SoferHomeState();
}

class _SoferHomeState extends State<SoferHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The sitting's clock. Everything about measuring time lives there; what is
  /// left here is telling the screen to redraw and keeping the pulse in step.
  late final TimerController _clock;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  bool _isSmartWorkflow = false;

  List<Project> projects = [];
  List<WorkSession> history = [];
  final StorageService _storageService = StorageService();

  Project? _selectedProject;
  // Pages and lines are counted from one. There is no page 0 and no line 0, so
  // these never start at zero — a zero on screen is always a bug.
  int _smartCurrentPage = 1;
  int _smartCurrentLine = 1;
  int _smartStartPage = 1;
  int _smartStartLine = 1;

  /// Whether the chosen commission has a position stored from a previous
  /// sitting. Distinct from the position being 1,1, which is where a writer who
  /// has genuinely begun at the beginning stands.
  bool _hasStoredPosition = false;


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
    _clock = TimerController(onTick: () {
      if (mounted) setState(() {});
    });
    widget.windowsFloatingMode?.addListener(_onWindowsFloatingModeChanged);
    _storageService.getDayStart().then((d) {
      if (mounted) setState(() => _dayStart = d);
    });
    _storageService.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    NotificationService().scheduleDailyReminder();

    _clock.initForegroundService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadData();
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

  /// Records filed under today's working day — the writer's own day, so a
  /// sitting at half past midnight still counts under the day he was working.
  int get _recordsToday => history
      .where((s) =>
          !s.isDeleted &&
          DateLogic.sessionIsOnDay(s, DateTime.now(), _dayStart))
      .length;

  /// Freezes onto each session the day-boundary rule it is being filed under.
  ///
  /// Every path that records work goes through here. The rule is settled once,
  /// now — so that changing the boundary later cannot re-file work that was
  /// already counted under a different reckoning, while a correction to how a
  /// boundary is computed still reaches every record ever made.
  ///
  /// The day the rule produces is written alongside it, for an older build that
  /// looks for the day and knows nothing about rules.
  ///
  /// A record that already carries a day is left alone: the writer stated it
  /// himself, and a rule for interpreting measurements has no business
  /// overruling an assertion.
  List<WorkSession> _stampWorkingDay(List<WorkSession> sessions) => sessions
      .map((s) => s.dayRule != null || s.workingDateAtEntry != null
          ? s
          : s.copyWith(
              dayRule: _dayStart,
              workingDateAtEntry:
                  DateLogic.effectiveDate(s.startTime, _dayStart)))
      .toList();


  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.windowsFloatingMode?.removeListener(_onWindowsFloatingModeChanged);
    _pulseController.dispose();
    _clock.dispose();
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
    if (_clock.isRunning || _clock.isPaused) {
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
      if (rate != null) hourlyRate = formatMoney(rate, project.currency);

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
      isRunning: _clock.isRunning,
      isPaused: _clock.isPaused,
      elapsed: formatClock(_clock.elapsed),
      breakElapsed: formatClock(_clock.breakElapsed),
      sinceLastLap: formatClock(_clock.sinceLastLap),
      // Read off the position already loaded rather than through a
      // FutureBuilder in the layout, which re-read storage on every rebuild.
      // Null and "page one" are different things: one is a commission never
      // touched, the other is one begun at the beginning.
      lastPosition: _hasStoredPosition
          ? "מיקום אחרון: ${_positionPageLabel(project)}, שורה $_smartCurrentLine"
          : null,
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
        // Named, not only drawn. This one control changes how the whole app
        // behaves, and it used to say so in a tooltip alone — which on a phone
        // opens on a long press, so in practice it said nothing. Someone tapped
        // it by accident, the app started behaving differently, and there was
        // no way to tell what had been pressed or how to undo it.
        TextButton.icon(
          icon: Icon(
              _isSmartWorkflow ? Icons.my_location : Icons.timer_outlined,
              size: 20),
          label: Text(_isSmartWorkflow ? "מצב חכם" : "מצב רגיל"),
          style: TextButton.styleFrom(
            foregroundColor: _isSmartWorkflow ? t.accent : null,
          ),
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
                // Remembered, because coming back used to impose 1280x720 and
                // discard whatever size the writer had arranged for himself.
                _sizeBeforeFloating = await windowManager.getSize();
                // The floor set for the main window would refuse a 320-wide
                // one, so it is lifted for as long as the small window is up.
                await windowManager.setMinimumSize(const Size(280, 200));
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
        onResume: _startTimer,
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
      _hasStoredPosition = lastPos.isNotEmpty;
      // Clamped rather than trusted: a position stored by an older build, or a
      // hand-edited backup, could carry a zero.
      _smartCurrentPage = ((lastPos['page'] as int?) ?? 1).clamp(1, 1 << 20);
      _smartCurrentLine = ((lastPos['line'] as int?) ?? 1).clamp(1, 1 << 20);
      _smartStartPage = _smartCurrentPage;
      _smartStartLine = _smartCurrentLine;
    });
  }

  void _startTimer() {
    setState(_clock.start);
    _syncPulse();
  }

  void _pauseTimer() {
    setState(_clock.pause);
    _syncPulse();
    _persistTimerState();
  }

  void _stopTimer() {
    late final StoppedSitting sitting;
    setState(() => sitting = _clock.stop());
    _syncPulse();

    _clock.stopForegroundService();
    NotificationService().cancelBreakReminder();

    if (_isSmartWorkflow) {
      _finishSmartSession(breakDuration: sitting.onBreak);
    } else {
      _openEntryDialog(isManual: false);
    }
  }

  /// The pulse follows the clock rather than being driven alongside it, so
  /// there is one answer to whether writing is under way and not two.
  void _syncPulse() {
    if (_clock.isRunning && !_clock.isPaused) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  Future<void> _persistTimerState() async {
    await _storageService.saveTimerState({
      ..._clock.toJson(),
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
    final isSmart = state['isSmart'] == true;
    final projectId = state['projectId'] as String?;
    if (projectId == null && isSmart) return;
    if (!mounted) return;
    var running = false;
    setState(() {
      running = _clock.restoreFrom(state);
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
    });
    if (running) _syncPulse();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_clock.isActive) _persistTimerState();
      _clock.startForegroundService();
    } else if (state == AppLifecycleState.resumed) {
      _clock.stopForegroundService();
    }
  }

  void _recordLap() {
    final lapDuration = _clock.recordLap();

    showAppNote(
        context, "סיימתי שורה! זמן שורה: ${formatClock(lapDuration)}");
  }

  Future<void> _initSmartSession() async {
    if (_selectedProject == null) return;

    await _loadSmartPosition();
    if (!mounted) return;
    setState(_clock.clearBreaks);
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
      if (!_clock.isRunning && !_clock.isPaused) {
        _smartStartPage = p;
        _smartStartLine = l;
      }
    });
    await _storageService.saveLastPosition(_selectedProject!.id, p, l);
  }

  /// Files a sitting recorded in smart mode.
  ///
  /// The arithmetic — which lines of which pages were written, and how the
  /// measured time divides between them — lives in [SmartSessionBuilder], which
  /// is pure and tested. Left here: the duplicate question, the message, and the
  /// write.
  Future<void> _finishSmartSession(
      {Duration breakDuration = Duration.zero}) async {
    final project = _selectedProject;
    if (project == null) return;

    final outcome = SmartSessionBuilder.build(
      project: project,
      from: SmartPosition(_smartStartPage, _smartStartLine),
      to: SmartPosition(_smartCurrentPage, _smartCurrentLine),
      worked: _clock.lastSitting,
      endedAt: _clock.endedAt ?? DateTime.now(),
      history: history,
    );

    switch (outcome) {
      case SmartNothingWritten():
        showAppError(context, "לא נרשמה התקדמות בכתיבה");
        return;

      case SmartRecorded(
          :final sessions,
          :final linesWritten,
          :final overlappingPages
        ):
        if (overlappingPages.isNotEmpty &&
            !await _confirmSmartOverlap(overlappingPages)) {
          return;
        }
        if (!mounted) return;

        setState(() => history.addAll(_stampWorkingDay(sessions)));
        await _storageService.saveHistory(history);
        await _storageService.saveLastPosition(
            project.id, _smartCurrentPage, _smartCurrentLine);

        if (!mounted) return;
        showAppSuccess(
          context,
          breakDuration > Duration.zero
              ? "הסשן נשמר בהצלחה! נכתבו $linesWritten שורות.\n"
                  "זמן כתיבה נטו: ${formatClock(_clock.lastSitting)}, "
                  "זמן הפסקה: ${formatClock(breakDuration)}"
              : "הסשן נשמר בהצלחה! נכתבו $linesWritten שורות.",
        );
    }
  }

  /// Smart mode used to write straight to history without ever looking, so
  /// jumping back with "ערוך מיקום" and rewriting a stretch produced a silent
  /// double entry.
  Future<bool> _confirmSmartOverlap(List<int> pages) =>
      confirmOverlap(context, pages: pages);

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
      measuredTime: _clock.lastSitting,
      measuredEnd: _clock.endedAt,
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

    final metToday = DailyGoal.isMet(
      project: save.project,
      history: history,
      day: DateTime.now(),
      dayStart: _dayStart,
    );
    // A copy into the folder the writer chose, if he chose one. Fire and
    // forget: a backup that cannot be written is not a reason to interrupt
    // someone who has just finished writing, and the next sitting tries again.
    BackupService.instance.writeAutoBackup();

    // Today's only. Cancelling the whole queue is what the old code did, and it
    // silenced the reminder for every day after as well.
    if (NotificationService.isSupported && metToday) {
      NotificationService().cancelTodaysReminder();
    } else {
      // Tops the week up, so the queue never runs dry for anyone recording work.
      NotificationService().scheduleDailyReminder();
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

    final linesPerUnit = project.type == ProjectType.mezuza
        ? ProductionCalculator.linesPerMezuza
        : ProductionCalculator.linesPerPageOf(project);
    final next = SmartPosition.after(
        page: page, line: lastLine, linesPerUnit: linesPerUnit);

    final stored = await _storageService.getLastPosition(project.id);
    final current = SmartPosition(
        (stored['page'] as int?) ?? 0, (stored['line'] as int?) ?? 0);
    if (!next.isAfter(current)) return;

    await _storageService.saveLastPosition(project.id, next.page, next.line);
    if (!mounted) return;
    if (_selectedProject?.id == project.id) {
      setState(() {
        _smartCurrentPage = next.page;
        _smartCurrentLine = next.line;
      });
    }
  }

  void _resetAllData() async {
    // The one place that erases rather than marks. Saving an empty list used to
    // do it, which is exactly the confusion that let every other save erase
    // tombstones by accident; a save no longer removes anything, so asking for
    // this has to be explicit.
    await _storageService.eraseAllRecords();
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
            // A deleted project leaves the screen; it does not leave the file.
            // Its sessions stay too, and stay alive — the work happened, and
            // restoring the project from the bin has to bring it back. They
            // used to be dropped here, so a restore returned an empty project.
            setState(() {
              if (p.isDeleted) {
                projects.removeWhere((element) => element.id == p.id);
              } else {
                int index =
                    projects.indexWhere((element) => element.id == p.id);
                if (index != -1) projects[index] = p;
              }
            });
            _storageService.saveProjects(projects);
          },
          onProjectDeleted: (p) {
            setState(() =>
                projects.removeWhere((element) => element.id == p.id));
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
          // What comes back may carry tombstones — the editor marks a record
          // deleted rather than dropping it. The whole list is written; only
          // the live records stay on screen.
          onHistoryUpdated: (updatedHistory) {
            _storageService.saveHistory(updatedHistory);
            setState(() => history =
                updatedHistory.where((s) => !s.isDeleted).toList());
          },
          useGregorianDates: _useGregorianDates,
        ),
      ),
    );
  }

  /// The main window's size before the floating one took over, so returning
  /// gives the writer his own window back rather than a fresh 1280x720.
  Size? _sizeBeforeFloating;

  Future<void> _restoreFromFloatingWindow() async {
    if (!Platform.isWindows || widget.windowsFloatingMode == null) return;
    widget.windowsFloatingMode!.value = false;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(const Size(420, 640));
    await windowManager.setSize(_sizeBeforeFloating ?? const Size(1280, 720));
    await windowManager.center();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows && (widget.windowsFloatingMode?.value ?? false)) {
      return FloatingTimerWindow(
        clock: _clock,
        onStart: _startTimer,
        onPause: _pauseTimer,
        onStop: _stopTimer,
        onLap: _recordLap,
        onRestore: _restoreFromFloatingWindow,
      );
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
      return Scaffold(
        appBar: _homeAppBar(),
        body: CardsSmartBody(
          snapshot: _buildHomeSnapshot(),
          actions: _homeActions,
          pulse: _pulseAnimation,
        ),
        bottomNavigationBar: _homeBottomNav(),
      );
    }

    return Scaffold(
      appBar: _homeAppBar(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // A first launch has no commissions, and this layout used to answer
          // that with a running timer and no hint that anything was missing.
          // The writer pressed start, wrote, pressed stop — and only then was
          // told there was nothing to file it against. The ruled layouts have
          // always said so first; this one is the default, so it is the one
          // almost everybody met.
          if (projects.isEmpty) {
            return _ModernEmptyState(
              hebrewDate: _getDisplayDate(_effectiveDate(DateTime.now())),
              onCreateProject: _navigateToProjects,
            );
          }
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
                      // Which commission this sitting belongs to, on the screen
                      // rather than at the end of it. The ruled layouts have
                      // always asked here; this one asked only once the writer
                      // had already stopped the clock, which is the wrong end of
                      // the job to be choosing at.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _clock.isRunning || _clock.isPaused
                              ? Text(
                                  _selectedProject?.name ?? '',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w500),
                                )
                              : DropdownButtonFormField<Project>(
                                  initialValue: _selectedProject,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    border: UnderlineInputBorder(),
                                    hintText: "בחר פרויקט",
                                  ),
                                  items: [
                                    for (final p in projects)
                                      DropdownMenuItem(
                                          value: p, child: Text(p.name)),
                                  ],
                                  onChanged: _selectProject,
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: FadeTransition(
                            opacity: _pulseAnimation,
                            child: Text(
                              formatClock(_clock.elapsed),
                              style: const TextStyle(
                                  fontSize: 80, fontWeight: FontWeight.w200),
                            ),
                          ),
                        ),
                      ),
                      if (_clock.isRunning && !_clock.isPaused)
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
                      if (!_clock.isRunning && !_clock.isPaused)
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
                            // Nothing to start until there is a commission to
                            // start it against.
                            onPressed:
                                _selectedProject == null ? null : _startTimer,
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
                        // Ordered by how often a writer reaches for them.
                        // Finishing a line happens dozens of times in a sitting;
                        // breaking and stopping happen once each. The big button
                        // used to be the one pressed last.
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_clock.isPaused) ...[
                              ElevatedButton.icon(
                                onPressed: _recordLap,
                                icon: const Icon(Icons.flag, size: 28),
                                label: const Text("סיימתי שורה"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[400],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 50, vertical: 25),
                                  textStyle: const TextStyle(fontSize: 20),
                                ),
                              ),
                              const SizedBox(height: 18),
                            ],
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed:
                                      _clock.isPaused ? _startTimer : _pauseTimer,
                                  icon: Icon(_clock.isPaused
                                      ? Icons.play_arrow
                                      : Icons.coffee),
                                  label: Text(_clock.isPaused ? "המשך" : "הפסקת קפה"),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 15),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                OutlinedButton.icon(
                                  onPressed: _stopTimer,
                                  icon: const Icon(Icons.stop),
                                  label: const Text("סיים"),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 15),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      const SizedBox(height: 20),
                      if (!_clock.isRunning && !_clock.isPaused)
                        OutlinedButton.icon(
                          onPressed: () => _openEntryDialog(isManual: true),
                          icon: const Icon(Icons.edit_calendar),
                          label: const Text("הוספת כתיבה ידנית (ללא טיימר)"),
                        ),
                      const SizedBox(height: 12),
                      // Today's work, not "this session". The old line counted
                      // records since the app was opened — a number that reset
                      // itself on every launch and told the writer nothing about
                      // his day. "סשן" was not a Hebrew word either.
                      if (_recordsToday > 0)
                        Text(
                          "נשמרו היום $_recordsToday רשומות",
                          style: const TextStyle(color: Colors.grey),
                        ),
                      // Not a coffee cup: while the timer runs, "הפסקת קפה" is
                      // on the same screen, and the two meant different things
                      // under the same picture.
                      TextButton.icon(
                        icon: const Icon(Icons.volunteer_activism, size: 20),
                        label: const Text("תרומה לפיתוח"),
                        onPressed: () => launchUrl(
                            Uri.parse('https://buymeacoffee.com/soferstam')),
                        style: TextButton.styleFrom(
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
      // The same bar as every other layout. This used to be a second copy —
      // same four destinations, same routing, written out again in the older
      // Material widget with its colours hardcoded, so smart mode was the one
      // screen the theme did not reach.
      bottomNavigationBar: _homeBottomNav(),
    );
  }

}

/// No commissions yet, in the cards layout — an invitation rather than a timer
/// with nothing behind it.
///
/// Says the same thing the ruled layouts say, and offers the way out of it,
/// because "open a project first" is only useful next to the door.
class _ModernEmptyState extends StatelessWidget {
  final String hebrewDate;
  final VoidCallback onCreateProject;

  const _ModernEmptyState({
    required this.hebrewDate,
    required this.onCreateProject,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(hebrewDate,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 22),
            Text("אין עוד פרויקטים",
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              "פתח פרויקט ראשון כדי להתחיל למדוד כתיבה, רווח וצפי סיום.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, height: 1.6, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: onCreateProject,
              icon: const Icon(Icons.add),
              label: const Text("פתיחת פרויקט ראשון"),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                textStyle: const TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
