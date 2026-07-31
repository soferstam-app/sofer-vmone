/// How a duration reads on screen.
///
/// Two shapes, and they are not interchangeable. A clock is what a running
/// timer shows and what a measured sitting reports; a span is what a sentence
/// says about a stretch of work. The app had four private copies of one or the
/// other scattered through the screens.
library;

/// `01:14:32` — a stretch of time read as a clock.
String formatClock(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  return '${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}'
      ':${twoDigits(d.inSeconds.remainder(60))}';
}

/// `1 שע' 14 דק'` — a stretch of time read as a sentence would say it.
String formatSpan(Duration d) {
  if (d.inHours > 0) {
    final minutes = d.inMinutes.remainder(60);
    return minutes > 0 ? "${d.inHours} שע' $minutes דק'" : "${d.inHours} שע'";
  }
  return "${d.inMinutes} דק'";
}
