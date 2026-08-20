import 'package:flutter/material.dart';

import '../models.dart';
import '../theme/app_theme.dart';
import '../widgets/sofer_widgets.dart';

/// Everything the ruled home screen shows, gathered once by the home screen.
///
/// Passed in rather than reached for, so this file holds no state and can be
/// laid out, read and changed without touching the timer.
class HomeSnapshot {
  final Project? project;
  final List<Project> projects;
  final String hebrewDate;

  final bool isRunning;
  final bool isPaused;

  /// Already formatted, because how a duration reads is a decision the home
  /// screen already makes for the other layout.
  final String elapsed;

  /// The current break, and the time since the last line was marked finished.
  /// Both formatted for the same reason as [elapsed].
  final String breakElapsed;

  /// Time left in the break, signed — "-04:05" once it has run over. Empty
  /// when no length was set for it, which is when there is nothing to say.
  final String breakRemaining;

  /// Whether that number is time taken rather than time left.
  final bool breakOverrun;
  final String sinceLastLap;

  /// When a line target is enabled the second clock becomes a signed
  /// countdown. Without it these are null and the familiar elapsed line clock
  /// remains unchanged.
  final String? lineClockLabel;
  final String? lineClockValue;
  final bool lineClockOverrun;

  /// Optional, independently enabled rows below the main clocks.
  final String? writingTargetStatus;
  final bool writingTargetOverrun;
  final String? endTimeStatus;
  final bool endTimeOverrun;
  final int? metronomeBpm;
  final bool metronomeActive;

  /// True only for the short write to local storage after "סיימתי שורה".
  /// The action is disabled during it so two rapid taps cannot file one line
  /// twice against the same checkpoint.
  final bool isSavingLine;

  /// Where the writer left off last time, written out — or null when this
  /// commission has never been worked on, which is a different thing from
  /// starting at page one and has to read differently.
  final String? lastPosition;

  /// Smart mode only: where the writer is right now.
  final int currentLine;

  /// The page, already written out — "עמוד קמ״ה", "מזוזה 3", "סט 2". Which unit
  /// a commission counts its pages in, and whether the number reads as a Hebrew
  /// numeral, is a decision the home screen already makes for the other layout.
  final String pageLabel;

  /// What the project counts in — "שורה", "מזוזה", "פרשייה".
  final String positionUnit;

  /// What to show large instead of the unit and its number.
  ///
  /// Tefillin only. A sofer does not think "parshiya 2"; he thinks "the vehaya
  /// ki yeviacha of pair four", so the name goes in the large type and the pair
  /// and line go beneath. Null everywhere else, where a number is exactly what
  /// the writer means.
  final String? positionTitle;

  final String todayOutput;
  final String? hourlyRate;
  final String? doneOfTotal;
  final double progress;
  final String? completion;
  final String? completionDetail;

  const HomeSnapshot({
    required this.project,
    required this.projects,
    required this.hebrewDate,
    required this.isRunning,
    required this.isPaused,
    required this.elapsed,
    this.breakElapsed = '',
    this.breakRemaining = '',
    this.breakOverrun = false,
    this.sinceLastLap = '',
    this.lineClockLabel,
    this.lineClockValue,
    this.lineClockOverrun = false,
    this.writingTargetStatus,
    this.writingTargetOverrun = false,
    this.endTimeStatus,
    this.endTimeOverrun = false,
    this.metronomeBpm,
    this.metronomeActive = false,
    this.isSavingLine = false,
    this.lastPosition,
    required this.currentLine,
    required this.pageLabel,
    required this.positionUnit,
    this.positionTitle,
    required this.todayOutput,
    this.hourlyRate,
    this.doneOfTotal,
    this.progress = 0,
    this.completion,
    this.completionDetail,
  });

  bool get isActive => isRunning || isPaused;
  String get shownLineLabel => lineClockLabel ?? 'זמן השורה';
  String get shownLineValue => lineClockValue ?? sinceLastLap;
  bool get hasHomeAdditions =>
      writingTargetStatus != null ||
      endTimeStatus != null ||
      metronomeBpm != null;
}

