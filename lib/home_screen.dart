import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'entry/entry_sheet.dart';
import 'format.dart';
import 'logic/break_timing.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/keyboard_shortcuts.dart';
import 'logic/home_additions.dart';
import 'logic/measured_work.dart';
import 'logic/production_calculator.dart';
import 'logic/timer_controller.dart';
import 'logic/smart_session.dart';
import 'logic/smart_live_recording.dart';
import 'logic/id_generator.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'projects_screen.dart';
import 'storage_service.dart';
import 'summary_screen.dart';
import 'features_screen.dart';
import 'notification_service.dart';
import 'hebrew_utils.dart';
import 'home/ruled_home_body.dart';
import 'home/mezuza_position_sheet.dart';
import 'home/tefillin_position_sheet.dart';
import 'logic/completion_estimator.dart';
import 'logic/mezuza_state.dart';
import 'logic/tefillin_position.dart';
import 'logic/tefillin_state.dart';
import 'logic/tefillin_units.dart';
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
  const SoferHome({
    super.key,
    this.windowsFloatingMode,
    this.openProjectsOnStart = false,
  });

  final ValueNotifier<bool>? windowsFloatingMode;

  /// Set when the writer arrives from the opening explanation having pressed
  /// "פתיחת פרויקט ראשון". The screen spent five pages saying a project comes
  /// first, so it opens one rather than landing him on an empty home screen
  /// carrying the same button again.
  final bool openProjectsOnStart;

  @override
  State<SoferHome> createState() => _SoferHomeState();
}

