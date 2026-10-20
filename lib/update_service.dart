import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'logic/version_check.dart';
import 'version.dart';

typedef HttpClientFactory = HttpClient Function();

/// A downloaded release that has passed size and SHA-256 verification.
final class DownloadedUpdate {
  final UpdateAvailable release;
  final File file;
  final Directory workingDirectory;

  const DownloadedUpdate({
    required this.release,
    required this.file,
    required this.workingDirectory,
  });
}

/// Progress while the release artifact is being transferred.
final class UpdateDownloadProgress {
  final int received;
  final int total;

  const UpdateDownloadProgress(this.received, this.total);

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

/// A failure that can be shown without exposing an exception dump or
/// pretending every network failure has the same cause.
final class UpdateException implements Exception {
  final String message;
  final Object? cause;

  const UpdateException(this.message, [this.cause]);

  @override
  String toString() => message;
}

/// Finds and downloads a published update from GitHub Releases.
///
/// Nothing happens in the background. A check is made only when the writer
/// presses the update row; downloading begins only after a second confirmation.
/// GitHub learns an IP address, a user agent and which published asset is being
/// downloaded. No writing data or settings leave the device.
class UpdateService {
  static const String releasesApi =
      'https://api.github.com/repos/soferstam-app/sofer-vmone/releases/latest';

  static const Duration connectionTimeout = Duration(seconds: 15);
  static const Duration responseTimeout = Duration(seconds: 30);
  static const Duration downloadIdleTimeout = Duration(seconds: 45);

  final HttpClientFactory? _clientFactory;
  final UpdatePlatform? _platformOverride;

  const UpdateService({
    HttpClientFactory? clientFactory,
    UpdatePlatform? platformOverride,
  })  : _clientFactory = clientFactory,
        _platformOverride = platformOverride;

  UpdatePlatform? get _platform {
    if (_platformOverride != null) return _platformOverride;
    if (Platform.isAndroid) return UpdatePlatform.android;
    if (Platform.isWindows) return UpdatePlatform.windows;
    return null;
  }

  HttpClient _newClient() {
    final client = _clientFactory?.call() ?? HttpClient();
    client.connectionTimeout = connectionTimeout;
    return client;
  }

