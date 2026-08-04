import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/feedback.dart';

/// Shows the progress update, and then offers to send it.
///
/// It used to go straight to a `mailto:` link, which fails in two ways a writer
/// cannot tell apart from the app being broken. On Windows the launch reports
/// success and nothing opens when no mail client is registered; and the body,
/// percent-encoded from Hebrew at three bytes a character, can outrun the
/// length a URL is allowed to be — so the mail opens with the text cut off, or
/// not at all. Writers reported it as "the button does nothing", which is
/// precisely what it did.
///
/// So the text is put on the screen first. Whatever happens to the mail client
/// afterwards, the writer has his update and can send it however he likes.
Future<void> showClientUpdate({
  required BuildContext context,
  required String body,
  required String subject,
  String? to,
}) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = SoferTokens.of(ctx);
      return AlertDialog(
        title: const Text('עדכון ללקוח'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (to != null && to.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('אל: $to',
                        style: TextStyle(
                            fontFamily: t.labelFamily,
                            fontSize: 12,
                            color: t.inkMuted)),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.rule),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  // Selectable, so he can take part of it if that is all he
                  // wants. The copy button is for the whole thing.
                  child: SelectableText(body,
                      style: TextStyle(fontSize: 13, height: 1.6, color: t.ink)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('סגור'),
          ),
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('העתק'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: body));
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              showAppSuccess(context, 'העדכון הועתק');
            },
          ),
          if (to != null && to.isNotEmpty)
            ElevatedButton.icon(
              icon: const Icon(Icons.email, size: 18),
              label: const Text('פתח במייל'),
              onPressed: () async {
                Navigator.pop(ctx);
                // Subject only. The body goes on the clipboard instead of into
                // the URL, which is what kept it from arriving at all.
                await Clipboard.setData(ClipboardData(text: body));
                final uri = Uri(
                  scheme: 'mailto',
                  path: to,
                  query: 'subject=${Uri.encodeComponent(subject)}',
                );
                var opened = false;
                try {
                  opened = await launchUrl(uri);
                } catch (_) {
                  opened = false;
                }
                if (!context.mounted) return;
                opened
                    ? showAppSuccess(
                        context, 'נפתח מייל — הטקסט הועתק, הדבק אותו בגוף')
                    : showAppError(context,
                        'לא נמצאה תוכנת מייל. הטקסט הועתק — אפשר להדביק אותו בכל מקום');
              },
            ),
        ],
      );
    },
  );
}
