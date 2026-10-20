import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'entry/entry_sheet.dart';
import 'entry/entry_draft.dart';
import 'format.dart';
import 'logic/break_timing.dart';
import 'logic/date_logic.dart';
import 'logic/hebrew_clock.dart';
import 'logic/keyboard_shortcuts.dart';
import 'logic/home_additions.dart';
import 'logic/writing_journal.dart';
import 'logic/measured_work.dart';
import 'logic/metronome_audio.dart';
import 'logic/partial_line_recording.dart';
import 'logic/production_calculator.dart';
import 'logic/timer_controller.dart';
import 'logic/smart_session.dart';
import 'logic/smart_live_recording.dart';
import 'logic/tefillin_text.dart';
import 'logic/entry_builder.dart';
import 'entry/tefillin_words_dialog.dart';
import 'logic/id_generator.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'projects_screen.dart';
import 'storage_service.dart';
import 'summary_screen.dart';
import 'features_screen.dart';
import 'help/help_screen.dart';
import 'writing_journal_screen.dart';
import 'notification_service.dart';
import 'hebrew_utils.dart';
import 'home/ruled_home_body.dart';
import 'home/mezuza_position_sheet.dart';
import 'home/tefillin_position_sheet.dart';
import 'logic/completion_estimator.dart';
import 'logic/mezuza_state.dart';
import 'logic/megillah_format.dart';
import 'logic/tefillin_position.dart';
import 'logic/tefillin_state.dart';
import 'logic/tefillin_units.dart';
import 'logic/hebrew_work_calendar.dart';
import 'logic/json_compat.dart';
import 'logic/profit_calculator.dart';
import 'theme/app_theme.dart';
import 'widgets/feedback.dart';
import 'widgets/confirm.dart';
import 'logic/daily_goal.dart';
import 'home/floating_window.dart';
import 'home/cards_smart_body.dart';
import 'l10n/app_localizations.dart';

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
  bool _timerCheckpointSaving = false;
  Completer<void>? _timerCheckpointDone;

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
  WritingJournalSettings _journalSettings = WritingJournalSettings.defaults;
  bool _journalHomeTemporarilyHidden = false;
  final MetronomeAudio _metronomeAudio = MetronomeAudio();
  Timer? _metronomeTimer;
  int? _sessionTargetMinutes;
  bool _sessionTargetSounded = false;
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

  /// Smart-mode time that was already attached to confirmed lines before the
  /// writer deliberately switched to plain entry. The visible timer keeps its
  /// full sitting; the closing form receives only the unfiled remainder, so
  /// one minute at the desk can never be counted twice.
  Duration _plainAlreadyRecordedElapsed = Duration.zero;

  /// One identity for every checkpoint written during the sitting. A line is
  /// durable as soon as it is marked, while all lines on the same physical
  /// page still fold back into one record.
  String? _smartEntryId;
  bool _smartLineSaving = false;
  bool _stopAfterLineSave = false;
  bool _stoppingTimer = false;
  bool _reviewingLineTime = false;
  bool _pendingEntryRecoveryScheduled = false;

  /// Whether the chosen commission has a position stored from a previous
  /// sitting. Distinct from the position being 1,1, which is where a writer who
  /// has genuinely begun at the beginning stands.
  bool _hasStoredPosition = false;

  DayStart _dayStart = DayStart.midnight;
  bool _useGregorianDates = false;

  /// Needed for the completion estimate the ruled home screen shows.
  WorkCalendarRules _workRules = WorkCalendarRules.standard;

  Duration get _carriedCurrentLineTime {
    final project = _selectedProject;
    if (!_isSmartWorkflow || project == null) return Duration.zero;
    return PartialLineRecording.carriedTime(
      history,
      project,
      SmartPosition(_smartCurrentPage, _smartCurrentLine),
    );
  }

  Duration get _currentLineElapsed =>
      _carriedCurrentLineTime + _clock.sinceLastLap;

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
      _checkSessionTargetChime();
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
    _metronomeAudio.dispose();
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
      final journalSettings = await _storageService.getWritingJournalSettings();
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
        _journalSettings = journalSettings;
        _selectedProject = _pickStartingProject(activeProjects, lastId);
      });
      if (_isSmartWorkflow && _selectedProject != null) {
        await _loadSmartPosition();
      }
      await _restoreTimerState();
      await _restorePendingEntry();
    } catch (e) {
      debugPrint("Error loading data: $e");
    }
  }

  String _getDisplayDate(DateTime date) {
    return formatDisplayDate(
      date,
      _useGregorianDates,
      english: context.l10n.isEnglish,
    );
  }

  /// Flips between the two workflows after an explicit confirmation.
  ///
  /// This used to live in settings. It is something a writer changes between
  /// sittings — smart when they are picking up where they left off, plain when
  /// they will say afterwards what they wrote — so it belongs where the work
  /// starts, not behind a settings screen.
  ///
  /// Smart → plain is the recovery path for a writer who forgot to mark one or
  /// more lines. The clock stays alive and the already-filed smart time is
  /// remembered, so the closing form receives only the unrecorded remainder.
  /// Plain → smart is still refused mid-sitting: no position exists for the
  /// work already typed only in the writer's head.
  Future<void> _setWorkflowMode(bool next) async {
    final movingActiveSmartToPlain = _clock.isActive && !next;
    await _storageService.setSmartWorkflowEnabled(next);
    if (!mounted) return;
    setState(() {
      if (movingActiveSmartToPlain) {
        _plainAlreadyRecordedElapsed = _smartRecordedElapsed;
      }
      _isSmartWorkflow = next;
    });
    if (movingActiveSmartToPlain) await _persistTimerState();
    // Switching into smart mode with a project already chosen: bring its stored
    // position along, so the position on screen is the real one immediately.
    if (next) await _loadSmartPosition();
  }

  Future<void> _toggleWorkflowMode() async {
    if (_smartLineSaving) {
      showAppError(
        context,
        context.l10n.pick(
          he: "יש להמתין עד ששמירת השורה תסתיים",
          en: "Wait for the line to finish saving",
        ),
      );
      return;
    }
    final next = !_isSmartWorkflow;
    if (_clock.isActive && next) {
      showAppError(
        context,
        context.l10n.pick(
          he: "אי אפשר לעבור למצב חכם באמצע ישיבה רגילה. יש לסיים את הישיבה ולהתחיל ישיבה חדשה במצב חכם.",
          en: "You cannot switch to Smart Mode during a Regular Mode session. Finish this session, then start a new one in Smart Mode.",
        ),
      );
      return;
    }

    // Between sittings this is a preference, not a risky data transition. The
    // confirmation belongs only to switching while a timer is carrying work.
    if (!_clock.isActive) {
      await _setWorkflowMode(next);
      return;
    }

    final movingActiveSmartToPlain = _clock.isActive && !next;
    final confirmed = await confirmAction(
      context,
      title: next
          ? context.l10n.pick(
              he: "לעבור למצב חכם?",
              en: "Switch to Smart Mode?",
            )
          : context.l10n.pick(
              he: "לעבור למצב רגיל?",
              en: "Switch to Regular Mode?",
            ),
      message: movingActiveSmartToPlain
          ? context.l10n.pick(
              he: "הטיימר ימשיך מאותו זמן. שורות שכבר סימנת נשמרו. בסיום הישיבה יש להזין רק את השורות שלא סימנת; רק הזמן מאז השורה האחרונה שנשמרה יצורף אליהן.",
              en: "The timer will continue from the same time. Lines you already marked are saved. At the end, enter only the unmarked lines; only the time since the last saved line will be assigned to them.",
            )
          : next
              ? context.l10n.pick(
                  he: "במצב חכם כל לחיצה על „סיימתי שורה” מעדכנת מיד את המיקום ואת ההספק.",
                  en: "In Smart Mode, every tap on “Finished a line” immediately updates the position and Output.",
                )
              : context.l10n.pick(
                  he: "במצב רגיל הטיימר נמדד, ובסיום מזינים ידנית מה נכתב.",
                  en: "In Regular Mode, the timer measures your work and you enter what was written at the end.",
                ),
      cancelLabel: context.l10n.pick(
        he: "הישאר במצב הנוכחי",
        en: "Stay in current mode",
      ),
      confirmLabel: context.l10n.pick(he: "כן, עבור", en: "Switch"),
    );
    if (!confirmed || !mounted) return;
    await _setWorkflowMode(next);
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
        case ProjectType.megillah:
          final lines = ProductionCalculator.seferLinesTotal(todaySessions);
          todayOutput = context.l10n.pick(
            he: "$lines שורות",
            en: "$lines lines",
          );
        case ProjectType.mezuza:
          final lines = ProductionCalculator.mezuzaLinesTotal(todaySessions);
          todayOutput = context.l10n.pick(
            he: "${(lines / ProductionCalculator.linesPerMezuza).toStringAsFixed(1)} מזוזות",
            en: "${(lines / ProductionCalculator.linesPerMezuza).toStringAsFixed(1)} Mezuzot",
          );
        case ProjectType.tefillin:
          // In sefer lines, so a day on tefillin can be held against a day on
          // anything else. A count of parshiyot could not be.
          final lines =
              ProductionCalculator.tefillinSeferLinesTotal(todaySessions);
          todayOutput = context.l10n.pick(
            he: "מקביל ל־${lines.toStringAsFixed(0)} שורות של ס״ת",
            en: "Equivalent to ${lines.toStringAsFixed(0)} Sefer Torah lines",
          );
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
        progress = MegillahFormat.displayedProgress(project, estimate.progress);
        final unit = switch (project.type) {
          ProjectType.sefer => context.l10n.pick(he: "עמודים", en: "pages"),
          ProjectType.megillah => context.l10n.pick(he: "עמודים", en: "pages"),
          ProjectType.mezuza => context.l10n.pick(he: "מזוזות", en: "Mezuzot"),
          ProjectType.tefillin => context.l10n.pick(he: "זוגות", en: "sets"),
        };
        doneOfTotal = context.l10n.pick(
          he: "${estimate.doneUnits.toStringAsFixed(0)} מתוך ${estimate.totalUnits.toStringAsFixed(0)} $unit",
          en: "${estimate.doneUnits.toStringAsFixed(0)} of ${estimate.totalUnits.toStringAsFixed(0)} $unit",
        );
        completion = formatDisplayDateWithWeekday(
          estimate.plan.completionDate,
          _useGregorianDates,
          english: context.l10n.isEnglish,
        );
        completionDetail = context.l10n.pick(
          he: "בעוד ${estimate.plan.calendarDays} ימים · ${estimate.workDaysLeft.toStringAsFixed(0)} ימי עבודה",
          en: "In ${estimate.plan.calendarDays} days · ${estimate.workDaysLeft.toStringAsFixed(0)} workdays",
        );
      }
    }

    final lineCountdown = TargetCountdown(
      target: _homeAdditions.lineTargetEnabled
          ? Duration(seconds: _homeAdditions.lineTargetSeconds)
          : null,
      elapsed: _currentLineElapsed,
    );
    final writingCountdown = TargetCountdown(
      target:
          _homeAdditions.writingTargetEnabled && _sessionTargetMinutes != null
              ? Duration(minutes: _sessionTargetMinutes!)
              : null,
      elapsed: _clock.elapsed,
    );
    String? writingStatus;
    if (_homeAdditions.writingTargetEnabled) {
      writingStatus = _sessionTargetMinutes == null
          ? context.l10n.pick(
              he: 'בחירת יעד לישיבה',
              en: 'Choose a session target',
            )
          : _clock.isActive
              ? writingCountdown.isOverrun
                  ? context.l10n.pick(
                      he: 'יעד הכתיבה · חריגה ${writingCountdown.label}',
                      en: 'Writing target · overtime ${writingCountdown.label}',
                    )
                  : context.l10n.pick(
                      he: 'יעד הכתיבה · נותרו ${writingCountdown.label}',
                      en: 'Writing target · ${writingCountdown.label} remaining',
                    )
              : context.l10n.pick(
                  he: 'יעד הכתיבה · ${formatClock(Duration(minutes: _sessionTargetMinutes!))}',
                  en: 'Writing target · ${formatClock(Duration(minutes: _sessionTargetMinutes!))}',
                );
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
            ? context.l10n.pick(
                he: 'שעת סיום $configured · חריגה $signed',
                en: 'Finish time $configured · overtime $signed',
              )
            : context.l10n.pick(
                he: 'שעת סיום $configured · נותרו $signed',
                en: 'Finish time $configured · $signed remaining',
              );
      } else {
        endTimeStatus = context.l10n.pick(
          he: 'התראה בשעת סיום · $configured',
          en: 'Finish-time alert · $configured',
        );
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
      sinceLastLap: formatClock(_currentLineElapsed),
      lineClockLabel: _homeAdditions.lineTargetEnabled
          ? context.l10n.pick(he: 'יעד לשורה', en: 'Line target')
          : context.l10n.pick(he: 'זמן השורה', en: 'Line time'),
      lineClockValue:
          _homeAdditions.lineTargetEnabled ? lineCountdown.label : null,
      lineClockOverrun: lineCountdown.isOverrun,
      writingTargetStatus: writingStatus,
      writingTargetOverrun: writingCountdown.isOverrun,
      showWritingTargetButton: _homeAdditions.writingTargetEnabled,
      endTimeStatus: endTimeStatus,
      endTimeOverrun: endTimeOverrun,
      metronomeBpm:
          _homeAdditions.metronomeEnabled ? _homeAdditions.metronomeBpm : null,
      metronomeActive: _homeAdditions.metronomeEnabled &&
          _clock.isRunning &&
          !_clock.isPaused,
      isSavingLine: _smartLineSaving,
      wordEntry: _wordTefillin,
      // Read off the position already loaded rather than through a
      // FutureBuilder in the layout, which re-read storage on every rebuild.
      // Null and "page one" are different things: one is a commission never
      // touched, the other is one begun at the beginning.
      lastPosition: _hasStoredPosition
          ? context.l10n.pick(
              he: _wordTefillin
                  ? 'מיקום אחרון: ${_positionPageLabel(project)}'
                  : "מיקום אחרון: ${_positionPageLabel(project)}, שורה $_smartCurrentLine",
              en: _wordTefillin
                  ? 'Last position: ${_positionPageLabel(project)}'
                  : "Last position: ${_positionPageLabel(project)}, line $_smartCurrentLine",
            )
          : null,
      // Clamped at the display boundary too: whatever goes wrong upstream, the
      // screen never shows a page or line zero.
      currentLine: _smartCurrentLine < 1 ? 1 : _smartCurrentLine,
      pageLabel: _positionPageLabel(project),
      positionUnit: project?.type == ProjectType.tefillin
          ? context.l10n.pick(he: "פרשייה", en: "Parashah")
          : context.l10n.pick(he: "שורה", en: "Line"),
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

  Future<void> _pickSessionTarget() async {
    final chosen = await showModalBottomSheet<int>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(context.l10n.pick(
                  he: 'יעד לישיבה הנוכחית', en: 'Current session target')),
              subtitle: Text(context.l10n.pick(
                he: 'זמן כתיבה נטו; הפסקות אינן נספרות',
                en: 'Net writing time; breaks are not counted',
              )),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in const [30, 45, 60, 90])
                  ActionChip(
                    label: Text(minutes < 60
                        ? context.l10n
                            .pick(he: '$minutes דקות', en: '$minutes min')
                        : formatClock(Duration(minutes: minutes))),
                    onPressed: () => Navigator.pop(sheetContext, minutes),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.tune, size: 18),
                  label:
                      Text(context.l10n.pick(he: 'זמן אחר', en: 'Custom time')),
                  onPressed: () => Navigator.pop(sheetContext, -1),
                ),
              ],
            ),
            if (_sessionTargetMinutes != null)
              ListTile(
                leading:
                    Icon(Icons.clear, color: SoferTokens.of(context).danger),
                title: Text(context.l10n
                    .pick(he: 'הסר יעד מהישיבה', en: 'Remove session target')),
                onTap: () => Navigator.pop(sheetContext, 0),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    var minutes = chosen;
    if (chosen == -1) {
      final recent = _homeAdditions.writingTargetMinutes;
      final hoursController = TextEditingController(text: '${recent ~/ 60}');
      final minutesController =
          TextEditingController(text: '${recent.remainder(60)}');
      final custom = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.l10n
              .pick(he: 'זמן כתיבה מתוכנן', en: 'Planned writing time')),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: hoursController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: context.l10n.pick(he: 'שעות', en: 'Hours')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: minutesController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: context.l10n.pick(he: 'דקות', en: 'Minutes')),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final hours = int.tryParse(hoursController.text.trim()) ?? -1;
                final rest = int.tryParse(minutesController.text.trim()) ?? -1;
                final total = hours * 60 + rest;
                if (hours < 0 || rest < 0 || rest > 59 || total < 1) return;
                Navigator.pop(dialogContext, total.clamp(1, 24 * 60));
              },
              child: Text(context.l10n.pick(he: 'הגדר יעד', en: 'Set target')),
            ),
          ],
        ),
      );
      hoursController.dispose();
      minutesController.dispose();
      if (custom == null || !mounted) return;
      minutes = custom;
    }

    setState(() {
      _sessionTargetMinutes = minutes == 0 ? null : minutes;
      _sessionTargetSounded = false;
    });
    if (minutes > 0) {
      _homeAdditions = _homeAdditions.copyWith(writingTargetMinutes: minutes);
      await _storageService.setHomeAdditions(_homeAdditions);
    }
    if (_clock.isActive) await _persistTimerState();
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
      if (_wordTefillin) {
        final slots = TefillinState.slots(project!, history);
        final here = slots.where((s) =>
            s.pair == at.pair &&
            s.side == at.side &&
            s.parshiya == at.parshiya);
        final boundary = here.isEmpty ? null : here.first.wordBoundary;
        return context.l10n.pick(
            he: '${at.whereLabel} · ${boundary == null || boundary == 0 ? 'מתחילת הפרשייה' : 'אחרי ${TefillinText.of(at.parshiya).wordAt(boundary)} ($boundary)'}',
            en: '${_tefillinWhereLabel(at)} · ${boundary == null || boundary == 0 ? 'from the beginning' : 'after ${TefillinText.of(at.parshiya).wordAt(boundary)} ($boundary)'}');
      }
      final line = _smartCurrentLine < 1 ? 1 : _smartCurrentLine;
      return context.l10n.pick(
        he: "${at.whereLabel} · שורה $line מתוך ${at.lineCount}",
        en: "${_tefillinWhereLabel(at)} · line $line of ${at.lineCount}",
      );
    }
    return switch (project?.type) {
      ProjectType.mezuza => context.l10n.pick(
          he: "מזוזה $page",
          en: "Mezuzah $page",
        ),
      _ => context.l10n.pick(
          he: "עמוד ${formatHebrewNumber(page)}",
          en: "Page ${formatHebrewNumber(page)}",
        ),
    };
  }

  String _tefillinWhereLabel(TefillinPosition at) => context.l10n.pick(
        he: at.whereLabel,
        en: '${at.side == TefillinSide.head ? 'Shel Rosh' : 'Shel Yad'} · set ${at.pair}',
      );

  /// One app bar for every theme and both workflows.
  ///
  /// The workflow toggle sits immediately beside the tools button, which is
  /// where it was asked for: the two things a writer reaches for that are not
  /// about the sitting in front of them.
  PreferredSizeWidget _homeAppBar() {
    final t = SoferTokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;

    return AppBar(
      title: Text(context.l10n.appName),
      centerTitle: t.isCards,
      actions: [
        if (_journalSettings.useAsHome && _journalHomeTemporarilyHidden)
          IconButton(
            icon: const Icon(Icons.table_chart_outlined),
            tooltip: context.l10n.pick(
              he: "יומן כתיבה",
              en: "Writing Journal",
            ),
            onPressed: _clock.isActive
                ? () => showAppError(
                      context,
                      context.l10n.pick(
                        he: "יש לסיים את הטיימר לפני שחוזרים ליומן הכתיבה",
                        en: "Finish the timer before returning to the Writing Journal",
                      ),
                    )
                : () => setState(() => _journalHomeTemporarilyHidden = false),
          ),
        // Named, not only drawn. This one control changes how the whole app
        // behaves, and it used to say so in a tooltip alone — which on a phone
        // opens on a long press, so in practice it said nothing. Someone tapped
        // it by accident, the app started behaving differently, and there was
        // no way to tell what had been pressed or how to undo it.
        TextButton.icon(
          icon: Icon(
              _isSmartWorkflow ? Icons.my_location : Icons.timer_outlined,
              size: 20),
          label: Text(_isSmartWorkflow
              ? context.l10n.pick(he: "מצב חכם", en: "Smart Mode")
              : context.l10n.pick(he: "מצב רגיל", en: "Regular Mode")),
          style: TextButton.styleFrom(
            foregroundColor: _isSmartWorkflow ? t.accent : null,
          ),
          // Left enabled while the timer runs: it explains why it will not
          // switch, which a greyed-out button cannot do.
          onPressed: _toggleWorkflowMode,
        ),
        IconButton(
          icon: const Icon(Icons.auto_awesome_mosaic),
          tooltip: context.l10n.pick(he: "כלים", en: "Tools"),
          onPressed: _navigateToFeatures,
        ),
        IconButton(
          icon: const Icon(Icons.help_outline),
          tooltip: context.l10n.pick(he: "עזרה", en: "Help"),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HelpScreen()),
          ),
        ),
        if (Platform.isWindows && compact)
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: context.l10n.pick(he: "חלון צף", en: "Floating window"),
            onPressed: _openFloatingWindow,
          ),
        if (Platform.isWindows && !compact)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 22),
              label: Text(context.l10n.pick(
                he: "חלון צף",
                en: "Floating window",
              )),
              onPressed: _openFloatingWindow,
            ),
          ),
      ],
    );
  }

  Future<void> _openFloatingWindow() async {
    // Remembered, because coming back used to impose 1280x720 and discard
    // whatever size the writer had arranged for himself.
    _sizeBeforeFloating = await windowManager.getSize();
    // The floor set for the main window would refuse a 320-wide one, so it is
    // lifted for as long as the small window is up.
    await windowManager.setMinimumSize(const Size(280, 200));
    await windowManager.setSize(const Size(320, 260));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setAlignment(Alignment.bottomRight);
    widget.windowsFloatingMode?.value = true;
  }

  Widget _homeBottomNav() {
    final t = SoferTokens.of(context);
    return NavigationBar(
      selectedIndex: 0,
      backgroundColor: t.paper,
      indicatorColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      destinations: [
        NavigationDestination(
            icon: const Icon(Icons.bar_chart_rounded),
            label: context.l10n.pick(he: "סיכומים", en: "Summary")),
        NavigationDestination(
            icon: const Icon(Icons.folder_rounded),
            label: context.l10n.pick(he: "פרויקטים", en: "Projects")),
        NavigationDestination(
            icon: const Icon(Icons.settings_rounded),
            label: context.l10n.settings),
      ],
      onDestinationSelected: (i) {
        if (i == 0) _navigateToSummary();
        if (i == 1) _navigateToProjects();
        if (i == 2) _navigateToSettings();
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
        onWritingTarget: _pickSessionTarget,
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
    var page = (JsonCompat.intOrNull(lastPos['page']) ?? 1).clamp(1, 1 << 20);
    var line = (JsonCompat.intOrNull(lastPos['line']) ?? 1).clamp(1, 1 << 20);
    if (project.type == ProjectType.tefillin) {
      final next = TefillinState.positionAfterCompleted(
        project: project,
        history: history,
        page: page,
        line: line,
      );
      if (next.page != page || next.line != line) {
        page = next.page;
        line = next.line;
        try {
          await _storageService.saveLastPosition(project.id, page, line);
        } catch (error) {
          debugPrint('Could not persist next Tefillin position: $error');
        }
        if (!mounted) return;
      }
    }
    setState(() {
      _hasStoredPosition = lastPos.isNotEmpty;
      // Clamped rather than trusted: a position stored by an older build, or a
      // hand-edited backup, could carry a zero.
      _smartCurrentPage = page;
      _smartCurrentLine = line;
      _smartStartPage = _smartCurrentPage;
      _smartStartLine = _smartCurrentLine;
    });
  }

  Future<void> _startTimer() async {
    if (_reviewingLineTime || _timerCheckpointSaving || _smartLineSaving) {
      return;
    }
    if (_selectedProject == null) {
      showAppError(
        context,
        context.l10n.pick(
          he: 'יש לבחור פרויקט לפני שמתחילים את הטיימר.',
          en: 'Choose a project before starting the timer.',
        ),
      );
      return;
    }
    _timerCheckpointSaving = true;
    _timerCheckpointDone = Completer<void>();
    final previousClock = _clock.checkpoint();
    final previousDeadline = _endTimeDeadline;
    final previousEndSounded = _endTimeSounded;
    final previousTargetSounded = _sessionTargetSounded;
    final previousBreakTarget = _breakTarget;
    final previousRecorded = _plainAlreadyRecordedElapsed;
    final freshSitting = !_clock.isActive;
    if (freshSitting) {
      _endTimeSounded = false;
      _sessionTargetSounded = false;
      _plainAlreadyRecordedElapsed = Duration.zero;
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
    try {
      await _persistTimerState();
    } catch (error) {
      _clock.restoreFrom(previousClock);
      _endTimeDeadline = previousDeadline;
      _endTimeSounded = previousEndSounded;
      _sessionTargetSounded = previousTargetSounded;
      _breakTarget = previousBreakTarget;
      _plainAlreadyRecordedElapsed = previousRecorded;
      if (mounted) {
        setState(() {});
        showAppError(
            context,
            context.l10n.pick(
                he: 'הפעלת הטיימר לא נשמרה: $error',
                en: 'Timer start could not be saved: $error'));
      }
      _syncPulse();
      _syncMetronome();
      if (freshSitting) await NotificationService().cancelWritingEndAlert();
    } finally {
      await _finishTimerCheckpoint();
    }
  }

  Future<void> _pauseTimer() async {
    if (_reviewingLineTime || _timerCheckpointSaving || _smartLineSaving) {
      return;
    }
    _timerCheckpointSaving = true;
    _timerCheckpointDone = Completer<void>();
    final previousClock = _clock.checkpoint();
    setState(_clock.pause);
    _syncPulse();
    _syncMetronome();
    try {
      await _persistTimerState();
    } catch (error) {
      _clock.restoreFrom(previousClock);
      if (mounted) {
        setState(() {});
        showAppError(
            context,
            context.l10n.pick(
                he: 'ההפסקה לא נשמרה: $error',
                en: 'Pause could not be saved: $error'));
      }
      _syncPulse();
      _syncMetronome();
    } finally {
      await _finishTimerCheckpoint();
    }
  }

  Future<void> _finishTimerCheckpoint() async {
    _timerCheckpointSaving = false;
    _timerCheckpointDone?.complete();
    _timerCheckpointDone = null;
    if (mounted) setState(() {});
    if (_stopAfterLineSave && mounted) {
      _stopAfterLineSave = false;
      await _stopTimer();
    }
  }

  Future<void> _stopTimer() async {
    if (_stoppingTimer) return;
    _stoppingTimer = true;
    try {
      await _stopTimerImpl();
    } finally {
      _stoppingTimer = false;
    }
  }

  Future<void> _stopTimerImpl() async {
    if (_reviewingLineTime) return;
    if (_smartLineSaving || _timerCheckpointSaving) {
      // A fast "line finished" followed by "stop" is one intended sequence.
      // Do not drop the second tap while the durable line checkpoint is busy.
      _stopAfterLineSave = true;
      return;
    }
    if (!await _prepareWindowForDialog()) return;
    if (_clock.hasUnusualLineTime && !await _reviewUnusualLineTime()) return;
    if (!mounted) return;
    if (_isSmartWorkflow) {
      await _stopSmartTimerTransactionally();
      return;
    }
    final project = _selectedProject;
    if (project == null) {
      // This should only be reachable for a legacy timer state. Keep it alive
      // rather than stopping with nowhere to file its measured time.
      showAppError(
        context,
        context.l10n.pick(
          he: 'יש לבחור את הפרויקט של הישיבה לפני שעוצרים את הטיימר.',
          en: 'Choose the project for this sitting before stopping the timer.',
        ),
      );
      return;
    }

    // Preview first. The persisted running timer remains the recovery source
    // until the pending entry has been written successfully.
    final sitting = _clock.previewStop();
    final measured = sitting.worked > _plainAlreadyRecordedElapsed
        ? sitting.worked - _plainAlreadyRecordedElapsed
        : Duration.zero;
    final pending = EntryDraft.timed(
      projectId: project.id,
      entryId: IdGenerator.generate(),
      measuredTime: measured,
      measuredEnd: sitting.endedAt,
    );

    try {
      await _storageService.savePendingEntry(pending);
    } catch (error) {
      debugPrint('Could not persist stopped sitting: $error');
      if (mounted) {
        showAppError(
          context,
          context.l10n.pick(
            he: 'לא ניתן היה להכין את הישיבה לשמירה. הטיימר נשאר פעיל; יש לפנות מקום באחסון ולנסות שוב.',
            en: 'The session could not be prepared for saving. The timer remains active; free storage space and try again.',
          ),
        );
      }
      return;
    }

    // The pending entry is durable now. Stop the in-memory clock without
    // clearing its old persisted state until the explicit clear below.
    _clock.commitPreview(sitting, clearStoredState: false);
    _syncPulse();
    _syncMetronome();
    _clock.stopForegroundService();
    NotificationService().cancelBreakReminder();
    NotificationService().cancelWritingEndAlert();
    _endTimeDeadline = null;
    _endTimeSounded = false;
    _sessionTargetSounded = false;
    _sessionTargetMinutes = null;
    if (mounted) {
      setState(() {
        _plainAlreadyRecordedElapsed = Duration.zero;
        _smartRecordedElapsed = Duration.zero;
        _smartSavedAny = false;
        _smartSavedLines = 0;
        _smartEntryId = null;
      });
    }
    try {
      await _storageService.clearTimerState();
    } catch (error) {
      // The pending entry is authoritative and startup clears the stale timer
      // state before reopening it, so a failure here cannot lose the sitting.
      debugPrint('Could not clear stopped timer state: $error');
    }
    await _openEntryDialog(
      isManual: false,
      measuredTime: measured,
      measuredEnd: sitting.endedAt,
      initialDraft: pending,
    );
  }

  /// Ask before an unattended interval enters history. Keep a durable paused
  /// checkpoint while the dialog is open, so closing the app cannot approve it.
  Future<bool> _reviewUnusualLineTime() async {
    if (_reviewingLineTime) return false;
    _reviewingLineTime = true;
    final wasRunning = _clock.isRunning;
    if (wasRunning) {
      setState(_clock.pause);
      _syncPulse();
      _syncMetronome();
    }
    var keep = false;
    try {
      if (wasRunning) {
        try {
          await _clock.stopForegroundService();
        } catch (error) {
          debugPrint('Could not stop foreground timer during review: $error');
        }
      }
      await _persistTimerState();
      if (!mounted) return false;
      if (!await _prepareWindowForDialog() || !mounted) return false;
      final current = formatClock(_clock.sinceLastLap);
      final previous = _clock.previousLineDuration;
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          title: Text(context.l10n.pick(
            he: 'זמן שורה חריג',
            en: 'Unusual line time',
          )),
          content: Text(context.l10n.pick(
            he: 'נמדדו $current בשורה הנוכחית.'
                '${previous > Duration.zero ? '\nזמן השורה הקודמת: ${formatClock(previous)}.' : ''}'
                '\nייתכן שיצאת להפסקה והטיימר נשאר פועל. לשמור את הזמן הזה?'
                '\n„התחל מדידה מחדש” יעביר את הזמן הנוכחי להפסקה וימשיך באותה שורה. שורות וזמן שכבר נשמרו יישארו.',
            en: 'The current line has taken $current.'
                '${previous > Duration.zero ? '\nPrevious line: ${formatClock(previous)}.' : ''}'
                '\nYou may have taken a break while the timer kept running. Keep this time?'
                '\n“Restart measurement” moves the current interval to break time and continues on the same line. Saved lines and time are kept.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.pick(he: 'ביטול', en: 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.pick(
                he: 'התחל מדידה מחדש',
                en: 'Restart measurement',
              )),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.pick(
                he: 'כן, שמור את הזמן',
                en: 'Yes, keep the time',
              )),
            ),
          ],
        ),
      );
      if (!mounted) return false;
      if (choice == false) {
        final beforeReset = _clock.toJson();
        setState(_clock.restartCurrentLine);
        try {
          await _persistTimerState();
        } catch (_) {
          _clock.restoreFrom(beforeReset);
          rethrow;
        }
      }
      keep = choice == true;
    } catch (error) {
      debugPrint('Could not persist line time review: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'לא ניתן לשמור את שינוי הטיימר. הזמן נשמר ללא איפוס; נסה שוב לאחר פינוי מקום.',
              en: 'The timer change could not be saved. The time was kept without resetting; free storage space and retry.',
            ));
      }
    } finally {
      if (mounted) {
        if (wasRunning) _clock.start(clearStoredState: false);
        _syncPulse();
        _syncMetronome();
        try {
          await _persistTimerState();
        } catch (error) {
          debugPrint('Could not persist resumed timer: $error');
          keep = false;
          if (!mounted) return false;
          showAppError(
              context,
              context.l10n.pick(
                he: 'לא ניתן לשמור את מצב הטיימר. נסה שוב לאחר פינוי מקום.',
                en: 'The timer state could not be saved. Free storage space and retry.',
              ));
        }
        if (mounted) setState(() => _reviewingLineTime = false);
      }
    }
    return keep;
  }

  /// Smart mode first saves the candidate history, then stops and clears the
  /// timer. A storage error therefore leaves the live timer and its recovery
  /// state intact instead of resetting the screen before the write succeeds.
  Future<void> _stopSmartTimerTransactionally(
      {bool lineJustCompleted = false}) async {
    final wordMode = _wordTefillin;
    final sitting = _clock.previewStop();
    setState(() => _smartLineSaving = true);
    final saved = wordMode
        ? await _smartWordsCheckpoint(stopping: true)
        : await _finishSmartSession(
            breakDuration: sitting.onBreak,
            sitting: sitting,
            finishCurrentLine:
                _homeAdditions.finishWritingCompletesLine && !lineJustCompleted,
            savePartialLine: !_homeAdditions.finishWritingCompletesLine &&
                !lineJustCompleted,
          );
    if (!saved) {
      if (mounted) setState(() => _smartLineSaving = false);
      return;
    }
    // History is durable; clear the old timer state as a separate awaited
    // step. If storage is temporarily unavailable, the old state remains as a
    // recoverable, idempotent checkpoint rather than disappearing silently.
    _clock.commitPreview(wordMode ? _clock.previewStop() : sitting,
        clearStoredState: false);
    try {
      await _storageService.clearTimerState();
    } catch (error) {
      debugPrint('Could not clear smart timer state: $error');
    }
    _syncPulse();
    _syncMetronome();
    _clock.stopForegroundService();
    NotificationService().cancelBreakReminder();
    NotificationService().cancelWritingEndAlert();
    _endTimeDeadline = null;
    _endTimeSounded = false;
    _sessionTargetSounded = false;
    _sessionTargetMinutes = null;
    if (mounted) setState(() => _smartLineSaving = false);
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
      ..._clock.checkpoint(),
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
      'plainAlreadyRecordedElapsedSeconds':
          _plainAlreadyRecordedElapsed.inSeconds,
      'endTimeDeadline': _endTimeDeadline?.toIso8601String(),
      'endTimeSounded': _endTimeSounded,
      'sessionTargetMinutes': _sessionTargetMinutes,
      'sessionTargetSounded': _sessionTargetSounded,
    });
  }

  Future<void> _persistTimerStateSafely() async {
    try {
      final pending = _timerCheckpointDone;
      if (pending != null) await pending.future;
      // The smart transaction writes its own final checkpoint. Never queue a
      // background snapshot of coordinates that are still being committed.
      if (!_clock.isActive || _smartLineSaving) return;
      await _persistTimerState();
    } catch (error) {
      debugPrint('Timer checkpoint failed: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'מצב הטיימר לא נשמר. פנה מקום ונסה שוב לפני סגירת התוכנה.',
                en: 'Timer state was not saved. Free space and retry before closing the app.'));
      }
    }
  }

  Future<void> _restoreTimerState() async {
    final state = await _storageService.getTimerState();
    if (state.isEmpty) return;
    final isSmart = state['isSmart'] == true;
    final projectId =
        state['projectId'] is String ? state['projectId'] as String : null;
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
      _sessionTargetMinutes = switch (state['sessionTargetMinutes']) {
        final num value when value > 0 => value.toInt().clamp(1, 24 * 60),
        _ => null,
      };
      _sessionTargetSounded = state['sessionTargetSounded'] == true;
      _isSmartWorkflow = isSmart;
      if (projectId != null) {
        _selectedProject = projects.cast<Project?>().firstWhere(
              (p) => p?.id == projectId,
              orElse: () => null,
            );
        _smartCurrentPage =
            JsonCompat.intOrNull(state['smartCurrentPage']) ?? 1;
        _smartCurrentLine =
            JsonCompat.intOrNull(state['smartCurrentLine']) ?? 1;
        _smartStartPage = JsonCompat.intOrNull(state['smartStartPage']) ?? 1;
        _smartStartLine = JsonCompat.intOrNull(state['smartStartLine']) ?? 1;
        _smartRecordedElapsed = Duration(
            seconds:
                JsonCompat.intOrNull(state['smartRecordedElapsedSeconds']) ??
                    0);
        _smartSavedAny = state['smartSavedAny'] == true;
        _smartSavedLines = JsonCompat.intOrNull(state['smartSavedLines']) ?? 0;
        _plainAlreadyRecordedElapsed = Duration(
          seconds: JsonCompat.intOrNull(
                  state['plainAlreadyRecordedElapsedSeconds']) ??
              0,
        );
        _smartEntryId = switch (state['smartEntryId']) {
          final String id when id.isNotEmpty => id,
          _ => isSmart ? IdGenerator.generate() : null,
        };
        // A durable word receipt wins over a transient timer checkpoint that
        // failed immediately after saving history. Never file that time twice.
        for (final s in history) {
          final elapsedMs = s.extraFields['tefillinTimerElapsedMs'];
          if (!s.isDeleted &&
              s.projectId == _selectedProject?.id &&
              s.extraFields['tefillinTimerId'] == _smartEntryId &&
              elapsedMs is int &&
              elapsedMs > _smartRecordedElapsed.inMilliseconds) {
            _smartRecordedElapsed = Duration(milliseconds: elapsedMs);
            _smartSavedAny = true;
          }
        }
        if (_selectedProject?.type == ProjectType.tefillin) {
          final next = TefillinState.positionAfterCompleted(
              project: _selectedProject!,
              history: history,
              page: _smartCurrentPage,
              line: _smartCurrentLine);
          _smartCurrentPage = next.page;
          _smartCurrentLine = next.line;
          _smartStartPage = next.page;
          _smartStartLine = next.line;
        }
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
    _checkSessionTargetChime();
    _checkEndTimeAlert();
  }

  Future<void> _restorePendingEntry() async {
    if (_pendingEntryRecoveryScheduled) return;
    final draft = await _storageService.getPendingEntry();
    if (draft == null) return;

    // The history write and deletion of the recovery copy are two separate
    // durable operations. If the process died between them, the stable entry
    // id proves the work is already present and prevents a duplicate prompt.
    if (history.any((session) => session.entryId == draft.entryId)) {
      await _storageService.clearPendingEntry();
      return;
    }

    // A pending draft is created only after Stop. If the process died before
    // the old timer-state key was cleared, the draft is the authoritative
    // stopped sitting; do not restore a second live clock underneath it.
    if (_clock.isActive) {
      _clock.stop(clearStoredState: false);
      _syncPulse();
      _syncMetronome();
    }
    await _storageService.clearTimerState();

    Project? project;
    for (final candidate in projects) {
      if (candidate.id == draft.projectId) project = candidate;
    }
    if (project == null || !mounted) return;
    _pendingEntryRecoveryScheduled = true;
    setState(() => _selectedProject = project);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _openEntryDialog(
        isManual: draft.isManual,
        measuredTime: draft.measuredTime,
        measuredEnd: draft.measuredEnd,
        initialDraft: draft,
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_clock.isActive) unawaited(_persistTimerStateSafely());
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

  Duration _markLineFinished({Duration carried = Duration.zero}) {
    final lapDuration = _clock.recordLap(carried: carried);
    final fullLineDuration = carried + lapDuration;
    showAppNote(
      context,
      context.l10n.pick(
        he: "סיימתי שורה! זמן שורה: ${formatClock(fullLineDuration)}",
        en: "Line finished! Line time: ${formatClock(fullLineDuration)}",
      ),
    );
    return fullLineDuration;
  }

  Future<void> _recordLap() async {
    if (_reviewingLineTime || _timerCheckpointSaving || _smartLineSaving) {
      return;
    }
    if (_clock.hasUnusualLineTime && !await _reviewUnusualLineTime()) return;
    if (!mounted || _timerCheckpointSaving) return;
    _timerCheckpointSaving = true;
    _timerCheckpointDone = Completer<void>();
    final previousLap = _clock.lastLapElapsed;
    final previousDuration = _clock.previousLineDuration;
    final lap = _clock.recordLap();
    try {
      await _persistTimerState();
      if (mounted) {
        setState(() {});
        showAppNote(
            context,
            context.l10n.pick(
                he: 'זמן השורה: ${formatClock(lap)}. שעון השורה אופס; ההספק יוזן בסיום הישיבה.',
                en: 'Line time: ${formatClock(lap)}. The line timer was reset; output will be entered at the end.'));
      }
    } catch (error) {
      _clock.restoreLastLap(previousLap,
          previousLineDuration: previousDuration);
      if (mounted) {
        setState(() {});
        showAppError(
            context,
            context.l10n.pick(
                he: 'איפוס שעון השורה לא נשמר: $error',
                en: 'Line timer reset could not be saved: $error'));
      }
    } finally {
      await _finishTimerCheckpoint();
    }
  }

  Future<void> _initSmartSession() async {
    if (_timerCheckpointSaving || _smartLineSaving || _clock.isActive) return;
    if (_selectedProject == null) return;

    await _loadSmartPosition();
    if (!mounted) return;
    if (_timerCheckpointSaving || _clock.isActive) return;
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
      _plainAlreadyRecordedElapsed = Duration.zero;
    });
    await _startTimer();
  }

  /// Every way into a break goes through here.
  ///
  /// It used to also require the smart workflow, so a writer in plain mode
  /// switched the setting on, pressed "הפסקת קפה" and was never offered the
  /// thing the setting promised. The question belongs to the break, not to the
  /// workflow.
  void _onBreakTap() {
    if (_smartLineSaving || _timerCheckpointSaving) return;
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
          title: Text(context.l10n.pick(he: "הפסקת קפה", en: "Take a break")),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.pick(
                he: "הזמן בהפסקה לא ייכנס בממוצע לכתיבה.",
                en: "Break time is excluded from writing averages.",
              )),
              const SizedBox(height: 16),
              TextField(
                controller: minutesCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.pick(
                    he: "אורך ההפסקה בדקות (אופציונלי – השאר ריק)",
                    en: "Break length in minutes (optional)",
                  ),
                  hintText: context.l10n.pick(
                    he: "למשל 10",
                    en: "For example, 10",
                  ),
                ),
              ),
              // Here rather than in settings, so it can be decided in the
              // moment: stepping out of the room wants it, stretching at the
              // desk does not. The answer is remembered for the next break.
              SwitchListTile(
                value: chime,
                onChanged: (v) => setDialog(() => chime = v),
                title: Text(context.l10n.pick(
                  he: "צליל בסיום הזמן",
                  en: "Sound when time is up",
                )),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.coffee),
              label: Text(context.l10n.pick(
                he: "התחל הפסקה",
                en: "Start break",
              )),
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
    await _pauseTimer();
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
    _metronomeAudio.alert();
  }

  void _checkSessionTargetChime() {
    final minutes = _sessionTargetMinutes;
    if (!sessionTargetChimeDue(
      enabled: _homeAdditions.writingTargetEnabled &&
          _homeAdditions.sessionTargetChimeEnabled,
      sounded: _sessionTargetSounded,
      running: _clock.isRunning,
      paused: _clock.isPaused,
      targetMinutes: minutes,
      elapsed: _clock.elapsed,
    )) {
      return;
    }
    _sessionTargetSounded = true;
    _metronomeAudio.alert();
    showAppNote(
      context,
      context.l10n.pick(
        he: 'הגעת ליעד הזמן שקבעת לישיבה',
        en: 'You reached the time target set for this writing session',
      ),
    );
    unawaited(_persistTimerStateSafely());
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
          _metronomeAudio.beat(_homeAdditions.metronomeVolume);
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
    _metronomeAudio.alert();
    showAppNote(
      context,
      context.l10n.pick(
        he: 'הגעת לשעת הסיום שקבעת לישיבה',
        en: 'You reached the finish time set for this writing session',
      ),
    );
    unawaited(_persistTimerStateSafely());
  }

  bool get _wordTefillin {
    final p = _selectedProject;
    if (p == null || p.type != ProjectType.tefillin) return false;
    if (TefillinPreferences.usesWords(p)) return true;
    final at = TefillinPosition.fromSlotIndex(_smartCurrentPage);
    return history.any((s) =>
        s.projectId == p.id &&
        !s.isDeleted &&
        !s.isInvalid &&
        s.pairIndex == at.pair &&
        s.tefillinType == at.side.name &&
        s.parshiya == at.parshiya &&
        TefillinWordRange.isWordRecord(s));
  }

  Future<bool> _smartWordsCheckpoint({bool stopping = false}) async {
    final project = _selectedProject;
    if (project == null || !_clock.isActive) return false;
    final wasRunning = _clock.isRunning;
    if (wasRunning) {
      setState(_clock.pause);
      _syncPulse();
      _syncMetronome();
    }
    var saved = false;
    List<WorkSession>? pendingWordRecords;
    Duration? attemptedElapsed;
    try {
      if (!await _prepareWindowForDialog() || !mounted) return false;
      await _persistTimerState();
      if (!mounted) return false;
      final elapsed = _clock.elapsed;
      final worked = elapsed > _smartRecordedElapsed
          ? elapsed - _smartRecordedElapsed
          : Duration.zero;
      if (stopping && worked.inSeconds <= 0) {
        saved = true;
        return true;
      }
      final at = TefillinPosition.fromSlotIndex(_smartCurrentPage);
      final all = TefillinState.slots(project, history);
      final slot = all.firstWhere(
          (s) =>
              s.pair == at.pair &&
              s.side == at.side &&
              s.parshiya == at.parshiya,
          orElse: () => TefillinSlot(
              pair: at.pair, side: at.side, parshiya: at.parshiya));
      final label = '${at.parshiyaName} · ${_tefillinWhereLabel(at)}';
      if (!TefillinState.canWrite(slot, all) || slot.state == SlotState.stuck) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'יש לבחור פרשייה זמינה לפי סדר הכתיבה',
                en: 'Choose a writable Parashah in writing order'));
        return false;
      }
      int? base;
      if (slot.wordBoundary == null && slot.linesWritten > 0) {
        base = await showTefillinWords(
            context: context,
            parshiya: at.parshiya,
            script: TefillinPreferences.script(project),
            unitLabel: label,
            locatingLegacyPosition: true);
        if (base == null || !mounted) return false;
      }
      final from = slot.wordBoundary ?? base ?? 0;
      if (!mounted) return false;
      final until = await showTefillinWords(
          context: context,
          parshiya: at.parshiya,
          script: TefillinPreferences.script(project),
          unitLabel: label,
          fromWord: from,
          allowNoProgress: stopping);
      if (until == null || !mounted) return false;
      final ended = DateTime.now();
      final entry =
          '${_smartEntryId ?? IdGenerator.generate()}-words-${at.slotIndex}-$from-$until-${elapsed.inMilliseconds}';
      List<WorkSession> checkpoint;
      if (until == from) {
        checkpoint = [
          PartialLineRecording.create(
                  project: project,
                  position: SmartPosition(at.slotIndex, _smartCurrentLine),
                  worked: worked,
                  endedAt: ended)
              .copyWith(
                  entryId: entry,
                  description: context.l10n.pick(
                      he: 'זמן כתיבה ללא מילים נוספות — $label',
                      en: 'Writing time without additional completed words — $label'))
        ];
      } else {
        final outcome = EntryBuilder.build(
            input: EntryInput(
                project: project,
                start: ended.subtract(worked),
                end: ended,
                isManual: false,
                tefillinMode: 'parshiya',
                tefillinPart: at.side.name,
                tefillinPair: '${at.pair}',
                tefillinParshiya: at.parshiya,
                tefillinUntilWord: until,
                tefillinBaselineWord: base,
                tefillinScript: TefillinPreferences.script(project),
                entryId: entry),
            history: history);
        if (outcome is EntryRejected) {
          showAppError(context, context.l10n.businessMessage(outcome.message));
          return false;
        }
        checkpoint = (outcome as EntryBuilt).sessions;
      }
      checkpoint = _stampWorkingDay([
        for (final s in checkpoint)
          s.copyWith(extraFields: {
            ...s.extraFields,
            'tefillinTimerId': _smartEntryId,
            'tefillinTimerElapsedMs': elapsed.inMilliseconds,
          })
      ]);
      final nextHistory = [
        ...PartialLineRecording.resolve(
            history, project, SmartPosition(at.slotIndex, _smartCurrentLine)),
        ...checkpoint
      ];
      final wasMet = _dailyGoalMet(project);
      pendingWordRecords = checkpoint;
      attemptedElapsed = elapsed;
      await _storageService.saveHistory(nextHistory);
      saved = true;
      if (!mounted) return true;
      final nextSlot = TefillinState.positionAfterCompleted(
              project: project,
              history: nextHistory,
              page: at.slotIndex,
              line: 1)
          .page;
      final next = TefillinPosition.fromSlotIndex(nextSlot);
      setState(() {
        history = nextHistory;
        _smartRecordedElapsed = elapsed;
        _smartSavedAny = true;
        _smartCurrentPage = next.slotIndex;
        _smartCurrentLine = 1;
        _smartStartPage = next.slotIndex;
        _smartStartLine = 1;
        _clock.recordLap();
      });
      _celebrateIfReached(project, wasMet: wasMet);
      try {
        await _storageService.saveLastPosition(project.id, next.slotIndex, 1);
        await _persistTimerState();
      } catch (error) {
        debugPrint('Word checkpoint saved; position update failed: $error');
      }
      if (!mounted) return true;
      showAppSuccess(
          context,
          context.l10n.pick(
              he: until == from
                  ? 'זמן הכתיבה נשמר'
                  : 'נשמר עד המילה ${TefillinText.of(at.parshiya).wordAt(until)}',
              en: until == from
                  ? 'Writing time saved'
                  : 'Saved through ${TefillinText.of(at.parshiya).wordAt(until)}'));
      return true;
    } catch (error) {
      debugPrint('Word checkpoint failed: $error');
      // A backup callback may fail after the actual history write succeeded.
      // Read its receipts before offering a retry of the same measured work.
      if (pendingWordRecords != null && attemptedElapsed != null) {
        try {
          final durable = await _storageService.loadHistory();
          if (pendingWordRecords.every((p) => durable.any(
              (s) => s.id == p.id && s.entryId == p.entryId && !s.isDeleted))) {
            saved = true;
            if (mounted) {
              final at = TefillinState.positionAfterCompleted(
                  project: project,
                  history: durable,
                  page: _smartCurrentPage,
                  line: 1);
              setState(() {
                history = durable;
                _smartRecordedElapsed = attemptedElapsed!;
                _smartSavedAny = true;
                _smartCurrentPage = at.page;
                _smartCurrentLine = 1;
                _smartStartPage = at.page;
                _smartStartLine = 1;
                _clock.recordLap();
              });
              showAppNote(
                  context,
                  context.l10n.pick(
                      he: 'הרישום נשמר; עדכון הגיבוי או המיקום לא הושלם.',
                      en: 'The record was saved; the backup or position update did not finish.'));
            }
            return true;
          }
        } catch (recoveryError) {
          debugPrint('Could not read word-save receipts: $recoveryError');
        }
      }
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
                he: 'השמירה לא הושלמה. הזמן והמיקום נשמרו להמשך; נסה שוב.',
                en: 'Saving did not finish. Your time and position were kept; retry.'));
      }
      return false;
    } finally {
      if (mounted && wasRunning && (!stopping || !saved)) {
        _clock.start(clearStoredState: false);
        _syncPulse();
        _syncMetronome();
        try {
          await _persistTimerState();
        } catch (error) {
          debugPrint('Timer resume failed: $error');
        }
      }
    }
  }

  Future<void> _smartNextLine() async {
    if (_smartLineSaving || _timerCheckpointSaving || _reviewingLineTime) {
      return;
    }
    if (_clock.hasUnusualLineTime && !await _reviewUnusualLineTime()) return;
    if (!mounted) return;
    if (_wordTefillin) {
      setState(() => _smartLineSaving = true);
      var saved = false;
      try {
        saved = await _smartWordsCheckpoint();
      } finally {
        if (mounted) setState(() => _smartLineSaving = false);
        final stop = saved && _stopAfterLineSave;
        _stopAfterLineSave = false;
        if (stop && mounted) {
          await _stopSmartTimerTransactionally(lineJustCompleted: true);
        }
      }
      return;
    }
    // Once a valid segment starts, finishing one parshiya makes the following
    // one valid inside that same segment even before the segment is saved.
    // A restored timer is checked from its saved start for the same reason.
    final positionError = _tefillinPositionError(slotIndex: _smartStartPage);
    if (positionError != null) {
      showAppError(context, positionError);
      return;
    }
    final project = _selectedProject;
    if (project == null) return;
    final from = SmartPosition(_smartCurrentPage, _smartCurrentLine);
    var nextPage = from.page;
    var nextLine = from.line + 1;
    final linesPerUnit = project.type == ProjectType.tefillin
        ? TefillinUnits.linesIn(TefillinPosition.fromSlotIndex(from.page).side)
        : project.type == ProjectType.mezuza
            ? 22
            : ProductionCalculator.linesPerPageOf(project);
    if (nextLine > linesPerUnit) {
      nextLine = 1;
      nextPage++;
    }
    final destination = SmartPosition(nextPage, nextLine);
    final previousLap = _clock.lastLapElapsed;
    final previousLineDuration = _clock.previousLineDuration;
    final carriedLineTime = PartialLineRecording.carriedTime(
      history,
      project,
      from,
    );
    var lineSaved = false;
    setState(() => _smartLineSaving = true);
    _markLineFinished(carried: carriedLineTime);

    try {
      final saved = await _commitSmartSegment(target: destination);
      if (!saved) {
        // The line mark and the history checkpoint are one user-visible
        // action. If the checkpoint was rejected or could not be written,
        // restore the lap so the writer can press the same button again.
        _clock.restoreLastLap(previousLap,
            previousLineDuration: previousLineDuration);
        return;
      }
      lineSaved = true;
      final nextPosition = _nextWritablePosition(project, destination, history);
      if (mounted) {
        setState(() {
          _smartCurrentPage = nextPosition.page;
          _smartCurrentLine = nextPosition.line;
          // The segment just saved ended at [destination].  If the next page
          // was already written, the following segment must start at the
          // first unwritten position rather than recreate the skipped page.
          _smartStartPage = nextPosition.page;
          _smartStartLine = nextPosition.line;
        });
      }
      if (mounted &&
          (nextPosition.page != destination.page ||
              nextPosition.line != destination.line)) {
        final skippedWorkMessage = project.type == ProjectType.mezuza
            ? context.l10n.pick(
                he: 'ממשיך במזוזה ${formatHebrewNumber(nextPosition.page)}, שורה ${nextPosition.line}; העבודה שכבר נכתבה נשמרה.',
                en: 'Continuing at mezuza ${nextPosition.page}, line ${nextPosition.line}; previously recorded work is preserved.',
              )
            : nextPosition.page == destination.page
                ? context.l10n.pick(
                    he: 'השורות הבאות כבר נכתבו; ממשיך בעמוד ${formatHebrewNumber(nextPosition.page)}, שורה ${nextPosition.line}.',
                    en: 'The following lines are already written; continuing at page ${nextPosition.page}, line ${nextPosition.line}.',
                  )
                : destination.line > 1
                    ? context.l10n.pick(
                        he: 'יתר השורות בעמוד כבר נכתבו; ממשיך לעמוד ${formatHebrewNumber(nextPosition.page)}, שורה ${nextPosition.line}.',
                        en: 'The remaining lines on this page are already written; continuing at page ${nextPosition.page}, line ${nextPosition.line}.',
                      )
                    : nextPosition.page == destination.page + 1
                        ? context.l10n.pick(
                            he: 'העמוד הבא כבר נכתב; ממשיך לעמוד ${formatHebrewNumber(nextPosition.page)}, שורה ${nextPosition.line}.',
                            en: 'The next page is already written; continuing at page ${nextPosition.page}, line ${nextPosition.line}.',
                          )
                        : context.l10n.pick(
                            he: 'העמודים הבאים כבר נכתבו; ממשיך לעמוד ${formatHebrewNumber(nextPosition.page)}, שורה ${nextPosition.line}.',
                            en: 'The following pages are already written; continuing at page ${nextPosition.page}, line ${nextPosition.line}.',
                          );
        showAppNote(
          context,
          skippedWorkMessage,
        );
      }
      try {
        await _storageService.saveLastPosition(
            project.id, nextPosition.page, nextPosition.line);
      } catch (error) {
        debugPrint('Could not persist smart position: $error');
        if (mounted) {
          showAppError(
              context,
              context.l10n.pick(
                he: 'השורה נשמרה, אך המיקום לא עודכן. אפשר להמשיך; נסה שוב לאחר מכן.',
                en: 'The line was saved, but the position could not be updated. You can continue and retry later.',
              ));
        }
      }
      try {
        await _persistTimerState();
      } catch (error) {
        // History and the position are already durable. A failed transient
        // timer checkpoint must not leave the line button locked or turn a
        // successful line into an unhandled async error.
        debugPrint('Could not persist smart timer state: $error');
      }
    } finally {
      if (mounted) setState(() => _smartLineSaving = false);
      final shouldStop = lineSaved && _stopAfterLineSave;
      _stopAfterLineSave = false;
      if (shouldStop && mounted) {
        await _stopSmartTimerTransactionally(lineJustCompleted: true);
      }
    }
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
      SlotState.done => context.l10n.pick(
          he: 'פרשיית $name כבר הסתיימה. יש לבחור את הפרשייה הבאה.',
          en: 'The $name Parashah is complete. Choose the next Parashah.',
        ),
      SlotState.voided => context.l10n.pick(
          he: 'פרשיית $name נפסלה. יש להסיר אותה ממפת התפילין לפני התחלה מחדש.',
          en: 'The $name Parashah was invalidated. Remove it from the Tefillin map before starting again.',
        ),
      _ => context.l10n.pick(
          he: 'אי אפשר להתחיל את $name לפני שהפרשייה הקודמת הסתיימה באותו סט.',
          en: 'You cannot start $name until the previous Parashah in this set is complete.',
        ),
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
        title: Text(context.l10n.pick(
          he: "עריכת מיקום בפרויקט",
          en: "Edit project position",
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pageCtrl,
              decoration: InputDecoration(
                labelText: context.l10n.pick(he: "עמוד", en: "Page"),
                hintText: context.l10n.pick(
                  he: "אותיות (למשל: יא)",
                  en: "Hebrew letters (for example: יא)",
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lineCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.pick(he: "שורה", en: "Line"),
                hintText: "1-$maxLines",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.pick(he: "שמור", en: "Save"))),
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
        currentWord: here?.wordBoundary,
        wordEntry: _wordTefillin,
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
        TefillinPreferences.usesWords(project) || picked.wordBoundary != null
            ? 1
            : picked.state == SlotState.partial
                ? picked.linesWritten + 1
                : 1;

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
    if (_smartLineSaving || _timerCheckpointSaving) return;
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
    try {
      // Make the durable position the first part of the move. If storage is
      // unavailable the timer and the screen remain at the old location,
      // rather than showing a move that will disappear on the next launch.
      await _storageService.saveLastPosition(project.id, page, line);
    } catch (error) {
      debugPrint('Could not save selected smart position: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'לא ניתן לשמור את המיקום שבחרת. המיקום הקודם נשמר; נסה שוב לאחר מכן.',
              en: 'The selected position could not be saved. The previous position was kept; try again later.',
            ));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _smartCurrentPage = page;
      _smartCurrentLine = line;
      _smartStartPage = page;
      _smartStartLine = line;
      _smartRecordedElapsed = _clock.isActive ? _clock.elapsed : Duration.zero;
    });
    if (_clock.isActive) {
      try {
        await _persistTimerState();
      } catch (error) {
        debugPrint('Could not persist timer after position change: $error');
        if (mounted) {
          showAppError(
              context,
              context.l10n.pick(
                he: 'המיקום נשמר, אך מצב הטיימר לא עודכן. אם תסגור את התוכנה, כדאי לבדוק את העמדה לפני המשך.',
                en: 'The position was saved, but the timer checkpoint was not. Check the position before continuing after a restart.',
              ));
        }
      }
    }
  }

  /// Files the current smart-mode stretch while leaving the stopwatch alive.
  Future<bool> _commitSmartSegment({SmartPosition? target}) async {
    final project = _selectedProject;
    if (project == null || !_clock.isActive) return true;
    if (_wordTefillin) {
      if (_clock.elapsed <= _smartRecordedElapsed) return true;
      return _smartWordsCheckpoint();
    }

    final destination =
        target ?? SmartPosition(_smartCurrentPage, _smartCurrentLine);

    final elapsed = _clock.elapsed;
    final worked = elapsed > _smartRecordedElapsed
        ? elapsed - _smartRecordedElapsed
        : Duration.zero;
    final outcome = SmartSessionBuilder.build(
      project: project,
      from: SmartPosition(_smartStartPage, _smartStartLine),
      to: destination,
      worked: worked,
      endedAt: DateTime.now(),
      history: history,
      entryId: _smartEntryId,
    );

    switch (outcome) {
      case SmartRejected(:final message):
        showAppError(context, context.l10n.businessMessage(message));
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
        final checkpoint = _stampWorkingDay(sessions);
        final goalWasMet = _dailyGoalMet(project);
        final resolvedHistory = PartialLineRecording.resolve(
          history,
          project,
          SmartPosition(_smartStartPage, _smartStartLine),
        );
        final nextHistory =
            SmartLiveRecording.merge(resolvedHistory, checkpoint);
        try {
          await _storageService.saveHistory(nextHistory);
        } catch (error) {
          debugPrint('Could not persist smart checkpoint: $error');
          if (mounted) {
            showAppError(
                context,
                context.l10n.pick(
                  he: 'לא ניתן לשמור את השורה. הטיימר נשאר פעיל; נסה שוב לאחר פינוי מקום.',
                  en: 'The line could not be saved. The timer is still active; try again after freeing storage.',
                ));
          }
          return false;
        }
        if (!mounted) return false;
        setState(() {
          history = nextHistory;
          _smartStartPage = destination.page;
          _smartStartLine = destination.line;
          _smartRecordedElapsed = elapsed;
          _smartSavedAny = true;
          _smartSavedLines += linesWritten;
        });
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
  Future<bool> _finishSmartSession({
    Duration breakDuration = Duration.zero,
    required StoppedSitting sitting,
    bool finishCurrentLine = false,
    bool savePartialLine = false,
  }) async {
    final project = _selectedProject;
    if (project == null) return false;

    final remaining = sitting.worked > _smartRecordedElapsed
        ? sitting.worked - _smartRecordedElapsed
        : Duration.zero;

    final current = SmartPosition(_smartCurrentPage, _smartCurrentLine);
    final segmentStart = SmartPosition(_smartStartPage, _smartStartLine);

    // Ordinary stopping does not claim output.  Preserve the unfinished time
    // as its own dated record and leave the stored position on this line.
    if (savePartialLine &&
        segmentStart.page == current.page &&
        segmentStart.line == current.line &&
        remaining > Duration.zero) {
      final partial = _stampWorkingDay([
        PartialLineRecording.create(
          project: project,
          position: current,
          worked: remaining,
          endedAt: sitting.endedAt,
        ),
      ]).single;
      final nextHistory = [...history, partial];
      try {
        await _storageService.saveHistory(nextHistory);
        await _storageService.saveLastPosition(
            project.id, current.page, current.line);
      } catch (error) {
        debugPrint('Could not persist partial smart line: $error');
        if (mounted) {
          showAppError(
              context,
              context.l10n.pick(
                he: 'לא ניתן לשמור את זמן השורה החלקית. הטיימר נשאר פעיל; נסה שוב לאחר פינוי מקום.',
                en: 'The partial line time could not be saved. The timer is still active; try again after freeing storage.',
              ));
        }
        return false;
      }
      final totalLines = _smartSavedLines;
      if (mounted) {
        setState(() {
          history = nextHistory;
          _smartRecordedElapsed = Duration.zero;
          _smartSavedAny = false;
          _smartSavedLines = 0;
          _smartEntryId = null;
        });
      }
      if (!mounted) return false;
      showAppSuccess(
        context,
        context.l10n.pick(
          he: totalLines > 0
              ? 'הישיבה נשמרה. נכתבו $totalLines שורות, וזמן השורה הנוכחית נשמר להמשך.'
              : 'זמן השורה החלקית נשמר. בישיבה הבאה תמשיך מאותה שורה.',
          en: totalLines > 0
              ? 'The session was saved. $totalLines lines were completed, and the current line time was kept for later.'
              : 'The partial line time was saved. The next session will resume on this line.',
        ),
      );
      return true;
    }

    var destination = current;
    if (finishCurrentLine) {
      final positionError = _tefillinPositionError(slotIndex: current.page);
      if (positionError != null) {
        showAppError(context, positionError);
        return false;
      }
      final carried = PartialLineRecording.carriedTime(
        history,
        project,
        current,
      );
      if (remaining.inSeconds <= 0 && carried == Duration.zero) {
        showAppError(
          context,
          context.l10n.pick(
            he: 'לא נמדד זמן בשורה הנוכחית.',
            en: 'No time was measured on the current line.',
          ),
        );
        return false;
      }
      final linesPerUnit = project.type == ProjectType.tefillin
          ? TefillinUnits.linesIn(
              TefillinPosition.fromSlotIndex(current.page).side)
          : project.type == ProjectType.mezuza
              ? ProductionCalculator.linesPerMezuza
              : ProductionCalculator.linesPerPageOf(project);
      destination = SmartPosition.after(
        page: current.page,
        line: current.line,
        linesPerUnit: linesPerUnit,
      );
    }

    final outcome = SmartSessionBuilder.build(
      project: project,
      from: segmentStart,
      to: destination,
      worked: remaining,
      endedAt: sitting.endedAt,
      history: history,
      entryId: _smartEntryId,
    );

    switch (outcome) {
      case SmartRejected(:final message):
        showAppError(context, context.l10n.businessMessage(message));
        return false;
      case SmartNothingWritten():
        if (!_smartSavedAny) {
          showAppError(
            context,
            context.l10n.pick(
              he: "לא נרשמה התקדמות בכתיבה",
              en: "No writing progress was recorded",
            ),
          );
          return false;
        }
        final totalLines = _smartSavedLines;
        if (mounted) {
          setState(() {
            _smartRecordedElapsed = Duration.zero;
            _smartSavedAny = false;
            _smartSavedLines = 0;
            _smartEntryId = null;
          });
        }
        showAppSuccess(
          context,
          context.l10n.pick(
            he: breakDuration > Duration.zero
                ? "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.\nזמן כתיבה נטו: ${formatClock(sitting.worked)}, זמן הפסקה: ${formatClock(breakDuration)}"
                : "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.",
            en: breakDuration > Duration.zero
                ? "The session was saved. $totalLines lines were written.\nNet writing time: ${formatClock(sitting.worked)}, break time: ${formatClock(breakDuration)}"
                : "The session was saved. $totalLines lines were written.",
          ),
        );
        return true;

      case SmartRecorded(
          :final sessions,
          :final linesWritten,
          :final overlappingPages
        ):
        if (overlappingPages.isNotEmpty &&
            !await _confirmSmartOverlap(overlappingPages)) {
          return false;
        }
        if (!mounted) return false;

        final totalLines = _smartSavedLines + linesWritten;
        final finalRecords = _stampWorkingDay(sessions);
        final goalWasMet = _dailyGoalMet(project);
        final resolvedHistory = finishCurrentLine
            ? PartialLineRecording.resolve(history, project, current)
            : history;
        final nextHistory =
            SmartLiveRecording.merge(resolvedHistory, finalRecords);
        final nextPosition = finishCurrentLine
            ? _nextWritablePosition(project, destination, nextHistory)
            : destination;
        try {
          await _storageService.saveHistory(nextHistory);
          await _storageService.saveLastPosition(
              project.id, nextPosition.page, nextPosition.line);
        } catch (error) {
          debugPrint('Could not persist smart session: $error');
          if (mounted) {
            showAppError(
                context,
                context.l10n.pick(
                  he: 'לא ניתן לשמור את הסשן. הטיימר נשאר פעיל; נסה שוב לאחר פינוי מקום.',
                  en: 'The session could not be saved. The timer is still active; try again after freeing storage.',
                ));
          }
          return false;
        }
        if (mounted) {
          setState(() {
            history = nextHistory;
            _smartRecordedElapsed = Duration.zero;
            _smartSavedAny = false;
            _smartSavedLines = 0;
            _smartEntryId = null;
            if (finishCurrentLine) {
              _smartCurrentPage = nextPosition.page;
              _smartCurrentLine = nextPosition.line;
              _smartStartPage = nextPosition.page;
              _smartStartLine = nextPosition.line;
            }
          });
        }
        _celebrateIfReached(project, wasMet: goalWasMet);

        if (!mounted) return false;
        showAppSuccess(
          context,
          context.l10n.pick(
            he: breakDuration > Duration.zero
                ? "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.\nזמן כתיבה נטו: ${formatClock(sitting.worked)}, זמן הפסקה: ${formatClock(breakDuration)}"
                : "הסשן נשמר בהצלחה! נכתבו $totalLines שורות.",
            en: breakDuration > Duration.zero
                ? "The session was saved. $totalLines lines were written.\nNet writing time: ${formatClock(sitting.worked)}, break time: ${formatClock(breakDuration)}"
                : "The session was saved. $totalLines lines were written.",
          ),
        );
        return true;
    }
  }

  /// Smart mode used to write straight to history without ever looking, so
  /// jumping back with "ערוך מיקום" and rewriting a stretch produced a silent
  /// double entry.
  Future<bool> _confirmSmartOverlap(List<int> pages) async {
    if (!await _prepareWindowForDialog() || !mounted) return false;
    return confirmOverlap(context, pages: pages);
  }

  /// Opens the form that records work.
  ///
  /// The form owns its own fields and its own rules. What is left here is what
  /// only this screen can answer: which working day a record is filed under,
  /// where the stored position goes next, and whether a daily target has just
  /// been met.
  Future<void> _openEntryDialog({
    required bool isManual,
    Duration? measuredTime,
    DateTime? measuredEnd,
    EntryDraft? initialDraft,
  }) async {
    if (!await _prepareWindowForDialog() || !mounted) return;
    Project? initialProject = _selectedProject;
    if (initialDraft != null) {
      for (final project in projects) {
        if (project.id == initialDraft.projectId) initialProject = project;
      }
    }
    final used = await showEntrySheet(
      context: context,
      isManual: isManual,
      projects: projects,
      history: history,
      useGregorianDates: _useGregorianDates,
      dayStart: _dayStart,
      initialProject: initialProject,
      measuredTime: measuredTime ?? _clock.lastSitting,
      measuredEnd: measuredEnd ?? _clock.endedAt,
      initialDraft: initialDraft,
      onProjectCreated: (project) async {
        final next = [...projects, project];
        await _storageService.saveProjects(next);
        if (!mounted) return;
        setState(() => projects.add(project));
      },
      onSave: _recordEntry,
    );
    // The commission the form was last used on stays selected here, so the two
    // screens never disagree about what is being worked on.
    if (used != null && mounted) {
      setState(() => _selectedProject =
          projects.firstWhere((p) => p.id == used.id, orElse: () => used));
    }
  }

  /// Files what the entry form produced.
  Future<void> _recordEntry(EntrySave save) async {
    if (save.tefillinWordEntry != null) {
      final nextProjects = [
        for (final p in projects)
          if (p.id == save.project.id)
            TefillinPreferences.update(p,
                words: save.tefillinWordEntry, script: save.tefillinScript)
          else
            p
      ];
      await _storageService.saveProjects(nextProjects);
      if (mounted) {
        setState(() {
          projects = nextProjects;
          if (_selectedProject?.id == save.project.id) {
            _selectedProject =
                projects.firstWhere((p) => p.id == save.project.id);
          }
        });
      }
    }
    final goalWasMet = _dailyGoalMet(save.project);
    final entryIds = save.sessions
        .map((session) => session.entryId)
        .whereType<String>()
        .toSet();
    final nextHistory = [
      for (final session in history)
        if (session.entryId == null || !entryIds.contains(session.entryId))
          session,
      ..._stampWorkingDay(save.sessions),
    ];
    // The sheet awaits this callback. Do not tell it the save is complete
    // until the history is actually durable; "save and continue" can otherwise
    // start a second write while the first JSON value is still being stored.
    await _storageService.saveHistory(nextHistory);
    if (!mounted) return;
    setState(() => history = nextHistory);
    try {
      _celebrateIfReached(save.project, wasMet: goalWasMet);

      // Keeps the smart-workflow position in step with entries made by hand.
      // Otherwise typing pages in and then starting a smart session resumes
      // from wherever the writer was before, and rewrites existing work.
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
      // Today's only. Cancelling the whole queue is what the old code did, and
      // it silenced the reminder for every day after as well.
      if (NotificationService.isSupported && metToday) {
        NotificationService().cancelTodaysReminder();
      } else {
        // Tops the week up, so the queue never runs dry for anyone recording work.
        NotificationService().scheduleDailyReminder();
      }
    } catch (error) {
      // History is already durable. No notification, backup, position or
      // celebration failure may turn this into a retry of the same work.
      debugPrint('Post-save convenience failed: $error');
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
    if (project.type == ProjectType.tefillin) {
      final position = TefillinState.nextWritingPosition(project, history);
      final next = SmartPosition(position.page, position.line);
      final stored = await _storageService.getLastPosition(project.id);
      final current = SmartPosition(
        JsonCompat.intOrNull(stored['page']) ?? 0,
        JsonCompat.intOrNull(stored['line']) ?? 0,
      );
      if (!next.isAfter(current)) return;
      await _storageService.saveLastPosition(project.id, next.page, next.line);
      if (!mounted || _selectedProject?.id != project.id) return;
      setState(() {
        _smartCurrentPage = next.page;
        _smartCurrentLine = next.line;
      });
      return;
    }
    if (!project.type.isPaged && project.type != ProjectType.mezuza) {
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
    final current = SmartPosition(JsonCompat.intOrNull(stored['page']) ?? 0,
        JsonCompat.intOrNull(stored['line']) ?? 0);
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
      _plainAlreadyRecordedElapsed = Duration.zero;
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

  Future<Project?> _editProjectFromCenter(Project project) async {
    final recorded = await _storageService.loadHistory();
    if (!mounted) return null;
    Project? saved;
    await showDialog<void>(
      context: context,
      builder: (_) => ProjectDialog(
        existingProject: project,
        useGregorianDates: _useGregorianDates,
        hasRecordedWork: recorded.any(
          (session) => session.projectId == project.id && !session.isDeleted,
        ),
        onSave: (updated) => saved = updated,
      ),
    );
    final updated = saved;
    if (updated == null || !mounted) return null;
    final nextProjects = [...projects];
    final projectAt = nextProjects.indexWhere((p) => p.id == updated.id);
    if (projectAt != -1) {
      nextProjects[projectAt] = updated;
    } else {
      nextProjects.add(updated);
    }
    try {
      // Persist before changing the live list. If storage refuses the edit,
      // the center must keep showing the old project rather than claiming the
      // new value was saved.
      await _storageService.saveProjects(nextProjects);
    } catch (error) {
      debugPrint('Project edit failed: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'שמירת שינויי הפרויקט לא הושלמה.',
              en: 'The project changes could not be saved.',
            ));
      }
      return null;
    }
    if (!mounted) return null;
    setState(() {
      final at = projects.indexWhere((p) => p.id == updated.id);
      if (at != -1) projects[at] = updated;
      if (at == -1) projects.add(updated);
      if (_selectedProject?.id == updated.id) _selectedProject = updated;
    });
    return updated;
  }

  Future<bool> _deleteProjectFromCenter(Project project) async {
    if (!await _canDeleteProject(project)) return false;
    if (!mounted) return false;
    final confirmed = await confirmAction(
      context,
      title: context.l10n.pick(he: 'מחיקת פרויקט', en: 'Delete project'),
      message: context.l10n.pick(
        he: 'הפרויקט יעבור לסל המחזור. רשומות הכתיבה שלו יישמרו.',
        en: 'The project will move to the Recycle Bin. Its writing records will be kept.',
      ),
      confirmLabel: context.l10n.pick(he: 'מחק', en: 'Delete'),
      danger: true,
    );
    if (!confirmed) return false;
    final deleted = project.copyWith(isDeleted: true);
    final nextProjects = [
      for (final current in projects)
        current.id == project.id ? deleted : current,
      if (!projects.any((current) => current.id == project.id)) deleted,
    ];
    try {
      await _storageService.saveProjects(nextProjects);
    } catch (error) {
      debugPrint('Project deletion failed: $error');
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'מחיקת הפרויקט לא הושלמה.',
              en: 'The project could not be deleted.',
            ));
      }
      return false;
    }
    if (!mounted) return true;
    setState(() {
      projects.removeWhere((p) => p.id == project.id);
      if (_selectedProject?.id == project.id) _selectedProject = null;
    });
    return true;
  }

  /// A project holding the active clock cannot be removed underneath it. The
  /// timer has no meaningful place to file its next segment once its project
  /// is gone, so refusing the destructive action is safer than silently losing
  /// the sitting.
  Future<bool> _canDeleteProject(Project project) async {
    if (_clock.isActive && _selectedProject?.id == project.id) {
      if (mounted) {
        showAppError(
          context,
          context.l10n.pick(
            he: 'אי אפשר למחוק את הפרויקט בזמן שטיימר הכתיבה שלו פעיל. יש לעצור ולשמור את הישיבה תחילה.',
            en: 'This project cannot be deleted while its writing timer is active. Stop and save the sitting first.',
          ),
        );
      }
      return false;
    }
    return true;
  }

  void _navigateToProjects() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectsScreen(
          projects: projects,
          onWorkCommitted: (nextProjects, nextHistory) async {
            if (!mounted) return;
            setState(() {
              projects
                ..clear()
                ..addAll(nextProjects.where((p) => !p.isDeleted));
              history = nextHistory.where((s) => !s.isDeleted).toList();
              final selectedId = _selectedProject?.id;
              for (final p in projects) {
                if (p.id == selectedId) _selectedProject = p;
              }
            });
          },
          onProjectAdded: (p) async {
            final next = [...projects, p];
            await _storageService.saveProjects(next);
            if (!mounted) return;
            setState(() => projects.add(p));
          },
          onProjectUpdated: (p) async {
            // A deleted project leaves the screen; it does not leave the file.
            // Its sessions stay too, and stay alive — the work happened, and
            // restoring the project from the bin has to bring it back. They
            // used to be dropped here, so a restore returned an empty project.
            final next = [
              for (final current in projects)
                if (current.id == p.id && p.isDeleted)
                  p
                else if (current.id == p.id)
                  p
                else
                  current,
            ];
            if (!projects.any((current) => current.id == p.id)) next.add(p);
            await _storageService.saveProjects(next);
            if (!mounted) return;
            setState(() {
              if (p.isDeleted) {
                projects.removeWhere((element) => element.id == p.id);
              } else {
                int index =
                    projects.indexWhere((element) => element.id == p.id);
                if (index != -1) projects[index] = p;
              }
            });
          },
          onProjectDeleted: (p) async {
            if (mounted) {
              setState(
                  () => projects.removeWhere((element) => element.id == p.id));
            }
          },
          onBeforeProjectDelete: _canDeleteProject,
          onHistoryUpdated: (updatedHistory) async {
            await _storageService.saveHistory(updatedHistory);
            if (mounted) {
              setState(() => history = updatedHistory
                  .where((session) => !session.isDeleted)
                  .toList());
            }
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
    final journalSettings = await _storageService.getWritingJournalSettings();
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
      _journalSettings = journalSettings;
      if (!journalSettings.useAsHome) {
        _journalHomeTemporarilyHidden = false;
      }
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
      unawaited(_persistTimerStateSafely());
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

  Future<void> _navigateToFeatures() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FeaturesScreen(
          projects: projects,
          history: history,
          onProjectCreated: _saveExternalProject,
          onEntrySave: _recordEntry,
          onHistoryCommitted: _acceptJournalHistory,
        ),
      ),
    );
    await _reloadAfterExternalChange();
  }

  Future<void> _acceptJournalHistory(List<WorkSession> next) async {
    if (mounted) {
      setState(() => history = next.where((s) => !s.isDeleted).toList());
    }
  }

  Future<void> _saveExternalProject(Project project) async {
    final next = [
      for (final current in projects)
        if (current.id != project.id) current,
      project,
    ];
    await _storageService.saveProjects(next);
    if (!mounted) return;
    setState(() => projects = next);
  }

  void _navigateToSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SummaryScreen(
          projects: projects,
          onWorkCommitted: (nextProjects, nextHistory) async {
            if (!mounted) return;
            setState(() {
              projects
                ..clear()
                ..addAll(nextProjects.where((p) => !p.isDeleted));
              history = nextHistory.where((s) => !s.isDeleted).toList();
              final selectedId = _selectedProject?.id;
              for (final p in projects) {
                if (p.id == selectedId) _selectedProject = p;
              }
            });
          },
          history: history,
          // What comes back may carry tombstones — the editor marks a record
          // deleted rather than dropping it. The whole list is written; only
          // the live records stay on screen.
          onHistoryUpdated: (updatedHistory) async {
            await _storageService.saveHistory(updatedHistory);
            if (mounted) {
              setState(() =>
                  history = updatedHistory.where((s) => !s.isDeleted).toList());
            }
          },
          onEditProject: _editProjectFromCenter,
          onDeleteProject: _deleteProjectFromCenter,
          onProjectUpdated: (updated) async {
            final next = [
              for (final current in projects)
                current.id == updated.id ? updated : current,
              if (!projects.any((current) => current.id == updated.id)) updated,
            ];
            try {
              await _storageService.saveProjects(next);
            } catch (error) {
              debugPrint('Project update from summary failed: $error');
              if (!context.mounted) return;
              showAppError(
                  context,
                  context.l10n.pick(
                    he: 'שמירת שינויי הפרויקט לא הושלמה.',
                    en: 'The project changes could not be saved.',
                  ));
              return;
            }
            if (mounted) {
              setState(() {
                projects
                  ..clear()
                  ..addAll(next);
                if (_selectedProject?.id == updated.id) {
                  _selectedProject = updated;
                }
              });
            }
          },
          useGregorianDates: _useGregorianDates,
        ),
      ),
    );
  }

  /// The main window's size before the floating one took over, so returning
  /// gives the writer his own window back rather than a fresh 1280x720.
  Size? _sizeBeforeFloating;

  SmartPosition _nextWritablePosition(
      Project project, SmartPosition from, Iterable<WorkSession> records) {
    if (project.type == ProjectType.mezuza) {
      final next = MezuzaState.nextWritablePosition(project, records,
          page: from.page, line: from.line);
      return SmartPosition(next.page, next.line);
    }
    return SmartSessionBuilder.nextWritablePosition(
        project: project, from: from, history: records);
  }

  Future<bool> _prepareWindowForDialog() async {
    if (!Platform.isWindows || !(widget.windowsFloatingMode?.value ?? false)) {
      return mounted;
    }
    try {
      await _restoreFromFloatingWindow();
      // Let MediaQuery receive the restored window size before choosing a
      // full-screen form or desktop dialog.
      await WidgetsBinding.instance.endOfFrame;
      return mounted;
    } catch (error) {
      if (mounted) {
        showAppError(
            context,
            context.l10n.pick(
              he: 'לא ניתן להגדיל את החלון. נסה שוב; נתוני הישיבה נשמרו.',
              en: 'Could not restore the window. Try again; session data is retained.',
            ));
      }
      return false;
    }
  }

  Future<void> _restoreFromFloatingWindow() async {
    if (!Platform.isWindows || widget.windowsFloatingMode == null) return;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(const Size(420, 640));
    await windowManager.setSize(_sizeBeforeFloating ?? const Size(1280, 720));
    await windowManager.center();
    widget.windowsFloatingMode!.value = false;
  }

  /// Runs a shortcut, if the key pressed is one and the moment allows it.
  ///
  /// Refused while a text field has focus. A shortcut is a key the writer is
  /// not otherwise using, and while he is typing a page number every key is one
  /// he is using — a bare letter stopping the timer mid-entry is exactly the
  /// failure this guards against, which is also why a bare letter cannot be
  /// bound in the first place.
  KeyEventResult _onKey(KeyEvent event) {
    if (_reviewingLineTime) return KeyEventResult.ignored;
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
          showAppNote(
            context,
            context.l10n.pick(
              he: "יש לבחור פרויקט לפני התחלת ישיבה",
              en: "Choose a project before starting a writing session",
            ),
          );
        }
      case ShortcutAction.takeBreak:
        // The same key is a toggle: while writing it opens a break, and while
        // paused it resumes.  Calling _onBreakTap while paused would open the
        // break dialog again (or pause an already paused timer), which made a
        // second press of Enter appear to do nothing.
        if (_clock.isPaused) {
          _startTimer();
        } else if (_clock.isRunning) {
          _onBreakTap();
        }
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
        lineSaving: _smartLineSaving || _timerCheckpointSaving,
        lineElapsed: _currentLineElapsed,
        lineActionTooltip: _isSmartWorkflow
            ? context.l10n.pick(
                he: _wordTefillin ? 'סמן מילה אחרונה' : "סיום שורה",
                en: _wordTefillin ? 'Select last word' : "Finish line")
            : context.l10n.pick(he: "איפוס זמן שורה", en: "Reset line timer"),
      );
    }

    final homeSnapshot = _buildHomeSnapshot();

    if (_journalSettings.useAsHome &&
        !_journalHomeTemporarilyHidden &&
        !_clock.isActive) {
      return Scaffold(
        appBar: _homeAppBar(),
        body: WritingJournalScreen(
          onHistoryCommitted: _acceptJournalHistory,
          projects: projects,
          history: history,
          onProjectCreated: _saveExternalProject,
          onSave: _recordEntry,
          embedded: true,
          onOpenTimer: () =>
              setState(() => _journalHomeTemporarilyHidden = true),
        ),
        bottomNavigationBar: _homeBottomNav(),
      );
    }

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
                                  decoration: InputDecoration(
                                    border: UnderlineInputBorder(),
                                    hintText: context.l10n.pick(
                                      he: "בחר פרויקט",
                                      en: "Choose project",
                                    ),
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
                                      Text(
                                          context.l10n.pick(
                                              he: "כותב...", en: "Writing…"),
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
                            child: HomeAdditionsPanel(
                              snapshot: homeSnapshot,
                              onWritingTarget: _pickSessionTarget,
                            ),
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
                            label: Text(context.l10n.pick(
                              he: "תחילת כתיבה",
                              en: "Start writing",
                            )),
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
                        // The line stopwatch is optional in plain mode. Its
                        // button is prominent for writers who use a line target,
                        // but its label says exactly what it does: it never
                        // records output in this workflow.
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!_clock.isPaused) ...[
                              ElevatedButton.icon(
                                onPressed: _recordLap,
                                icon: const Icon(Icons.flag, size: 28),
                                label: Text(context.l10n.pick(
                                  he: "איפוס זמן שורה",
                                  en: "Reset line timer",
                                )),
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
                                  label: Text(_clock.isPaused
                                      ? context.l10n.pick(
                                          he: "המשך",
                                          en: "Resume",
                                        )
                                      : context.l10n.pick(
                                          he: "הפסקת קפה",
                                          en: "Take a break",
                                        )),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 15),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                OutlinedButton.icon(
                                  onPressed: _stopTimer,
                                  icon: const Icon(Icons.stop),
                                  label: Text(context.l10n.pick(
                                    he: "סיים",
                                    en: "Finish",
                                  )),
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
                          label: Text(context.l10n.pick(
                            he: "הוספת כתיבה ידנית (ללא טיימר)",
                            en: "Add writing manually (without timer)",
                          )),
                        ),
                      const SizedBox(height: 12),
                      // Today's work, not "this session". The old line counted
                      // records since the app was opened — a number that reset
                      // itself on every launch and told the writer nothing about
                      // his day. "סשן" was not a Hebrew word either.
                      if (_recordsToday > 0)
                        Text(
                          context.l10n.pick(
                            he: "נשמרו היום $_recordsToday רשומות",
                            en: "$_recordsToday records saved today",
                          ),
                          style: const TextStyle(color: Colors.grey),
                        ),
                      // Not a coffee cup: while the timer runs, "הפסקת קפה" is
                      // on the same screen, and the two meant different things
                      // under the same picture.
                      TextButton.icon(
                        icon: const Icon(Icons.volunteer_activism, size: 20),
                        label: Text(context.l10n.pick(
                          he: "תרומה לפיתוח",
                          en: "Support development",
                        )),
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
            Text(
                context.l10n
                    .pick(he: "אין עוד פרויקטים", en: "No projects yet"),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              context.l10n.pick(
                he: "פתח פרויקט ראשון כדי להתחיל למדוד כתיבה, רווח וצפי סיום.",
                en: "Create your first project to start measuring writing, profit, and estimated completion.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15, height: 1.6, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: onCreateProject,
              icon: const Icon(Icons.add),
              label: Text(context.l10n.pick(
                he: "פתיחת פרויקט ראשון",
                en: "Create first project",
              )),
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
          metric(context.l10n.pick(he: 'זמן כתיבה', en: 'Writing time'),
              elapsed, 52),
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