/// What the ruled home screen can do. Held together so the layout never has to
/// know which of them the timer cares about.
class HomeActions {
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onBreak;
  final VoidCallback onManualEntry;
  final VoidCallback onNextLine;

  /// Marking a finished line in plain mode, where nothing is tracking the
  /// position. The cards layout has always offered it and this one could not:
  /// the action was simply never passed in, so a writer who moved to klaf or
  /// layla found a button he had been using every evening had gone.
  final VoidCallback onLap;
  final VoidCallback onEditPosition;

  /// Leaves the current mezuza part-written and moves to the next untouched
  /// one. The position sheet is what brings the writer back later.
  final VoidCallback onSkipMezuza;
  final ValueChanged<Project?> onProjectChanged;

  /// Pausing and resuming are the same button in the cards layout, so it needs
  /// resuming as its own action rather than as "start".
  final VoidCallback onResume;

  const HomeActions({
    required this.onStart,
    required this.onStop,
    required this.onBreak,
    required this.onManualEntry,
    required this.onNextLine,
    required this.onLap,
    required this.onEditPosition,
    required this.onSkipMezuza,
    required this.onProjectChanged,
    required this.onResume,
  });
}

/// The home screen in the ruled layout, used by the klaf and layla themes.
///
/// The two workflows put a different figure first, because they answer
/// different questions:
///
/// * **plain** — the writer will say afterwards what was written, so the only
///   thing the app knows during the sitting is the clock. The clock leads.
/// * **smart** — the app is tracking the position line by line. Where the
///   writer is leads, and the clock sits under it. That is the whole point of
///   the mode, so it is what the eye should land on.
class RuledHomeBody extends StatelessWidget {
  final HomeSnapshot snapshot;
  final HomeActions actions;
  final bool isSmart;

