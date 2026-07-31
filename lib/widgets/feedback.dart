import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The two things a screen says back to the writer.
///
/// Both were private to the home screen while fifteen other places reached for
/// `showSnackBar` directly, each choosing its own colour — which meant a failure
/// looked like a confirmation in some corners of the app.

/// Something worked, and it is worth saying so.
void showAppSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: SoferTokens.of(context).positive,
    ),
  );
}

/// Something cannot be done, and why.
void showAppError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message,
          style: TextStyle(color: SoferTokens.of(context).danger)),
    ),
  );
}
