import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The three things a screen says back to the writer.
///
/// These were private to the home screen while a dozen other places reached for
/// `showSnackBar` directly, each choosing its own colour — which meant a failure
/// looked like a confirmation in some corners of the app.
///
/// Each of those places also chose how long its message stayed up, by hand and
/// by feel: five seconds here, six there, eight for the longest. They were not
/// wrong, they were all reaching for the same rule without saying it, which is
/// that a message has to stay up long enough to be read. [_readingTime] states
/// it once, and it reproduces every number they had picked.

/// How long a message needs to be on screen.
///
/// Material's four seconds is right for a confirmation and much too short for
/// a file path or a summary of an import. Below the floor nobody has time to
/// look up; above the ceiling the writer is being held hostage by a
/// notification and should be reading a screen instead.
Duration _readingTime(String message) => Duration(
      milliseconds: math.max(
        4000,
        math.min(10000, 2000 + message.length * 55),
      ),
    );

/// Something worked, and it is worth saying so.
void showAppSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      // Read from the theme rather than assumed. White was hardcoded here, and
      // on the parchment theme it sits on a light green that it cannot be read
      // against.
      content: Text(message,
          style: TextStyle(color: SoferTokens.of(context).paper)),
      backgroundColor: SoferTokens.of(context).positive,
      duration: _readingTime(message),
    ),
  );
}

/// Something cannot be done, and why.
void showAppError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message,
          style: TextStyle(color: SoferTokens.of(context).paper)),
      backgroundColor: SoferTokens.of(context).danger,
      duration: _readingTime(message),
    ),
  );
}

/// A passing remark — neither a result nor a problem.
///
/// Deliberately brief and deliberately not [_readingTime]: this is what marks a
/// finished line while the writer is writing, several times a minute, and it
/// has to be gone before the next one wants the space.
void showAppNote(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message,
          style: TextStyle(color: SoferTokens.of(context).paper)),
      backgroundColor: SoferTokens.of(context).inkMuted,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
