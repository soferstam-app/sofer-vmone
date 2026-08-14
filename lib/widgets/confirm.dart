import 'package:flutter/material.dart';

import '../hebrew_utils.dart';
import '../theme/app_theme.dart';

/// Asking the writer before doing something they cannot take back.
///
/// Six screens built this dialog by hand, and it showed: the same button said
/// "ביטול" in five of them and "המשך בהזנה" in the sixth, and only two of the
/// destructive ones were coloured as destructive. Worse, the one question about
/// writing over work already recorded was written out three separate times, in
/// three slightly different sentences, so the app asked the same thing three
/// ways depending on which screen the writer happened to be on.

/// Asks a yes-or-no question and waits for the answer.
///
/// Returns false when the dialog is dismissed by tapping outside it, which is a
/// writer backing away from the question rather than answering it.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'ביטול',
  bool danger = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          // Destructive answers are set apart and coloured. The writer should
          // not have to read the label twice to know which button undoes work.
          if (danger)
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: SoferTokens.of(ctx).danger),
              child: Text(confirmLabel),
            )
          else
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(confirmLabel),
            ),
        ],
      ),
    ) ??
    false;

/// The one question about writing over lines already recorded.
///
/// Not an error: a sofer correcting a page writes over lines he has written
/// before, and that is ordinary work. It is asked because the other reading —
/// that he has lost his place and is about to record the same writing twice —
/// is the one he would want to catch.
///
/// [pages] names them where the caller knows which; [range] says the entry
/// covers a stretch of pages rather than one, which is the only case where
/// neither "this page" nor a list of them would be true.
Future<bool> confirmOverlap(
  BuildContext context, {
  List<int> pages = const [],
  bool range = false,
}) {
  final where = switch (pages.length) {
    0 => range ? 'בטווח העמודים' : 'בעמוד זה',
    1 => 'בעמוד ${formatHebrewNumber(pages.first)}',
    _ => 'בעמודים ${pages.map(formatHebrewNumber).join(', ')}',
  };
  return confirmAction(
    context,
    title: 'שים לב: כפילות',
    message: 'חלק מהשורות $where כבר נכתבו בעבר. לשמור בכל זאת?',
    confirmLabel: 'שמור בכל זאת',
  );
}
