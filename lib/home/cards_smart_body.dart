import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'ruled_home_body.dart';

/// Smart mode in the cards layout, used by the modern theme.
///
/// The position leads and the clock sits under it — the same order of
/// importance the ruled layout gives smart mode, arrived at independently and
/// then written out twice. Two hundred and seventy lines of it lived in the
/// home screen, reading that screen's fields directly.
///
/// It takes the same [HomeSnapshot] and [HomeActions] the ruled body does. They
/// are two drawings of one screen, and anything the two need to disagree about
/// is a thing worth noticing rather than a thing to add a field for.
class CardsSmartBody extends StatelessWidget {
  final HomeSnapshot snapshot;
  final HomeActions actions;

  /// Drives the fade on the clock while the writer is at work. Belongs to the
  /// screen, which owns the ticker.
  final Animation<double> pulse;

  const CardsSmartBody({
    super.key,
    required this.snapshot,
    required this.actions,
    required this.pulse,
  });

  /// Which commission to work on. Offered only before a sitting starts —
  /// changing it underneath a running clock would leave the measured time
  /// attributed to whichever project happened to be showing at the end.
  Widget _projectPicker() => Padding(
        padding: const EdgeInsets.all(20.0),
        child: DropdownButtonFormField<Project>(
          decoration: const InputDecoration(
            labelText: "בחר פרויקט להתחלת עבודה",
            border: OutlineInputBorder(),
          ),
          initialValue: snapshot.project,
          items: snapshot.projects
              .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
              .toList(),
          onChanged: actions.onProjectChanged,
        ),
      );

  /// Where the writer is, or where they left off.
  Widget _position(BuildContext context) {
    return Semantics(
      button: true,
      label: 'שינוי מיקום',
      child: InkWell(
        onTap: actions.onEditPosition,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!snapshot.isActive) ...[
                const Text('ממשיך מ'),
                const SizedBox(height: 6),
              ],
              Text(
                snapshot.positionTitle ??
                    "${snapshot.positionUnit} ${snapshot.currentLine}",
                style: TextStyle(
                  fontSize: snapshot.positionTitle != null ? 34 : 48,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                snapshot.pageLabel,
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The "writing…" badge, and what replaces it during a break.
  Widget _state(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (snapshot.isPaused) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "בהפסקה: ${snapshot.breakElapsed}",
            style: TextStyle(
              color: scheme.tertiary,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          // The minus is the point: at a glance, is this time still owed to
          // him or time he has already taken?
          if (snapshot.breakRemaining.isNotEmpty)
            Text(
              snapshot.breakOverrun
                  ? "חריגה: ${snapshot.breakRemaining}"
                  : "נותרו: ${snapshot.breakRemaining}",
              style: TextStyle(
                color: snapshot.breakOverrun
                    ? SoferTokens.of(context).danger
                    : SoferTokens.of(context).inkMuted,
                fontWeight:
                    snapshot.breakOverrun ? FontWeight.bold : FontWeight.normal,
                fontSize: 15,
              ),
            ),
        ],
      );
    }
    if (!snapshot.isRunning) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FadeTransition(
        opacity: pulse,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.brush, color: scheme.onSecondaryContainer, size: 26),
              const SizedBox(width: 8),
              Text("כותב...",
                  style: TextStyle(
                      color: scheme.onSecondaryContainer,
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clocks(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget metric(String label, String value, {bool danger = false}) =>
        Expanded(
          child: Column(
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value,
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w300,
                        color: danger
                            ? SoferTokens.of(context).danger
                            : snapshot.isPaused
                                ? scheme.onSurfaceVariant
                                : scheme.onSurface)),
              ),
            ],
          ),
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            metric('זמן כתיבה', snapshot.elapsed),
            Container(
                width: 1,
                height: 48,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: scheme.outlineVariant),
            metric(snapshot.shownLineLabel, snapshot.shownLineValue,
                danger: snapshot.lineClockOverrun),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    if (!snapshot.isActive) {
      return ElevatedButton.icon(
        onPressed: actions.onStart,
        icon: const Icon(Icons.login),
        label: const Text("כניסה"),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          textStyle: const TextStyle(fontSize: 20),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ElevatedButton.icon(
          // Nothing was written during a break, so there is no line to finish.
          onPressed: snapshot.isPaused || snapshot.isSavingLine
              ? null
              : actions.onNextLine,
          icon: const Icon(Icons.arrow_downward),
          label: const Text("מעבר שורה (סיימתי)"),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 25),
            textStyle: const TextStyle(fontSize: 22),
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
          ),
        ),
        if (snapshot.project?.type == ProjectType.mezuza) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: snapshot.isPaused ? null : actions.onSkipMezuza,
            icon: const Icon(Icons.skip_next),
            label: const Text('עבור למזוזה הבאה'),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 20,
          children: [
            ElevatedButton.icon(
              onPressed: snapshot.isSavingLine
                  ? null
                  : snapshot.isPaused
                      ? actions.onResume
                      : actions.onBreak,
              icon: Icon(snapshot.isPaused ? Icons.play_arrow : Icons.coffee),
              label: Text(snapshot.isPaused ? "המשך כתיבה" : "הפסקת קפה"),
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
              ),
            ),
            ElevatedButton.icon(
              onPressed: snapshot.isSavingLine ? null : actions.onStop,
              icon: const Icon(Icons.logout),
              label: const Text("יציאה"),
              style: ElevatedButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!snapshot.isActive) _projectPicker(),
            if (snapshot.project != null) ...[
              _position(context),
              const SizedBox(height: 30),
              if (snapshot.isActive)
                _clocks(context)
              else
                Text(snapshot.elapsed,
                    style: const TextStyle(
                        fontSize: 64, fontWeight: FontWeight.w200)),
              _state(context),
              if (snapshot.hasHomeAdditions) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: HomeAdditionsPanel(snapshot: snapshot),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _controls(context),
            ],
          ],
        ),
      ),
    );
  }
}