  const RuledHomeBody({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.isSmart,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    // Only when there is genuinely nothing to write. A project not yet chosen
    // is the ordinary state on a fresh launch, and the answer to it is the
    // picker, not an empty screen.
    if (snapshot.projects.isEmpty) {
      return _EmptyState(hebrewDate: snapshot.hebrewDate);
    }

    return SoferPage(
      child: LayoutBuilder(
        builder: (context, box) {
          // One column on a phone, two side by side once there is room — the
          // same content either way, never a different feature set.
          final wide = box.maxWidth > 620;
          final left = _WorkColumn(
              snapshot: snapshot, actions: actions, isSmart: isSmart);
          final right = _FiguresColumn(snapshot: snapshot);

          if (!wide) {
            return SingleChildScrollView(
              child: Column(children: [left, right]),
            );
          }

          // IntrinsicHeight because the rule between the columns has to run the
          // height of the taller one. Without it the row inherits the scroll
          // view's unbounded height, and since a release build has no
          // assertions to catch it, the page simply scrolled for ever.
          return SingleChildScrollView(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: left),
                  Container(width: 1, color: t.rule),
                  Expanded(child: right),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The sitting itself: which commission, the leading figure, and the actions.
class _WorkColumn extends StatelessWidget {
  final HomeSnapshot snapshot;
  final HomeActions actions;
  final bool isSmart;

  const _WorkColumn({
    required this.snapshot,
    required this.actions,
    required this.isSmart,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final s = snapshot;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SoferSectionTitle(
            s.isActive ? "כותב כעת" : "הפרויקט הנבחר",
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: 5),
          if (s.isActive)
            Text(
              s.project!.name,
              style: TextStyle(
                  fontFamily: t.numeralFamily, fontSize: 21, color: t.ink),
            )
          else
            DropdownButtonFormField<Project>(
              initialValue: s.project,
              isExpanded: true,
              decoration: const InputDecoration(
                border: UnderlineInputBorder(),
                hintText: "בחר פרויקט להתחלת עבודה",
              ),
              items: [
                for (final p in s.projects)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: actions.onProjectChanged,
            ),

          const SizedBox(height: 18),
          const SoferRule(),
          const SizedBox(height: 16),

          // Smart mode leads with the position whether or not the timer is
          // running. Knowing where you are — and being able to correct it — is
          // the whole point of the mode, and it is wanted most before starting,
          // not only during. The modern layout has always offered it here; this
          // one only did while the timer ran, which is a difference in what the
          // app can do and not only in how it looks.
          if (isSmart && s.project != null)
            _PositionHero(snapshot: s, onEdit: actions.onEditPosition)
          else
            _ClockHero(snapshot: s),

          if (s.hasHomeAdditions) ...[
            const SizedBox(height: 16),
            HomeAdditionsPanel(snapshot: s),
          ],

          const SizedBox(height: 20),
          _Actions(snapshot: s, actions: actions, isSmart: isSmart),
        ],
      ),
    );
  }
}

/// Smart mode: where the writer is, with the clock beneath it.
class _PositionHero extends StatelessWidget {
  final HomeSnapshot snapshot;
  final VoidCallback onEdit;

  const _PositionHero({required this.snapshot, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final s = snapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!s.isActive) ...[
          Text("ממשיך מ",
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: t.inkMuted)),
          const SizedBox(height: 5),
        ],
        Semantics(
          button: true,
          label: 'שינוי מיקום',
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (s.isRunning && !s.isPaused) ...[
                    Container(
                      width: 7,
                      height: 7,
                      margin: const EdgeInsetsDirectional.only(end: 10),
                      decoration: BoxDecoration(
                          color: t.accent, shape: BoxShape.circle),
                    ),
                  ],
                  // The large position itself is the control. A separate
                  // "manual position" button made this feel like data entry
                  // when the writer is simply saying where the quill is.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        s.positionTitle ?? "${s.positionUnit} ${s.currentLine}",
                        style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: s.positionTitle != null ? 46 : 58,
                          height: 1,
                          letterSpacing: -2,
                          color: t.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          s.pageLabel,
          style: TextStyle(
              fontFamily: t.numeralFamily, fontSize: 19, color: t.inkMuted),
        ),
        const SizedBox(height: 12),
        if (s.isActive)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ClockPair(snapshot: s, compact: true),
              if (s.isPaused) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                        s.breakElapsed.isEmpty
                            ? "בהפסקה"
                            : "בהפסקה ${s.breakElapsed}",
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 13,
                            color: t.inkMuted)),
                    if (s.breakRemaining.isNotEmpty)
                      Text(
                        s.breakOverrun
                            ? "חריגה ${s.breakRemaining}"
                            : "נותרו ${s.breakRemaining}",
                        style: TextStyle(
                          fontFamily: t.numeralFamily,
                          fontSize: 14,
                          color: s.breakOverrun ? t.danger : t.inkMuted,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          )
        else
          Text("מוכן להתחיל",
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  color: t.inkMuted)),
      ],
    );
  }
}

/// Plain mode: the clock, because the position is not known until the writer
/// says so.
class _ClockHero extends StatelessWidget {
  final HomeSnapshot snapshot;

  const _ClockHero({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final s = snapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.isActive)
          _ClockPair(snapshot: s)
        else
          Text(
            s.elapsed,
            style: TextStyle(
              fontFamily: t.numeralFamily,
              fontSize: 56,
              height: 1,
              letterSpacing: -1,
              color: t.ink,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          s.isPaused
              ? "בהפסקה"
              : s.isRunning
                  ? "כותב"
                  : "מוכן להתחיל",
          style: TextStyle(
            fontFamily: t.labelFamily,
            fontSize: 13,
            letterSpacing: 1.2,
            color: s.isRunning && !s.isPaused ? t.accent : t.inkMuted,
          ),
        ),
      ],
    );
  }
}

/// The two clocks answer different questions and stay visible together: how
/// long this sitting has run, and how long the line under the quill is taking.
class _ClockPair extends StatelessWidget {
  final HomeSnapshot snapshot;
  final bool compact;

