import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../logic/production_calculator.dart';
import '../models.dart';
import '../theme/app_theme.dart';

/// What has been written, drawn as the thing itself.
///
/// A sefer is a grid of pages and a set of tefillin is eight parshiyot, and
/// both read faster as a picture than as a percentage. Two hundred and forty
/// lines of drawing lived in the project summary alongside its arithmetic and
/// its client letter; nothing here needs any of that, only a commission and
/// the work recorded against it.

Widget seferProgressGrid(
    BuildContext context, Project project, List<WorkSession> sessions) {
  int totalPages = project.totalPages ?? 245;
  final int linesPerPage = ProductionCalculator.linesPerPageOf(project);

  Map<int, Set<int>> pageContent = {};
  for (var s in sessions) {
    if (s.amount > 0) {
      pageContent.putIfAbsent(s.amount, () => {});
      for (int i = s.startLine; i <= s.endLine; i++) {
        pageContent[s.amount]!.add(i);
      }
    }
  }

  final t = SoferTokens.of(context);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
        child: Row(
          children: [
            Expanded(
              child: Text("מפת העמודים",
                  style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 12,
                    letterSpacing: t.isRules ? 1.5 : 0,
                    fontWeight: t.isCards ? FontWeight.bold : FontWeight.normal,
                    color: t.isCards ? t.accent : t.inkMuted,
                  )),
            ),
            Text("$totalPages עמודים · לחיצה לפרטים",
                style: TextStyle(
                    fontFamily: t.labelFamily,
                    fontSize: 11,
                    color: t.inkFaint)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        // A page-per-cell map of the whole scroll. Sized by a maximum cell
        // extent rather than a fixed column count: at six across, 245 pages
        // came to nearly six thousand pixels of grid and pushed everything
        // below it off the screen.
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 30,
            childAspectRatio: 1 / 1.35,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
          ),
          itemCount: totalPages,
          itemBuilder: (context, index) {
            int pageNum = index + 1;
            Set<int> lines = pageContent[pageNum] ?? {};
            double progress = lines.length / linesPerPage;
            if (progress > 1.0) progress = 1.0;

            return InkWell(
              onTap: () =>
                  _showSeferPageDetails(context, pageNum, lines, linesPerPage),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: SoferTokens.of(context).rule),
              // How far into the page the writing got, filled from the top.
              // The accent marks what is done, here as everywhere.
              gradient: progress > 0
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        SoferTokens.of(context).accent,
                        SoferTokens.of(context).accent,
                        SoferTokens.of(context).paper,
                        SoferTokens.of(context).paper,
                      ],
                      stops: [0.0, progress, progress, 1.0],
                    )
                  : null,
                  color:
                      progress == 0 ? SoferTokens.of(context).paper : null,
                ),
                alignment: Alignment.center,
                // At this size only the shortest numerals fit, and the map is
                // read as a shape rather than page by page — the number is in
                // the tap.
                child: progress > 0
                    ? null
                    : Text(
                        formatHebrewNumber(pageNum),
                        style: TextStyle(
                          fontSize: 9,
                          color: SoferTokens.of(context).inkFaint,
                        ),
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                      ),
              ),
            );
          },
        ),
      ),
    ],
  );
}

void _showSeferPageDetails(
    BuildContext context, int page, Set<int> lines, int maxLines) {
  String msg;
  if (lines.length >= maxLines) {
    msg = "מושלם, זיכית יהודים בעוד מוצר סת\"ם כשר ומהודר";
  } else if (lines.isEmpty) {
    msg = "טרם נכתב";
  } else {
    List<int> sorted = lines.toList()..sort();
    List<String> ranges = [];
    if (sorted.isNotEmpty) {
      int start = sorted.first;
      int end = start;
      for (int i = 1; i < sorted.length; i++) {
        if (sorted[i] == end + 1) {
          end = sorted[i];
        } else {
          ranges.add(start == end ? "$start" : "$start-$end");
          start = sorted[i];
          end = start;
        }
      }
      ranges.add(start == end ? "$start" : "$start-$end");
    }
    msg = "שורות שנכתבו: ${ranges.join(', ')}";
  }

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text("עמוד ${formatHebrewNumber(page)}"),
      content: Text(msg),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text("סגור"))
      ],
    ),
  );
}

Widget tefillinProgressGrid(
    BuildContext context, Project project, List<WorkSession> sessions) {
  List<int> counts = List.filled(8, 0);

  for (var s in sessions) {
    if (s.tefillinType == null && s.parshiya == null) {
      for (int i = 0; i < 8; i++) {
        counts[i] += s.amount;
      }
    } else if (s.tefillinType == 'head' && s.parshiya == null) {
      for (int i = 0; i < 4; i++) {
        counts[i] += s.amount;
      }
    } else if (s.tefillinType == 'hand' && s.parshiya == null) {
      for (int i = 4; i < 8; i++) {
        counts[i] += s.amount;
      }
    } else if (s.tefillinType != null && s.parshiya != null) {
      int max = s.tefillinType == 'head' ? 4 : 7;
      if (s.endLine == 0 || s.endLine >= max) {
        int base = s.tefillinType == 'head' ? 0 : 4;
        int idx = base + (s.parshiya! - 1);
        if (idx >= 0 && idx < 8) counts[idx] += s.amount;
      }
    }
  }

  return Padding(
    padding: const EdgeInsets.all(16.0),
    child: Column(
      children: [
        const Text("תפילין של ראש",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children:
              List.generate(4, (i) => _tefillinBox(context, i, counts[i], true)),
        ),
        const SizedBox(height: 24),
        const Text("תפילין של יד",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(
              4, (i) => _tefillinBox(context, i, counts[i + 4], false)),
        ),
      ],
    ),
  );
}

Widget _tefillinBox(BuildContext context, int index, int count, bool isHead) {
  List<String> names = ["קדש", "והיה כי יביאך", "שמע", "והיה אם שמוע"];
  String name = names[index];

  return InkWell(
    onTap: () {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text("פרשיית $name (${isHead ? 'ראש' : 'יד'})"),
          content: Text("נכתבו בשלמות: $count"),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("סגור"))
          ],
        ),
      );
    },
    child: Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: count > 0 ? SoferTokens.of(context).paper : SoferTokens.of(context).rule,
        border: Border.all(color: SoferTokens.of(context).accent),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ),
  );
}
