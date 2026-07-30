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

  /// Smart mode only: where the writer is right now.
  final int currentPage;
  final int currentLine;

  /// What the project counts in — "שורה", "מזוזה", "פרשייה".
  final String positionUnit;

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
    required this.currentPage,
    required this.currentLine,
    required this.positionUnit,
    required this.todayOutput,
    this.hourlyRate,
    this.doneOfTotal,
    this.progress = 0,
    this.completion,
    this.completionDetail,
  });

  bool get isActive => isRunning || isPaused;
}

/// What the ruled home screen can do. Held together so the layout never has to
/// know which of them the timer cares about.
class HomeActions {
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onBreak;
  final VoidCallback onManualEntry;
  final VoidCallback onNextLine;
  final VoidCallback onEditPosition;
  final ValueChanged<Project?> onProjectChanged;

  const HomeActions({
    required this.onStart,
    required this.onStop,
    required this.onBreak,
    required this.onManualEntry,
    required this.onNextLine,
    required this.onEditPosition,
    required this.onProjectChanged,
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

    if (snapshot.project == null) {
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

          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: left),
                Container(width: 1, color: t.rule),
                Expanded(child: right),
              ],
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
              decoration: const InputDecoration(border: UnderlineInputBorder()),
              items: [
                for (final p in s.projects)
                  DropdownMenuItem(value: p, child: Text(p.name)),
              ],
              onChanged: actions.onProjectChanged,
            ),

          const SizedBox(height: 18),
          const SoferRule(),
          const SizedBox(height: 16),

          if (isSmart && s.isActive)
            _PositionHero(snapshot: s, onEdit: actions.onEditPosition)
          else
            _ClockHero(snapshot: s),

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (s.isRunning && !s.isPaused) ...[
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsetsDirectional.only(end: 10),
                decoration:
                    BoxDecoration(color: t.accent, shape: BoxShape.circle),
              ),
            ],
            Text(
              "${s.positionUnit} ${s.currentLine}",
              style: TextStyle(
                fontFamily: t.numeralFamily,
                fontSize: 58,
                height: 1,
                letterSpacing: -2,
                color: t.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.project!.type == ProjectType.mezuza
              ? "מזוזה ${s.currentPage}"
              : "עמוד ${s.currentPage}",
          style: TextStyle(
              fontFamily: t.numeralFamily, fontSize: 19, color: t.inkMuted),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text(
            s.elapsed,
            style: TextStyle(
              fontFamily: t.numeralFamily,
              fontSize: 25,
              color: s.isPaused ? t.inkMuted : t.ink,
            ),
          ),
          const SizedBox(width: 12),
          if (s.isPaused)
            Text("בהפסקה",
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 13,
                    color: t.inkMuted)),
        ]),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: onEdit,
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          icon: const Icon(Icons.edit_location_alt, size: 18),
          label: const Text("ערוך מיקום"),
        ),
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (s.isRunning && !s.isPaused)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsetsDirectional.only(end: 10),
                decoration:
                    BoxDecoration(color: t.accent, shape: BoxShape.circle),
              ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  s.elapsed,
                  style: TextStyle(
                    fontFamily: t.numeralFamily,
                    fontSize: 56,
                    height: 1,
                    letterSpacing: -1,
                    color: s.isPaused ? t.inkMuted : t.ink,
                  ),
                ),
              ),
            ),
          ],
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
      return Column(children: [
        SoferPrimaryButton("תחילת כתיבה",
            icon: Icons.play_arrow, expand: true, onPressed: actions.onStart),
        const SizedBox(height: 8),
        SoferSecondaryButton("הזנה ידנית",
            icon: Icons.edit_calendar,
            expand: true,
            quiet: true,
            onPressed: actions.onManualEntry),
      ]);
    }

    return Column(children: [
      SoferPrimaryButton("עצור וסיים",
          icon: Icons.stop, expand: true, onPressed: actions.onStop),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: SoferSecondaryButton(
            s.isPaused ? "המשך" : "הפסקה",
            icon: s.isPaused ? Icons.play_arrow : Icons.coffee,
            expand: true,
            onPressed: actions.onBreak,
          ),
        ),
        if (isSmart) ...[
          const SizedBox(width: 8),
          Expanded(
            child: SoferSecondaryButton("סיימתי שורה",
                icon: Icons.flag, expand: true, onPressed: actions.onNextLine),
          ),
        ],
      ]),
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