  const _ClockPair({required this.snapshot, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final valueSize = compact ? 25.0 : 43.0;
    final color = snapshot.isPaused ? t.inkMuted : t.ink;

    Widget metric(String label, String value, {bool danger = false}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 11,
                      color: t.inkMuted)),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value,
                    style: TextStyle(
                        fontFamily: t.numeralFamily,
                        fontSize: valueSize,
                        height: 1,
                        color: danger ? t.danger : color)),
              ),
            ],
          ),
        );

    return Row(
      children: [
        metric('זמן כתיבה', snapshot.elapsed),
        Container(
          width: 1,
          height: compact ? 42 : 58,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          color: t.rule,
        ),
        metric(snapshot.shownLineLabel, snapshot.shownLineValue,
            danger: snapshot.lineClockOverrun),
      ],
    );
  }
}

/// The opt-in tools that sit beneath the clocks in every home layout.
class HomeAdditionsPanel extends StatelessWidget {
  final HomeSnapshot snapshot;

  const HomeAdditionsPanel({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (!snapshot.hasHomeAdditions) return const SizedBox.shrink();
    final t = SoferTokens.of(context);

    Widget row(IconData icon, String text,
        {bool danger = false, bool active = false}) {
      final color = danger
          ? t.danger
          : active
              ? t.accent
              : t.inkMuted;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: danger ? FontWeight.bold : FontWeight.normal,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: t.accent.withValues(alpha: 0.055),
        border: Border.all(color: t.rule),
        borderRadius: t.isCards ? BorderRadius.circular(12) : BorderRadius.zero,
      ),
      child: Column(
        children: [
          if (snapshot.writingTargetStatus case final value?)
            row(Icons.hourglass_bottom, value,
                danger: snapshot.writingTargetOverrun),
          if (snapshot.endTimeStatus case final value?)
            row(Icons.alarm, value, danger: snapshot.endTimeOverrun),
          if (snapshot.metronomeBpm case final bpm?)
            row(
              Icons.graphic_eq,
              snapshot.metronomeActive
                  ? 'מטרונום · $bpm פעימות בדקה'
                  : snapshot.isActive
                      ? 'מטרונום · $bpm פעימות בדקה · מושהה'
                      : 'מטרונום · $bpm פעימות בדקה · יתחיל עם הטיימר',
              active: snapshot.metronomeActive,
            ),
        ],
      ),
    );
  }
}