  Future<UpdateStatus> check(
      {String currentVersion = appVersion, bool english = false}) async {
    final running = Version.tryParse(currentVersion);
    if (running == null) {
      return UpdateCheckFailed(english
          ? 'Unrecognized version: $currentVersion'
          : 'גרסה לא מזוהה: $currentVersion');
    }

    final platform = _platform;
    if (platform == null) {
      return UpdateCheckFailed(english
          ? 'Direct updates are currently supported only on Android and Windows'
          : 'עדכון ישיר נתמך כרגע רק ב־Android וב־Windows');
    }

    HttpClient? client;
    try {
      client = _newClient();
      final request =
          await client.getUrl(Uri.parse(releasesApi)).timeout(responseTimeout);
      _setGitHubHeaders(request);
      final response = await request.close().timeout(responseTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return response.statusCode == HttpStatus.notFound
            ? UpToDate(running)
            : UpdateCheckFailed(english
                ? 'GitHub returned ${response.statusCode}'
                : 'GitHub השיב ${response.statusCode}');
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(responseTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return UpdateCheckFailed(english
            ? 'GitHub returned an unexpected response'
            : 'התקבלה תשובה לא צפויה מ־GitHub');
      }

      return readLatestRelease(
        json: Map<String, dynamic>.from(decoded),
        running: running,
        platform: platform,
        english: english,
      );
    } on TimeoutException {
      return UpdateCheckFailed(english
          ? 'The update check timed out. Check your connection and try again'
          : 'בדיקת העדכונים ארכה זמן רב מדי. בדוק את החיבור ונסה שוב');
    } on HandshakeException {
      return UpdateCheckFailed(english
          ? 'The secure connection to GitHub could not be verified'
          : 'לא ניתן לאמת את החיבור המאובטח ל־GitHub');
    } on SocketException {
      return UpdateCheckFailed(english
          ? 'Could not connect to GitHub. Check your connection or network filtering'
          : 'לא ניתן להתחבר ל־GitHub. בדוק חיבור או סינון רשת');
    } on FormatException {
      return UpdateCheckFailed(english
          ? 'GitHub returned an invalid update response'
          : 'תשובת העדכון מ־GitHub אינה תקינה');
    } catch (_) {
      return UpdateCheckFailed(english
          ? 'Could not check for updates right now'
          : 'לא הצלחתי לבדוק עדכונים כרגע');
    } finally {
      client?.close(force: true);
    }
  }

  /// Downloads the artifact into the app's private temporary folder, then
  /// verifies both its byte count and GitHub-provided SHA-256 digest.
  Future<DownloadedUpdate> download(
    UpdateAvailable release, {
    void Function(UpdateDownloadProgress progress)? onProgress,
    bool english = false,
  }) async {
    final working = await Directory.systemTemp.createTemp('sofer-update-');
    final destination =
        File('${working.path}${Platform.pathSeparator}${release.asset.name}');
    HttpClient? client;
    IOSink? output;

    Future<void> closeOutputQuietly() async {
      try {
        await output?.close();
      } catch (_) {
        // The download error is the useful one; a second close error is not.
      }
      output = null;
    }

    try {
      client = _newClient();
      final request = await client
          .getUrl(release.asset.downloadUrl)
          .timeout(responseTimeout);
      _setGitHubHeaders(request, download: true);
      final response = await request.close().timeout(responseTimeout);
      if (response.redirects.any(
          (redirect) => redirect.location.scheme.toLowerCase() != 'https')) {
        throw UpdateException(english
            ? 'The update download was redirected to an insecure link. Installation was cancelled'
            : 'הורדת העדכון הופנתה לקישור שאינו מאובטח. ההתקנה בוטלה');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException(english
            ? 'Update download failed: GitHub returned ${response.statusCode}'
            : 'הורדת העדכון נכשלה: GitHub השיב ${response.statusCode}');
      }

      final destinationSink = destination.openWrite(mode: FileMode.writeOnly);
      output = destinationSink;
      var received = 0;
      onProgress?.call(UpdateDownloadProgress(0, release.asset.size));
      await for (final chunk in response.timeout(downloadIdleTimeout)) {
        destinationSink.add(chunk);
        received += chunk.length;
        if (received > release.asset.size) {
          throw UpdateException(english
              ? 'The update file is larger than the published file. Installation was cancelled'
              : 'קובץ העדכון גדול מהקובץ שפורסם. ההתקנה בוטלה');
        }
        onProgress?.call(UpdateDownloadProgress(received, release.asset.size));
      }
      await destinationSink.flush();
      await destinationSink.close();
      output = null;

      if (received != release.asset.size) {
        throw UpdateException(english
            ? 'The update download was interrupted ($received of ${release.asset.size} bytes)'
            : 'הורדת העדכון נקטעה ($received מתוך ${release.asset.size} בתים)');
      }

      final actualDigest = await sha256.bind(destination.openRead()).first;
      if (actualDigest.toString().toLowerCase() != release.asset.sha256Hex) {
        throw UpdateException(english
            ? 'Update file verification failed. The file was deleted and will not be installed'
            : 'אימות קובץ העדכון נכשל. הקובץ נמחק ולא יותקן');
      }

      return DownloadedUpdate(
        release: release,
        file: destination,
        workingDirectory: working,
      );
    } on UpdateException {
      await closeOutputQuietly();
      await _deleteWorkingDirectory(working);
      rethrow;
    } on TimeoutException catch (error) {
      await closeOutputQuietly();
      await _deleteWorkingDirectory(working);
      throw UpdateException(
          english
              ? 'The update download timed out. Check your connection and try again'
              : 'הורדת העדכון נעצרה זמן רב מדי. בדוק את החיבור ונסה שוב',
          error);
    } on HandshakeException catch (error) {
      await closeOutputQuietly();
      await _deleteWorkingDirectory(working);
      throw UpdateException(
          english
              ? 'The secure connection for downloading the update could not be verified'
              : 'לא ניתן לאמת את החיבור המאובטח להורדת העדכון',
          error);
    } on SocketException catch (error) {
      await closeOutputQuietly();
      await _deleteWorkingDirectory(working);
      throw UpdateException(
          english
              ? 'The connection was lost while downloading the update. Check your connection or network filtering'
              : 'החיבור נותק בזמן הורדת העדכון. בדוק חיבור או סינון רשת',
          error);
    } catch (error) {
      await closeOutputQuietly();
      await _deleteWorkingDirectory(working);
      throw UpdateException(
          english ? 'Update download failed' : 'הורדת העדכון נכשלה', error);
    } finally {
      await closeOutputQuietly();
      client?.close(force: true);
    }
  }

  static void _setGitHubHeaders(HttpClientRequest request,
      {bool download = false}) {
    request.headers.set(HttpHeaders.userAgentHeader, 'sofer-vmone/$appVersion');
    request.headers.set(
      HttpHeaders.acceptHeader,
      download ? 'application/octet-stream' : 'application/vnd.github+json',
    );
  }

  static Future<void> _deleteWorkingDirectory(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // A failed cleanup must not hide the actual update failure.
    }
  }
}