class _SoferHomeState extends State<SoferHome>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// The sitting's clock. Everything about measuring time lives there; what is
  /// left here is telling the screen to redraw and keeping the pulse in step.
  late final TimerController _clock;

  /// Whether pressing "הפסקת קפה" asks how long. Off means the break just
  /// starts, and then nothing can be counted against it.
  bool _askBreakLength = true;

  /// The remembered answer to "צליל בסיום הזמן", carried between breaks.
  bool _breakChime = false;

  /// The length set for the break under way, or null when none was named.
  Duration? _breakTarget;

  bool _chimeSounded = false;
  Duration _lastBreakElapsed = Duration.zero;

  HomeAdditionsSettings _homeAdditions = HomeAdditionsSettings.defaults;
  Timer? _metronomeTimer;
  Timer? _celebrationTimer;
  bool _goalCelebrationVisible = false;
  DateTime? _endTimeDeadline;
  bool _endTimeSounded = false;

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

  /// Time already filed when a smart sitting changed position without ending
  /// the clock. The remainder belongs to the current stretch only.
  Duration _smartRecordedElapsed = Duration.zero;
  bool _smartSavedAny = false;
  int _smartSavedLines = 0;

  /// One identity for every checkpoint written during the sitting. A line is
  /// durable as soon as it is marked, while all lines on the same physical
  /// page still fold back into one record.
  String? _smartEntryId;
  bool _smartLineSaving = false;

  /// Whether the chosen commission has a position stored from a previous
  /// sitting. Distinct from the position being 1,1, which is where a writer who
  /// has genuinely begun at the beginning stands.
  bool _hasStoredPosition = false;

  DayStart _dayStart = DayStart.midnight;
  bool _useGregorianDates = false;

  /// Needed for the completion estimate the ruled home screen shows.
  WorkCalendarRules _workRules = WorkCalendarRules.standard;

  /// Which key does what, and the focus that hears them.
  ShortcutMap _shortcuts = ShortcutMap.defaults;
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'shortcuts');

  void _onWindowsFloatingModeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = TimerController(onTick: () {
      if (!mounted) return;
      _checkBreakChime();
      _checkEndTimeAlert();
      setState(() {});
    });
    widget.windowsFloatingMode?.addListener(_onWindowsFloatingModeChanged);
    if (widget.openProjectsOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _navigateToProjects();
      });
    }
    _storageService.getDayStart().then((d) {
      if (mounted) setState(() => _dayStart = d);
    });
    _storageService.getUseGregorianDates().then((v) {
      if (mounted) setState(() => _useGregorianDates = v);
    });
    _storageService.getAskBreakLength().then((v) {
      if (mounted) setState(() => _askBreakLength = v);
    });
    _storageService.getBreakChime().then((v) {
      if (mounted) setState(() => _breakChime = v);
    });
    _storageService.getShortcuts().then((v) {
      if (mounted) setState(() => _shortcuts = v);
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
    _metronomeTimer?.cancel();
    _celebrationTimer?.cancel();
    _keyboardFocus.dispose();
    _clock.dispose();
    super.dispose();
  }

  /// Which commission the home screen opens on.
  ///
  /// The one last worked on, when it is still there. A commission that has been
  /// deleted or finished since is not a starting point, and falling back to the
  /// only one there is beats opening on nothing when there is nothing to choose.
  static Project? _pickStartingProject(List<Project> live, String? lastId) {
    if (live.isEmpty) return null;
    for (final p in live) {
      if (p.id == lastId) return p;
    }
    return live.length == 1 ? live.first : null;
  }

  Future<void> _loadData() async {
    try {
      final loadedProjects = await _storageService.loadProjects();
      var activeProjects = loadedProjects.where((p) => !p.isDeleted).toList();
      activeProjects = activeProjects.toSet().toList();

      final loadedHistory = await _storageService.loadHistory();
      final activeHistory = loadedHistory.where((h) => !h.isDeleted).toList();
      final smartEnabled = await _storageService.getSmartWorkflowEnabled();
      final homeAdditions = await _storageService.getHomeAdditions();
      // The commission he was last working on, already chosen. A sofer works on
      // one job for weeks, and being asked to pick it out of a list every time
      // the app opens is being asked something the app already knows — the
      // entry form has defaulted to it for a while; the home screen had not.
      final lastId = await _storageService.getLastProjectId();
      if (!mounted) return;
      setState(() {
        projects = activeProjects;
        history = activeHistory;
        _isSmartWorkflow = smartEnabled;
        _homeAdditions = homeAdditions;
        _selectedProject = _pickStartingProject(activeProjects, lastId);
      });
      if (_isSmartWorkflow && _selectedProject != null) {
        await _loadSmartPosition();
      }
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
    final now = DateTime.now();
    final today = _effectiveDate(now);

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

      switch (project.type) {
        case ProjectType.sefer:
          final lines = ProductionCalculator.seferLinesTotal(todaySessions);
          todayOutput = "$lines שורות";
        case ProjectType.mezuza:
          final lines = ProductionCalculator.mezuzaLinesTotal(todaySessions);
          todayOutput =
              "${(lines / ProductionCalculator.linesPerMezuza).toStringAsFixed(1)} מזוזות";
        case ProjectType.tefillin:
          // In sefer lines, so a day on tefillin can be held against a day on
          // anything else. A count of parshiyot could not be.
          final lines =
              ProductionCalculator.tefillinSeferLinesTotal(todaySessions);
          todayOutput = "מקביל ל־${lines.toStringAsFixed(0)} שורות של ס״ת";
      }

      // Today's pay per hour is a rate: both halves from the sittings that
      // were actually timed, not from every record filed under today.
      final measuredToday = MeasuredWork.only(todaySessions);
      final rate = ProfitCalculator.profitPerHour(
          project, measuredToday, MeasuredWork.time(measuredToday));
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
          ProjectType.tefillin => "זוגות",
        };
        doneOfTotal = "${estimate.doneUnits.toStringAsFixed(0)} "
            "מתוך ${estimate.totalUnits.toStringAsFixed(0)} $unit";
        completion = formatDisplayDateWithWeekday(
            estimate.plan.completionDate, _useGregorianDates);
        completionDetail = "בעוד ${estimate.plan.calendarDays} ימים · "
            "${estimate.workDaysLeft.toStringAsFixed(0)} ימי עבודה";
      }
    }

    final lineCountdown = TargetCountdown(
      target: _homeAdditions.lineTargetEnabled
          ? Duration(seconds: _homeAdditions.lineTargetSeconds)
          : null,
      elapsed: _clock.sinceLastLap,
    );
    final writingCountdown = TargetCountdown(
      target: _homeAdditions.writingTargetEnabled
          ? Duration(minutes: _homeAdditions.writingTargetMinutes)
          : null,
      elapsed: _clock.elapsed,
    );
    String? writingStatus;
    if (_homeAdditions.writingTargetEnabled) {
      writingStatus = _clock.isActive
          ? writingCountdown.isOverrun
              ? 'יעד הכתיבה · חריגה ${writingCountdown.label}'
              : 'יעד הכתיבה · נותרו ${writingCountdown.label}'
          : 'יעד הכתיבה · ${formatClock(Duration(minutes: _homeAdditions.writingTargetMinutes))}';
    }

    String? endTimeStatus;
    var endTimeOverrun = false;
    if (_homeAdditions.endTimeAlertEnabled) {
      final configured = _formatConfiguredTime(_homeAdditions.endTimeMinutes);
      final deadline = _endTimeDeadline;
      if (_clock.isActive && deadline != null) {
        final difference = deadline.difference(now);
        endTimeOverrun = difference.isNegative;
        final absolute = difference.isNegative ? -difference : difference;
        final signed =
            '${difference.isNegative ? '-' : ''}${formatClock(absolute)}';
        endTimeStatus = endTimeOverrun
            ? 'שעת סיום $configured · חריגה $signed'
            : 'שעת סיום $configured · נותרו $signed';
      } else {
        endTimeStatus = 'התראה בשעת סיום · $configured';
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
      breakRemaining: _breakCountdown.label ?? '',
      breakOverrun: _breakCountdown.isOverrun,
      sinceLastLap: formatClock(_clock.sinceLastLap),
      lineClockLabel: _homeAdditions.lineTargetEnabled ? 'יעד לשורה' : null,
      lineClockValue:
          _homeAdditions.lineTargetEnabled ? lineCountdown.label : null,
      lineClockOverrun: lineCountdown.isOverrun,
      writingTargetStatus: writingStatus,
      writingTargetOverrun: writingCountdown.isOverrun,
      endTimeStatus: endTimeStatus,
      endTimeOverrun: endTimeOverrun,
      metronomeBpm:
          _homeAdditions.metronomeEnabled ? _homeAdditions.metronomeBpm : null,
      metronomeActive: _homeAdditions.metronomeEnabled &&
          _clock.isRunning &&
          !_clock.isPaused,
      isSavingLine: _smartLineSaving,
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
      positionTitle: project?.type == ProjectType.tefillin
          ? TefillinPosition.fromSlotIndex(_smartCurrentPage).parshiyaName
          : null,
      todayOutput: todayOutput,
      hourlyRate: hourlyRate,
      doneOfTotal: doneOfTotal,
      progress: progress,
      completion: completion,
      completionDetail: completionDetail,
    );
  }

  String _formatConfiguredTime(int minutes) {
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = minutes.remainder(60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Where the writer is, in the unit the commission is counted in.
  ///
  /// A sefer's pages read as Hebrew numerals, the way a sofer refers to them.
  /// Mezuzot and tefillin sets are counted, and a set is not a page — calling it
  /// one, as this screen used to, is simply wrong.
  String _positionPageLabel(Project? project) {
    final page = _smartCurrentPage < 1 ? 1 : _smartCurrentPage;
    if (project?.type == ProjectType.tefillin) {
      // The stored number is a slot in the commission, not a pair — see
      // [TefillinPosition.slotIndex] — so it is unfolded before it is shown.
      final at = TefillinPosition.fromSlotIndex(page);
      final line = _smartCurrentLine < 1 ? 1 : _smartCurrentLine;
      return "${at.whereLabel} · שורה $line מתוך ${at.lineCount}";
    }
    return switch (project?.type) {
      ProjectType.mezuza => "מזוזה $page",
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
        NavigationDestination(icon: Icon(Icons.edit_outlined), label: "בית"),
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
        onLap: _recordLap,
        onEditPosition: _showEditPositionDialog,
        onSkipMezuza: _skipMezuza,
        onProjectChanged: _selectProject,
        onResume: _startTimer,
      );

  /// Choosing a commission in smart mode brings its stored position with it.
  ///
  /// Without this the screen showed — and the position dialog opened on — page
  /// one for every project until a sitting had been started.
  Future<void> _selectProject(Project? p) async {
    setState(() => _selectedProject = p);
    // Remembered here as well as at entry. Only a commission written through
    // the entry form used to be, so choosing one on this screen and working on
    // it all evening left the app opening on something else the next morning.
    if (p != null) await _storageService.setLastProjectId(p.id);
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
    final freshSitting = !_clock.isActive;
    if (freshSitting) {
      _endTimeSounded = false;
      _endTimeDeadline = _homeAdditions.endTimeAlertEnabled
          ? nextClockOccurrence(DateTime.now(), _homeAdditions.endTimeMinutes)
          : null;
    }
    setState(() {
      _clock.start();
      _clearBreakTarget();
    });
    _syncPulse();
    _syncMetronome();
    final deadline = _endTimeDeadline;
    if (freshSitting && deadline != null) {
      NotificationService().scheduleWritingEndAlert(deadline);
    }
  }

  void _pauseTimer() {
    setState(_clock.pause);
    _syncPulse();
    _syncMetronome();
    _persistTimerState();
  }

  void _stopTimer() {
    if (_smartLineSaving) return;
    late final StoppedSitting sitting;
    setState(() => sitting = _clock.stop());
    _syncPulse();
    _syncMetronome();

    _clock.stopForegroundService();
    NotificationService().cancelBreakReminder();
    NotificationService().cancelWritingEndAlert();
    _endTimeDeadline = null;
    _endTimeSounded = false;

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
      'smartRecordedElapsedSeconds': _smartRecordedElapsed.inSeconds,
      'smartSavedAny': _smartSavedAny,
      'smartSavedLines': _smartSavedLines,
      'smartEntryId': _smartEntryId,
      'endTimeDeadline': _endTimeDeadline?.toIso8601String(),
      'endTimeSounded': _endTimeSounded,
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
      _endTimeDeadline = switch (state['endTimeDeadline']) {
        final String value => DateTime.tryParse(value),
        _ => null,
      };
      _endTimeSounded = state['endTimeSounded'] == true;
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
        _smartRecordedElapsed = Duration(
            seconds:
                (state['smartRecordedElapsedSeconds'] as num?)?.toInt() ?? 0);
        _smartSavedAny = state['smartSavedAny'] == true;
        _smartSavedLines = (state['smartSavedLines'] as num?)?.toInt() ?? 0;
        _smartEntryId = switch (state['smartEntryId']) {
          final String id when id.isNotEmpty => id,
          _ => isSmart ? IdGenerator.generate() : null,
        };
      }
    });
    if (_clock.isActive &&
        _homeAdditions.endTimeAlertEnabled &&
        _endTimeDeadline == null) {
      _endTimeDeadline =
          nextClockOccurrence(DateTime.now(), _homeAdditions.endTimeMinutes);
    }
    if (!_homeAdditions.endTimeAlertEnabled) {
      _endTimeDeadline = null;
      _endTimeSounded = false;
      NotificationService().cancelWritingEndAlert();
    }
    if (_clock.isActive &&
        !_endTimeSounded &&
        _endTimeDeadline?.isAfter(DateTime.now()) == true) {
      NotificationService().scheduleWritingEndAlert(_endTimeDeadline!);
    }
    if (running) _syncPulse();
    _syncMetronome();
    _checkEndTimeAlert();
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

  BreakCountdown get _breakCountdown =>
      BreakCountdown(target: _breakTarget, elapsed: _clock.breakElapsed);

  /// A break is over the moment writing resumes, so nothing is left counting.
  void _clearBreakTarget() {
    _breakTarget = null;
    _chimeSounded = false;
    _lastBreakElapsed = Duration.zero;
  }

  Duration _markLineFinished() {
    final lapDuration = _clock.recordLap();
    showAppNote(context, "סיימתי שורה! זמן שורה: ${formatClock(lapDuration)}");
    return lapDuration;
  }

  void _recordLap() {
    _markLineFinished();
    // Reset the visible countdown now, not on the next one-second tick.
    if (mounted) setState(() {});
    // Plain mode has no position to checkpoint, but its line clock must still
    // survive the app going to sleep or being closed.
    _persistTimerState();
  }

  Future<void> _initSmartSession() async {
    if (_selectedProject == null) return;

    await _loadSmartPosition();
    if (!mounted) return;
    final positionError = _tefillinPositionError();
    if (positionError != null) {
      showAppError(context, positionError);
      return;
    }
    setState(() {
      _clock.clearBreaks();
      _smartRecordedElapsed = Duration.zero;
      _smartSavedAny = false;
      _smartSavedLines = 0;
      _smartEntryId = IdGenerator.generate();
      _smartLineSaving = false;
    });
    _startTimer();
  }

  /// Every way into a break goes through here.
  ///
  /// It used to also require the smart workflow, so a writer in plain mode
  /// switched the setting on, pressed "הפסקת קפה" and was never offered the
  /// thing the setting promised. The question belongs to the break, not to the
  /// workflow.
  void _onBreakTap() {
    if (_smartLineSaving) return;
    // Off means off: no question, and with no way left to name a length there
    // is nothing for a chime or an overrun clock to measure against.
    if (!_askBreakLength) {
      setState(() => _breakTarget = null);
      _pauseTimer();
      return;
    }
    _showBreakStartDialog();
  }

  Future<void> _showBreakStartDialog() async {
    final minutesCtrl = TextEditingController();
    var chime = _breakChime;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
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
                  labelText: "אורך ההפסקה בדקות (אופציונלי – השאר ריק)",
                  hintText: "למשל 10",
                ),
              ),
              // Here rather than in settings, so it can be decided in the
              // moment: stepping out of the room wants it, stretching at the
              // desk does not. The answer is remembered for the next break.
              SwitchListTile(
                value: chime,
                onChanged: (v) => setDialog(() => chime = v),
                title: const Text("צליל בסיום הזמן"),
                contentPadding: EdgeInsets.zero,
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
      ),
    );
    final minutes = int.tryParse(minutesCtrl.text.trim());
    minutesCtrl.dispose();
    if (result != true || !mounted) return;
    if (chime != _breakChime) {
      _breakChime = chime;
      await _storageService.setBreakChime(chime);
    }
    if (minutes != null && minutes > 0) {
      await NotificationService().scheduleBreakReminder(minutes);
    }
    if (!mounted) return;
    setState(() {
      _breakTarget =
          (minutes != null && minutes > 0) ? Duration(minutes: minutes) : null;
      _chimeSounded = false;
      _lastBreakElapsed = Duration.zero;
    });
    _pauseTimer();
  }

  /// Watches the break against the length that was set for it.
  ///
  /// Asked on every tick rather than scheduled for the end, so a break that
  /// runs out while the app is asleep is still announced when it wakes — a
  /// timer firing on a dead isolate sounds to nobody.
  void _checkBreakChime() {
    final target = _breakTarget;
    if (target == null || _chimeSounded || !_clock.isPaused) return;
    final now = _clock.breakElapsed;
    final due = BreakCountdown(target: target, elapsed: now)
        .chimeDue(previousElapsed: _lastBreakElapsed, enabled: _breakChime);
    _lastBreakElapsed = now;
    if (!due) return;
    _chimeSounded = true;
    SystemSound.play(SystemSoundType.alert);
  }

  /// Keeps the click entirely tied to active writing. The interval is rebuilt
  /// after a settings change, start, pause or resume, so there is never a
  /// second metronome left ticking at the old tempo.
  void _syncMetronome() {
    _metronomeTimer?.cancel();
    _metronomeTimer = null;
    if (!_homeAdditions.metronomeEnabled ||
        !_clock.isRunning ||
        _clock.isPaused) {
      return;
    }
    _metronomeTimer = Timer.periodic(
      metronomeInterval(_homeAdditions.metronomeBpm),
      (_) {
        if (_clock.isRunning && !_clock.isPaused) {
          SystemSound.play(SystemSoundType.click);
        }
      },
    );
  }

  /// The Android booking covers the app being asleep; this check covers an
  /// open Windows app and also gives an immediate on-screen message.
  void _checkEndTimeAlert() {
    final deadline = _endTimeDeadline;
    if (!_homeAdditions.endTimeAlertEnabled ||
        !_clock.isActive ||
        _endTimeSounded ||
        deadline == null ||
        DateTime.now().isBefore(deadline)) {
      return;
    }
    _endTimeSounded = true;
    NotificationService().cancelWritingEndAlert();
    SystemSound.play(SystemSoundType.alert);
    showAppNote(context, 'הגעת לשעת הסיום שקבעת לישיבה');
    _persistTimerState();
  }

  Future<void> _smartNextLine() async {
    if (_smartLineSaving) return;
    // Once a valid segment starts, finishing one parshiya makes the following
    // one valid inside that same segment even before the segment is saved.
    // A restored timer is checked from its saved start for the same reason.
    final positionError = _tefillinPositionError(slotIndex: _smartStartPage);
    if (positionError != null) {
      showAppError(context, positionError);
      return;
    }
    _markLineFinished();

    setState(() {
      _smartLineSaving = true;
      _smartCurrentLine++;

      if (_selectedProject?.type == ProjectType.tefillin) {
        // A parshiya, not a page: four ruled lines on a head and seven on a
        // hand. Rolling over at the sefer's forty-two meant the position never
        // left the first parshiya of the first pair.
        final at = TefillinPosition.fromSlotIndex(_smartCurrentPage);
        if (_smartCurrentLine > TefillinUnits.linesIn(at.side)) {
          _smartCurrentLine = 1;
          _smartCurrentPage++;
        }
      } else if (_selectedProject?.type == ProjectType.mezuza) {
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

    final saved = await _commitSmartSegment();
    await _storageService.saveLastPosition(
        _selectedProject!.id, _smartCurrentPage, _smartCurrentLine);
    if (saved) await _persistTimerState();
    if (mounted) setState(() => _smartLineSaving = false);
  }

  /// Prevents an old stored position, or a restored timer from an older build,
  /// from bypassing the order enforced by the new position picker.
  String? _tefillinPositionError({int? slotIndex}) {
    final project = _selectedProject;
    if (project?.type != ProjectType.tefillin) return null;

    final at = TefillinPosition.fromSlotIndex(slotIndex ?? _smartCurrentPage);
    final slots = TefillinState.slots(project!, history);
    final slot = slots.firstWhere(
      (s) =>
          s.pair == at.pair && s.side == at.side && s.parshiya == at.parshiya,
      orElse: () => TefillinSlot(
        pair: at.pair,
        side: at.side,
        parshiya: at.parshiya,
      ),
    );
    if (TefillinState.canWrite(slot, slots)) return null;

    final name = TefillinUnits.names[at.parshiya - 1];
    return switch (slot.state) {
      SlotState.done => 'פרשיית $name כבר הסתיימה. יש לבחור את הפרשייה הבאה.',
      SlotState.voided =>
        'פרשיית $name נפסלה. יש להסיר אותה ממפת התפילין לפני התחלה מחדש.',
      _ => 'אי אפשר להתחיל את $name לפני שהפרשייה הקודמת הסתיימה באותו סט.',
    };
  }

  Future<void> _showEditPositionDialog() async {
    if (_selectedProject == null) return;

    // Tefillin does not answer this with numbers. Eighty slots in a ten-pair
    // order, and the answer is nearly always one of five: where he stopped,
    // what is held for correction, or the next in writing order.
    if (_selectedProject!.type == ProjectType.tefillin) {
      await _showTefillinPositionSheet();
      return;
    }

    if (_selectedProject!.type == ProjectType.mezuza) {
      await _showMezuzaPositionSheet();
      return;
    }

    final pageCtrl =
        TextEditingController(text: formatHebrewNumber(_smartCurrentPage));
    final lineCtrl = TextEditingController(text: _smartCurrentLine.toString());
    final maxLines = ProductionCalculator.linesPerPageOf(_selectedProject!);
    final maxPages = _selectedProject!.totalPages ?? 245;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("עריכת מיקום בפרויקט"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pageCtrl,
              decoration: const InputDecoration(
                labelText: "עמוד",
                hintText: "אותיות (למשל: יא)",
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
    final page = parseHebrewPageToNumber(pageCtrl.text);
    final line = int.tryParse(lineCtrl.text) ?? _smartCurrentLine;
    pageCtrl.dispose();
    lineCtrl.dispose();
    if (ok != true || !mounted) return;
    final p = (page <= 0 ? _smartCurrentPage : page).clamp(1, maxPages);
    final l = line.clamp(1, maxLines);
    await _moveSmartPosition(p, l);
  }

  /// Moving about a tefillin commission without leaving the timer.
  Future<void> _showTefillinPositionSheet() async {
    final project = _selectedProject;
    if (project == null) return;

    final at = TefillinPosition.fromSlotIndex(_smartCurrentPage);
    final slots = TefillinState.slots(project, history);
    TefillinSlot? here;
    for (final s in slots) {
      if (s.pair == at.pair && s.side == at.side && s.parshiya == at.parshiya) {
        here = s;
      }
    }

    final picked = await showModalBottomSheet<TefillinSlot>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      builder: (ctx) => TefillinPositionSheet(
        current: at,
        currentLine: _smartCurrentLine,
        currentStartedOn: here?.startedOn,
        useGregorianDates: _useGregorianDates,
        picks: TefillinPicks.from(slots, current: at),
        onPick: (slot) => Navigator.pop(ctx, slot),
      ),
    );
    if (picked == null || !mounted) return;

    final to = TefillinPosition(
        pair: picked.pair, side: picked.side, parshiya: picked.parshiya);
    // A parshiya part-written resumes on the line after the last one written;
    // an untouched one starts at its first.
    final line =
        picked.state == SlotState.partial ? picked.linesWritten + 1 : 1;

    await _moveSmartPosition(to.slotIndex, line);
  }

  /// The same short, tap-only position list for a run of mezuzot.
  Future<void> _showMezuzaPositionSheet() async {
    final project = _selectedProject;
    if (project == null) return;

    final slots = MezuzaState.slots(project, history);
    MezuzaSlot? here;
    for (final slot in slots) {
      if (slot.index == _smartCurrentPage) here = slot;
    }

    final picked = await showModalBottomSheet<MezuzaSlot>(
      context: context,
      backgroundColor: Colors.transparent,
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      builder: (ctx) => MezuzaPositionSheet(
        current: _smartCurrentPage,
        currentLine: _smartCurrentLine,
        currentStartedOn: here?.startedOn,
        useGregorianDates: _useGregorianDates,
        picks: MezuzaPicks.from(slots, current: _smartCurrentPage),
        onPick: (slot) => Navigator.pop(ctx, slot),
      ),
    );
    if (picked == null || !mounted) return;
    await _moveSmartPosition(picked.index, picked.resumeLine);
  }

  /// Leaves the current mezuza where it is and moves to the next untouched
  /// one. Any lines marked in this stretch are filed first, while the clock
  /// itself keeps running.
  Future<void> _skipMezuza() async {
    if (_smartLineSaving) return;
    final project = _selectedProject;
    if (project?.type != ProjectType.mezuza) return;

    if (_clock.isActive && !await _commitSmartSegment()) return;
    final slots = MezuzaState.slots(project!, history);
    MezuzaSlot? next;
    for (final slot in slots) {
      if (slot.index > _smartCurrentPage &&
          slot.state == MezuzaSlotState.empty) {
        next = slot;
        break;
      }
    }
    next ??= MezuzaSlot(
      index: (slots.isEmpty ? _smartCurrentPage : slots.last.index) + 1,
      state: MezuzaSlotState.empty,
      linesWritten: 0,
    );
    await _setSmartPosition(next.index, 1);
  }

  /// Changes the location without pretending that the stretch before and the
  /// stretch after the jump were continuous work. If the timer is active, the
  /// first stretch is filed before the new location becomes current.
  Future<void> _moveSmartPosition(int page, int line) async {
    if (page == _smartCurrentPage && line == _smartCurrentLine) return;
    if (_clock.isActive && !await _commitSmartSegment()) return;
    await _setSmartPosition(page, line);
  }

  Future<void> _setSmartPosition(int page, int line) async {
    final project = _selectedProject;
    if (project == null || !mounted) return;
    setState(() {
      _smartCurrentPage = page;
      _smartCurrentLine = line;
      _smartStartPage = page;
      _smartStartLine = line;
      _smartRecordedElapsed = _clock.isActive ? _clock.elapsed : Duration.zero;
    });
    await _storageService.saveLastPosition(project.id, page, line);
    if (_clock.isActive) await _persistTimerState();
  }

  /// Files the current smart-mode stretch while leaving the stopwatch alive.
  Future<bool> _commitSmartSegment() async {
    final project = _selectedProject;
    if (project == null || !_clock.isActive) return true;

    final elapsed = _clock.elapsed;
    final worked = elapsed > _smartRecordedElapsed
        ? elapsed - _smartRecordedElapsed
        : Duration.zero;
    final outcome = SmartSessionBuilder.build(
      project: project,
      from: SmartPosition(_smartStartPage, _smartStartLine),
      to: SmartPosition(_smartCurrentPage, _smartCurrentLine),
      worked: worked,
      endedAt: DateTime.now(),
      history: history,
      entryId: _smartEntryId,
    );

    switch (outcome) {
      case SmartRejected(:final message):
        showAppError(context, message);
        return false;
      case SmartNothingWritten():
        return true;
      case SmartRecorded(
          :final sessions,
          :final linesWritten,
          :final overlappingPages,
        ):
        if (overlappingPages.isNotEmpty &&
            !await _confirmSmartOverlap(overlappingPages)) {
          return false;
        }
        if (!mounted) return false;
        final checkpoint = _stampWorkingDay(sessions);
        final goalWasMet = _dailyGoalMet(project);
        setState(() {
          history = SmartLiveRecording.merge(history, checkpoint);
          _smartStartPage = _smartCurrentPage;
          _smartStartLine = _smartCurrentLine;
          _smartRecordedElapsed = elapsed;
          _smartSavedAny = true;
          _smartSavedLines += linesWritten;
        });
        await _storageService.saveHistory(history);
        _celebrateIfReached(project, wasMet: goalWasMet);
        return true;
    }
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

    final remaining = _clock.lastSitting > _smartRecordedElapsed
        ? _clock.lastSitting - _smartRecordedElapsed
        : Duration.zero;

    final outcome = SmartSessionBuilder.build(
      project: project,
      from: SmartPosition(_smartStartPage, _smartStartLine),
      to: SmartPosition(_smartCurrentPage, _smartCurrentLine),
      worked: remaining,
      endedAt: _clock.endedAt ?? DateTime.now(),
      history: history,
      entryId: _smartEntryId,
    );

    switch (outcome) {
      case SmartRejected(:final message):
        showAppError(context, message);
        return;
      case SmartNothingWritten():
        if (!_smartSavedAny) {
          showAppError(context, "לא נרשמה התקדמות בכתיבה");
          return;
        }
        final totalLines = _smartSavedLines;
        setState(() {
          _smartRecordedElapsed = Duration.zero;
          _smartSavedAny = false;
          _smartSavedLines = 0;
          _smartEntryId = null;
          _smartLineSaving = false;
        });
        showAppSuccess(
          context,
          breakDuration > Duration.zero
              ? "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.\n"
                  "זמן כתיבה נטו: ${formatClock(_clock.lastSitting)}, "
                  "זמן הפסקה: ${formatClock(breakDuration)}"
              : "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.",
        );
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

        final totalLines = _smartSavedLines + linesWritten;
        final finalRecords = _stampWorkingDay(sessions);
        final goalWasMet = _dailyGoalMet(project);
        setState(() {
          history = SmartLiveRecording.merge(history, finalRecords);
          _smartRecordedElapsed = Duration.zero;
          _smartSavedAny = false;
          _smartSavedLines = 0;
          _smartEntryId = null;
          _smartLineSaving = false;
        });
        await _storageService.saveHistory(history);
        await _storageService.saveLastPosition(
            project.id, _smartCurrentPage, _smartCurrentLine);
        _celebrateIfReached(project, wasMet: goalWasMet);

        if (!mounted) return;
        showAppSuccess(
          context,
          breakDuration > Duration.zero
              ? "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.\n"
                  "זמן כתיבה נטו: ${formatClock(_clock.lastSitting)}, "
                  "זמן הפסקה: ${formatClock(breakDuration)}"
              : "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.",
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
    final goalWasMet = _dailyGoalMet(save.project);
    setState(() {
      history.addAll(_stampWorkingDay(save.sessions));
    });
    // The sheet awaits this callback. Do not tell it the save is complete
    // until the history is actually durable; "save and continue" can otherwise
    // start a second write while the first JSON value is still being stored.
    await _storageService.saveHistory(history);
    _celebrateIfReached(save.project, wasMet: goalWasMet);

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

  bool _dailyGoalMet(Project project) => DailyGoal.isMet(
        project: project,
        history: history,
        day: DateTime.now(),
        dayStart: _dayStart,
      );

  /// Appears only on the transition from below the target to at-or-above it.
  /// Reopening the app or adding another record later that day cannot replay
  /// the same celebration.
  void _celebrateIfReached(Project project, {required bool wasMet}) {
    if (!_homeAdditions.celebrateDailyGoal ||
        project.targetDaily <= 0 ||
        wasMet ||
        !_dailyGoalMet(project) ||
        !mounted) {
      return;
    }
    _celebrationTimer?.cancel();
    setState(() => _goalCelebrationVisible = true);
    _celebrationTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _goalCelebrationVisible = false);
    });
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
    if (project.type != ProjectType.sefer &&
        project.type != ProjectType.mezuza) {
      return;
    }
    late final SmartPosition next;
    if (project.type == ProjectType.mezuza) {
      final position = MezuzaState.nextWritingPosition(project, history);
      next = SmartPosition(position.page, position.line);
    } else {
      if (page <= 0) return;
      next = SmartPosition.after(
        page: page,
        line: lastLine,
        linesPerUnit: ProductionCalculator.linesPerPageOf(project),
      );
    }

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
    // Stop the clock before the records go. A running sitting outlived the
    // reset and went on counting against a commission that no longer existed.
    if (_clock.isActive) _clock.stop();
    await _storageService.eraseAllRecords();
    if (!mounted) return;
    setState(() {
      projects = [];
      history = [];
      _selectedProject = null;
      _hasStoredPosition = false;
      _smartCurrentPage = 1;
      _smartCurrentLine = 1;
      _smartStartPage = 1;
      _smartStartLine = 1;
      _smartRecordedElapsed = Duration.zero;
      _smartSavedAny = false;
      _smartSavedLines = 0;
      _smartEntryId = null;
      _smartLineSaving = false;
    });
    _syncPulse();
  }

  /// Re-reads everything from disk.
  ///
  /// The recycle bin and the backup importer both write records directly, and
  /// the screens they were opened from held the list they had at the time — so
  /// a restored project and an imported history announced success and then did
  /// not appear until the app was restarted.
  Future<void> _reloadAfterExternalChange() => _loadData();

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
            setState(
                () => projects.removeWhere((element) => element.id == p.id));
          },
          onResetAllData: _resetAllData,
        ),
      ),
    );
    // The recycle bin lives behind this screen and writes straight to storage,
    // so what is in memory here can be out of date by the time it closes.
    await _reloadAfterExternalChange();
  }

  Future<void> _refreshSettingsFromStorage() async {
    final smartEnabled = await _storageService.getSmartWorkflowEnabled();
    final dayStart = await _storageService.getDayStart();
    // Reloaded here too, or a writer who turns the break question off in
    // settings and comes straight back finds it still asking until he restarts
    // the app.
    final askBreakLength = await _storageService.getAskBreakLength();
    final breakChime = await _storageService.getBreakChime();
    final useGregorian = await _storageService.getUseGregorianDates();
    final workRules = await _storageService.getWorkCalendarRules();
    final homeAdditions = await _storageService.getHomeAdditions();
    if (!mounted) return;
    final previous = _homeAdditions;
    setState(() {
      _isSmartWorkflow = smartEnabled;
      _dayStart = dayStart;
      _askBreakLength = askBreakLength;
      _breakChime = breakChime;
      _useGregorianDates = useGregorian;
      _workRules = workRules;
      _homeAdditions = homeAdditions;
      if (!_clock.isActive || !homeAdditions.endTimeAlertEnabled) {
        _endTimeDeadline = null;
        _endTimeSounded = false;
      } else if (!previous.endTimeAlertEnabled ||
          previous.endTimeMinutes != homeAdditions.endTimeMinutes) {
        _endTimeDeadline =
            nextClockOccurrence(DateTime.now(), homeAdditions.endTimeMinutes);
        _endTimeSounded = false;
      }
    });
    _syncMetronome();
    final deadline = _endTimeDeadline;
    if (!homeAdditions.endTimeAlertEnabled) {
      NotificationService().cancelWritingEndAlert();
    } else if (_clock.isActive && deadline != null) {
      NotificationService().scheduleWritingEndAlert(deadline);
      _persistTimerState();
    }
  }

  void _navigateToSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    );
    await _refreshSettingsFromStorage();
    final shortcuts = await _storageService.getShortcuts();
    if (mounted) setState(() => _shortcuts = shortcuts);
    // Importing a backup writes records from in there. It reported success and
    // then nothing appeared until the app was restarted.
    await _reloadAfterExternalChange();
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
            setState(() =>
                history = updatedHistory.where((s) => !s.isDeleted).toList());
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

  /// Runs a shortcut, if the key pressed is one and the moment allows it.
  ///
  /// Refused while a text field has focus. A shortcut is a key the writer is
  /// not otherwise using, and while he is typing a page number every key is one
  /// he is using — a bare letter stopping the timer mid-entry is exactly the
  /// failure this guards against, which is also why a bare letter cannot be
  /// bound in the first place.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }

    final action = _shortcuts.actionFor(
      event,
      pressed: HardwareKeyboard.instance.logicalKeysPressed,
    );
    if (action == null) return KeyEventResult.ignored;

    // Space and Enter, bound bare, are also how the framework presses whatever
    // has focus. Left alone they would do two things at once — press the button
    // the writer last clicked and run the shortcut — so they only count when
    // nothing else has taken the focus. Anything with a modifier is unambiguous
    // and always counts.
    if ((_shortcuts[action]?.mayActivateFocusedControl ?? false) &&
        FocusManager.instance.primaryFocus != _keyboardFocus) {
      return KeyEventResult.ignored;
    }

    switch (action) {
      case ShortcutAction.startStop:
        if (_clock.isActive) {
          _stopTimer();
        } else if (_selectedProject != null) {
          _isSmartWorkflow ? _initSmartSession() : _startTimer();
        } else {
          showAppNote(context, "יש לבחור פרויקט לפני התחלת ישיבה");
        }
      case ShortcutAction.takeBreak:
        // Nothing to break from, and nothing to come back to.
        if (_clock.isActive) _onBreakTap();
      case ShortcutAction.markLine:
        if (_clock.isRunning && !_clock.isPaused) {
          _isSmartWorkflow ? _smartNextLine() : _recordLap();
        }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(event),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (Platform.isWindows && (widget.windowsFloatingMode?.value ?? false)) {
      return FloatingTimerWindow(
        clock: _clock,
        onStart: _startTimer,
        // Straight to the break, with no length asked for: the dialog would
        // open in the main window, which is the one the writer has just
        // folded away.
        onPause: () {
          setState(() => _breakTarget = null);
          _pauseTimer();
        },
        onStop: _stopTimer,
        onLap: () {
          if (_isSmartWorkflow) {
            _smartNextLine();
          } else {
            _recordLap();
          }
        },
        onRestore: _restoreFromFloatingWindow,
        lineSaving: _smartLineSaving,
      );
    }

    final homeSnapshot = _buildHomeSnapshot();

    // The ruled themes share one home screen for both workflows; the cards
    // theme keeps the two it has always had.
    if (SoferTokens.of(context).isRules) {
      return Scaffold(
        appBar: _homeAppBar(),
        body: _withCelebration(
          RuledHomeBody(
            snapshot: homeSnapshot,
            actions: _homeActions,
            isSmart: _isSmartWorkflow,
          ),
        ),
        bottomNavigationBar: _homeBottomNav(),
      );
    }

    if (_isSmartWorkflow) {
      return Scaffold(
        appBar: _homeAppBar(),
        body: _withCelebration(
          CardsSmartBody(
            snapshot: homeSnapshot,
            actions: _homeActions,
            pulse: _pulseAnimation,
          ),
        ),
        bottomNavigationBar: _homeBottomNav(),
      );
    }

    return Scaffold(
      appBar: _homeAppBar(),
      body: _withCelebration(LayoutBuilder(
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
                            child: _ModernClockDisplay(
                              elapsed: homeSnapshot.elapsed,
                              line: homeSnapshot.shownLineValue,
                              lineLabel: homeSnapshot.shownLineLabel,
                              lineOverrun: homeSnapshot.lineClockOverrun,
                              active: _clock.isActive,
                              paused: _clock.isPaused,
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
                                        color:
                                            Colors.brown.withValues(alpha: 0.2),
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
                      if (homeSnapshot.hasHomeAdditions) ...[
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: HomeAdditionsPanel(snapshot: homeSnapshot),
                          ),
                        ),
                      ],
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
                                  onPressed: _clock.isPaused
                                      ? _startTimer
                                      : _onBreakTap,
                                  icon: Icon(_clock.isPaused
                                      ? Icons.play_arrow
                                      : Icons.coffee),
                                  label: Text(
                                      _clock.isPaused ? "המשך" : "הפסקת קפה"),
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
      )),
      // The same bar as every other layout. This used to be a second copy —
      // same four destinations, same routing, written out again in the older
      // Material widget with its colours hardcoded, so smart mode was the one
      // screen the theme did not reach.
      bottomNavigationBar: _homeBottomNav(),
    );
  }

  Widget _withCelebration(Widget child) => Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_goalCelebrationVisible) const GoalCelebrationOverlay(),
        ],
      );
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

class _ModernClockDisplay extends StatelessWidget {
  final String elapsed;
  final String line;
  final String lineLabel;
  final bool lineOverrun;
  final bool active;
  final bool paused;

  const _ModernClockDisplay({
    required this.elapsed,
    required this.line,
    required this.lineLabel,
    required this.lineOverrun,
    required this.active,
    required this.paused,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return Text(elapsed,
          style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200));
    }

    Widget metric(String label, String value, double size,
            {bool danger = false}) =>
        Expanded(
          child: Column(
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      color: paused ? Colors.grey : Colors.brown.shade700)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: TextStyle(
                        fontSize: size,
                        fontWeight: FontWeight.w200,
                        color: danger
                            ? SoferTokens.of(context).danger
                            : paused
                                ? Colors.grey
                                : null)),
              ),
            ],
          ),
        );

    return SizedBox(
      width: 520,
      child: Row(
        children: [
          metric('זמן כתיבה', elapsed, 52),
          Container(
              width: 1,
              height: 60,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.brown.shade200),
          metric(lineLabel, line, 40, danger: lineOverrun),
        ],
      ),
    );
  }
}