/// A short, non-blocking celebration over whichever home layout is active.
class GoalCelebrationOverlay extends StatelessWidget {
  const GoalCelebrationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.75, end: 1),
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Container(
              margin: const EdgeInsets.all(18),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              decoration: BoxDecoration(
                color: t.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.accent, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: t.accent),
                  const SizedBox(width: 10),
                  Text(
                    'היעד היומי הושלם! 🎉',
                    style: TextStyle(
                      fontFamily: t.labelFamily,
                      color: t.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.celebration, color: t.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The actions, ordered so the one most likely to be wanted is first and
/// widest — and so that "הזנה" is never adjacent to "עצור" on a phone.
class _Actions extends StatelessWidget {
  final HomeSnapshot snapshot;
  final HomeActions actions;
  final bool isSmart;

  const _Actions({
    required this.snapshot,
    required this.actions,
    required this.isSmart,
  });

  @override
  Widget build(BuildContext context) {
    final s = snapshot;

    if (!s.isActive) {
      // Nothing to start or record until a project is chosen.
      final ready = s.project != null;
      return Column(children: [
        SoferPrimaryButton("תחילת כתיבה",
            icon: Icons.play_arrow,
            expand: true,
            onPressed: ready ? actions.onStart : null),
        const SizedBox(height: 8),
        SoferSecondaryButton("הזנה ידנית",
            icon: Icons.edit_calendar,
            expand: true,
            quiet: true,
            onPressed: ready ? actions.onManualEntry : null),
      ]);
    }

    // Ordered by how often a writer reaches for them. Finishing a line happens
    // dozens of times in a sitting; breaking and stopping happen once each, at
    // the end. The button under the thumb should be the one being pressed all
    // the way through, not the one pressed last.
    return Column(children: [
      if (!s.isPaused) ...[
        SoferPrimaryButton("סיימתי שורה",
            icon: Icons.flag,
            expand: true,
            // Smart mode advances the stored position; plain mode only times
            // the line. Same button, because to the writer it is the same act.
            onPressed: s.isSavingLine
                ? null
                : isSmart
                    ? actions.onNextLine
                    : actions.onLap),
        const SizedBox(height: 8),
        if (isSmart && s.project?.type == ProjectType.mezuza) ...[
          SoferSecondaryButton("עבור למזוזה הבאה",
              icon: Icons.skip_next,
              expand: true,
              onPressed: s.isSavingLine ? null : actions.onSkipMezuza),
          const SizedBox(height: 8),
        ],
        Row(children: [
          Expanded(
            child: SoferSecondaryButton("הפסקה",
                icon: Icons.coffee,
                expand: true,
                onPressed: s.isSavingLine ? null : actions.onBreak),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SoferSecondaryButton("סיים",
                icon: Icons.stop,
                expand: true,
                onPressed: s.isSavingLine ? null : actions.onStop),
          ),
        ]),
      ] else ...[
        // Plain mode has no line to mark, and a paused sitting has nothing to
        // mark yet — so stopping is the leading action again.
        SoferPrimaryButton("סיים",
            icon: Icons.stop, expand: true, onPressed: actions.onStop),
        const SizedBox(height: 8),
        SoferSecondaryButton(
          s.isPaused ? "המשך" : "הפסקה",
          icon: s.isPaused ? Icons.play_arrow : Icons.coffee,
          expand: true,
          // Resuming is its own action, which is why HomeActions carries one.
          // This button said "המשך" and called onBreak, so pressing it paused
          // again: in plain mode the writer was stuck in a break with no way
          // back to writing except ending the sitting, and in smart mode the
          // break dialog reopened. The cards layout has always had this right.
          onPressed: s.isPaused ? actions.onResume : actions.onBreak,
        ),
      ],
    ]);
  }
}

/// The figures: what today produced, what it pays, and when the job lands.
class _FiguresColumn extends StatelessWidget {
  final HomeSnapshot snapshot;

  const _FiguresColumn({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final s = snapshot;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SoferSectionTitle("היום", padding: EdgeInsets.zero),
              Text(s.hebrewDate,
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 13,
                      color: t.inkMuted)),
            ],
          ),
          const SizedBox(height: 10),
          SoferStatRow("נכתב", s.todayOutput),
          if (s.hourlyRate case final rate?)
            SoferStatRow("לשעה", rate, emphasise: true),
          if (s.doneOfTotal case final done?)
            SoferStatRow("מהעבודה", done, last: true),
          if (s.doneOfTotal != null) ...[
            const SizedBox(height: 12),
            SoferProgress(s.progress),
          ],
          if (s.completion case final finishOn?) ...[
            const SizedBox(height: 20),
            const SoferRule(strong: true),
            const SizedBox(height: 12),
            SoferSectionTitle("צפי סיום", padding: EdgeInsets.zero),
            const SizedBox(height: 5),
            Text(finishOn,
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 19, color: t.ink)),
            if (s.completionDetail case final detail?) ...[
              const SizedBox(height: 4),
              Text(detail,
                  style: TextStyle(
                      fontFamily: t.labelFamily,
                      fontSize: 12,
                      color: t.inkMuted)),
            ],
          ],
        ],
      ),
    );
  }
}

/// No commissions yet — an invitation rather than an empty screen.
class _EmptyState extends StatelessWidget {
  final String hebrewDate;

  const _EmptyState({required this.hebrewDate});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(hebrewDate,
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 13,
                    letterSpacing: 1.5,
                    color: t.inkMuted)),
            const SizedBox(height: 18),
            Text("אין עוד פרויקטים",
                style: TextStyle(
                    fontFamily: t.numeralFamily, fontSize: 24, color: t.ink)),
            const SizedBox(height: 8),
            Text(
              "פתח פרויקט ראשון כדי להתחיל למדוד כתיבה, רווח וצפי סיום.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: t.labelFamily,
                  fontSize: 14,
                  height: 1.6,
                  color: t.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
