import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The pieces every screen is built from.
///
/// Each one knows how to render itself in both layouts, so a screen is written
/// once and works in all three themes. This is what keeps a third look from
/// costing a third copy of the app: when a feature is added later, it is added
/// here or composed from here, and it appears everywhere at once.
///
/// The two renderings differ in kind, not just in colour:
///
/// * [AppLayout.cards] — a raised surface with a radius, separated by space.
/// * [AppLayout.rules] — no surface at all, separated by a hairline, the way
///   ruling separates the columns of a page.

/// A bounded group of related content.
class SoferPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// Draws the heavier rule above the panel, for the first panel in a run.
  final bool topRule;

  const SoferPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.topRule = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);

    if (t.isCards) {
      return Card(
        margin: margin == EdgeInsets.zero
            ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
            : margin,
        elevation: 3,
        child: Padding(padding: padding, child: child),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        border: Border(
          top: topRule ? BorderSide(color: t.ruleStrong) : BorderSide.none,
          bottom: BorderSide(color: t.ruleStrong),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A label on one side and a value on the other — the workhorse of every
/// summary in the app.
class SoferStatRow extends StatelessWidget {
  final String label;
  final String value;

  /// Draws the value in the accent. Reserved for the hourly rate and for the
  /// timer, so the accent keeps meaning something.
  final bool emphasise;

  /// The last row in a group carries no rule of its own.
  final bool last;

  const SoferStatRow(
    this.label,
    this.value, {
    super.key,
    this.emphasise = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final labelStyle = TextStyle(
      fontFamily: t.labelFamily,
      fontSize: 13,
      color: t.inkMuted,
      fontWeight: t.isCards ? FontWeight.bold : FontWeight.normal,
    );
    final valueStyle = TextStyle(
      fontFamily: t.numeralFamily,
      fontSize: t.isRules ? 20 : 15,
      color: emphasise ? t.accent : t.ink,
    );

    return Container(
      decoration: t.isRules && !last
          ? BoxDecoration(border: Border(bottom: BorderSide(color: t.rule)))
          : null,
      padding: EdgeInsets.symmetric(vertical: t.isRules ? 9 : 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Both sides flex, loosely: each takes only the width it needs, and
          // wraps rather than overflowing when it cannot have it. The value gets
          // the larger share because values here are the longer of the two —
          // "0 עמודים ו-38 שורות" against "נכתב".
          Flexible(flex: 2, child: Text(label, style: labelStyle)),
          const SizedBox(width: 10),
          Flexible(
            flex: 3,
            child: Text(value, textAlign: TextAlign.end, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

/// A small caption above a group. Sits in the accent colour in cards, and as
/// tracked-out muted type in rules.
class SoferSectionTitle extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SoferSectionTitle(this.text,
      {super.key, this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 4)});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: t.labelFamily,
          fontSize: 12,
          letterSpacing: t.isRules ? 1.5 : 0,
          fontWeight: t.isCards ? FontWeight.bold : FontWeight.normal,
          color: t.isCards ? t.accent : t.inkMuted,
        ),
      ),
    );
  }
}

/// A figure meant to be read first — a timer, a line number, a total.
class SoferNumber extends StatelessWidget {
  final String value;
  final double size;
  final bool emphasise;

  /// Small caption under the figure.
  final String? caption;

  const SoferNumber(
    this.value, {
    super.key,
    this.size = 32,
    this.emphasise = false,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: t.numeralFamily,
            fontSize: size,
            height: 1,
            // The serif reads as heavy already; bolding it muddies the shapes.
            fontWeight: t.isRules ? FontWeight.w400 : FontWeight.bold,
            letterSpacing: t.isRules ? -1 : 0,
            color: emphasise ? t.accent : t.ink,
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 5),
          Text(
            caption!,
            style: TextStyle(
              fontFamily: t.labelFamily,
              fontSize: 12,
              letterSpacing: t.isRules ? 1.2 : 0,
              color: t.inkMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// How far along something is.
///
/// A filled bar in cards; in rules, a short accent segment against a hairline —
/// the same information without pretending to be a physical object.
class SoferProgress extends StatelessWidget {
  /// 0 to 1.
  final double value;

  const SoferProgress(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final fraction = value.clamp(0.0, 1.0);

    if (t.isCards) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: fraction, minHeight: 8),
      );
    }

    // Laid out by flex rather than by a LayoutBuilder. A LayoutBuilder reports
    // no intrinsic height, and this bar sits inside columns whose height has to
    // be measurable — a bar that cannot be measured made the whole page
    // scroll without end. A hair of accent even at zero, so the bar still
    // reads as a scale rather than as a missing element.
    const scale = 1000;
    final filled = (fraction * scale).round().clamp(4, scale);
    return SizedBox(
      height: 3,
      child: Row(children: [
        Expanded(flex: filled, child: ColoredBox(color: t.accent)),
        if (filled < scale)
          Expanded(flex: scale - filled, child: ColoredBox(color: t.rule)),
      ]),
    );
  }
}

/// The grid of pages, or of mezuzot, in a commission.
///
/// Belongs to every theme, not only the ruled ones — it was already in the app
/// before the redesign. Cards give it a radius; rules give it a hairline.
class SoferUnitGrid extends StatelessWidget {
  final int total;
  final int done;
  final int columns;

  const SoferUnitGrid({
    super.key,
    required this.total,
    required this.done,
    this.columns = 16,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    // A sefer has 245 pages; drawn one per page the cells vanish, so beyond a
    // few hundred the grid summarises rather than enumerates.
    final cells = total <= columns * 8 ? total : columns * 8;
    final filled = total <= 0 ? 0 : (cells * (done / total)).round();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 1 / 1.4,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: cells,
      itemBuilder: (context, i) {
        final isDone = i < filled;
        return Container(
          decoration: BoxDecoration(
            color: isDone ? t.accent : Colors.transparent,
            border: isDone ? null : Border.all(color: t.rule),
            borderRadius: BorderRadius.circular(t.isCards ? 2 : 0),
          ),
        );
      },
    );
  }
}

/// A three-way choice, used for the working-day categories.
class SoferChoice<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const SoferChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final o in options)
          ButtonSegment(value: o.value, label: Text(o.label)),
      ],
      selected: {selected},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

/// The one action a screen most expects to be taken.
class SoferPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  const SoferPrimaryButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? null : Icon(icon, size: 20),
      label: Text(label,
          style: TextStyle(fontFamily: t.labelFamily, fontSize: 15)),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Everything else.
class SoferSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  /// Draws the button in the faint outline, for the least likely of several
  /// actions sitting side by side.
  final bool quiet;

  const SoferSecondaryButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.expand = false,
    this.quiet = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon == null ? null : Icon(icon, size: 20),
      label: Text(label,
          style: TextStyle(fontFamily: t.labelFamily, fontSize: 15)),
      style: OutlinedButton.styleFrom(
        foregroundColor: quiet ? t.inkMuted : t.ink,
        side: BorderSide(color: quiet ? t.rule : t.ink),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A horizontal separator between areas of a screen.
class SoferRule extends StatelessWidget {
  /// The heavier of the two weights, for a boundary between areas rather than
  /// between rows.
  final bool strong;

  const SoferRule({super.key, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final t = SoferTokens.of(context);
    return Container(height: 1, color: strong ? t.ruleStrong : t.rule);
  }
}

/// Wraps a screen's body so a wide desktop window gets a readable measure
/// instead of rows stretched across the whole display.
class SoferPage extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const SoferPage({super.key, required this.child, this.maxWidth = 860});

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
