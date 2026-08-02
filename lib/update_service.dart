import 'dart:convert';
import 'dart:io';

import 'logic/version_check.dart';
import 'version.dart';

/// Asks GitHub whether there is a newer release.
///
/// One unauthenticated GET, and the only request this app ever makes that the
/// writer did not ask for by name — which is why it is made only when they
/// press the button. GitHub learns an IP address and a user agent; nothing
/// about the writer or their work leaves the device.
///
/// This replaced `auto_updater`, which wraps Sparkle and WinSparkle and needs
/// an appcast XML feed signed with a second key. It was being handed the URL of
/// an HTML page — two different ones, in two different places — so it could
/// never have worked. And on Android it could never have helped either: an app
/// may not install another, so the only honest offer is a link.
class UpdateService {
  static const String _releasesApi =
      'https://api.github.com/repos/soferstam-app/sofer-vmone/releases/latest';

  /// Beyond this, the writer has been kept waiting for nothing.
  ///
  /// A good part of this audience is behind content filtering that may block
  /// the API outright. Failing is ordinary here, so it has to be quick and it
  /// has to be quiet.
  static const Duration timeout = Duration(seconds: 5);

  const UpdateService();

  Future<UpdateStatus> check({String currentVersion = appVersion}) async {
    final running = Version.tryParse(currentVersion);
    if (running == null) {
      return UpdateCheckFailed('גרסה לא מזוהה: $currentVersion');
    }

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client.getUrl(Uri.parse(_releasesApi));
      // GitHub asks for a user agent and answers 403 without one.
      request.headers.set(HttpHeaders.userAgentHeader, 'sofer-vmone/$appVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');

      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        // 404 means no release has been published yet, which is not a fault
        // and must not be reported as one.
        return response.statusCode == 404
            ? UpToDate(running)
            : UpdateCheckFailed('גיטהאב השיב ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return const UpdateCheckFailed('תשובה לא צפויה מגיטהאב');
      }

      return readLatestRelease(
        json: Map<String, dynamic>.from(decoded),
        running: running,
      );
    } catch (_) {
      // Blocked, offline, timed out, or malformed. The writer does not need to
      // know which, and none of them is a problem with their app.
      return const UpdateCheckFailed('לא הצלחתי לבדוק עדכונים כרגע');
    } finally {
      client?.close(force: true);
    }
  }
}
