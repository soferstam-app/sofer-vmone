import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as googleapis;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'logic/merge_service.dart';
import 'models.dart';
import 'storage_service.dart';

/// Outcome of a [SyncService.syncData] call, so callers can report to the user
/// instead of failing silently.
enum SyncStatus { success, notSignedIn, failed }

class SyncService {
  // Singleton pattern
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  /// Guards against overlapping sync cycles. syncData() is called from many UI
  /// paths; two concurrent cycles could each upload a merge result computed
  /// from stale data and clobber the other.
  bool _isSyncing = false;

  /// Set when a sync is requested while another is already running, so the
  /// latest local changes still reach Drive once the current cycle ends.
  bool _resyncQueued = false;

  DateTime? lastSyncTime;
  String? lastSyncError;

  // Scopes
  static const _scopes = [
    'email',
    googleapis.DriveApi.driveFileScope,
  ];

  // Windows Config – קורא מ-oauth_credentials.json (בתיקיית הפרויקט או ליד ה-exe) או מ--dart-define
  static (String, String)? _cachedWindowsCredentials;
  static String get _windowsClientId => _loadWindowsCredentials().$1;
  static String get _windowsClientSecret => _loadWindowsCredentials().$2;

  static (String, String) _loadWindowsCredentials() {
    final cached = _cachedWindowsCredentials;
    if (cached != null) return cached;
    final result = _loadWindowsCredentialsImpl();
    _cachedWindowsCredentials = result;
    return result;
  }

  static (String, String) _loadWindowsCredentialsImpl() {
    final String fromEnvId =
        String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID', defaultValue: '');
    final String fromEnvSecret =
        String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET', defaultValue: '');
    if (fromEnvId.isNotEmpty && fromEnvSecret.isNotEmpty) {
      return (fromEnvId, fromEnvSecret);
    }
    final file = _oauthCredentialsFile();
    if (file == null || !file.existsSync()) return (fromEnvId, fromEnvSecret);
    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>?;
      if (json == null) return (fromEnvId, fromEnvSecret);
      final idRaw = json['GOOGLE_OAUTH_CLIENT_ID'];
      final secretRaw = json['GOOGLE_OAUTH_CLIENT_SECRET'];
      final String id = (idRaw is String ? idRaw.trim() : '');
      final String secret = (secretRaw is String ? secretRaw.trim() : '');
      if (id.isNotEmpty && secret.isNotEmpty) return (id, secret);
    } catch (_) {}
    return (fromEnvId, fromEnvSecret);
  }

  static File? _oauthCredentialsFile() {
    const name = 'oauth_credentials.json';
    final current = File(name);
    if (current.existsSync()) return current;
    try {
      final exePath = Platform.resolvedExecutable;
      final dir = File(exePath).parent;
      final nextToExe = File('${dir.path}/$name');
      if (nextToExe.existsSync()) return nextToExe;
    } catch (_) {}
    return null;
  }

  // State
  GoogleSignInAccount? _currentUser;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);
  http.Client? _authenticatedClient;
  final StorageService _storage = StorageService();

  bool get isSignedIn => _currentUser != null || _authenticatedClient != null;
  String get userEmail => _currentUser?.email ?? "Windows User";

  // --- Auth Methods ---

  Future<void> init() async {
    _googleSignIn.onCurrentUserChanged.listen((account) {
      _currentUser = account;
    });

    if (Platform.isAndroid) {
      await _googleSignIn.signInSilently();
    }
  }

  Future<void> signIn() async {
    if (Platform.isWindows) {
      await _signInWindows();
    } else {
      await _googleSignIn.signIn();
    }
  }

  Future<void> signOut() async {
    if (Platform.isWindows) {
      _authenticatedClient = null;
    } else {
      await _googleSignIn.disconnect();
    }
  }

  Future<void> _signInWindows() async {
    final clientId = _windowsClientId;
    final clientSecret = _windowsClientSecret;
    if (clientId.isEmpty || clientSecret.isEmpty) {
      debugPrint(
          'Windows OAuth: לא נמצאו מפתחות. שים oauth_credentials.json בתיקיית הפרויקט או ליד ה-exe, או השתמש ב--dart-define בבנייה.');
      return;
    }
    final id = ClientId(clientId, clientSecret);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirectUrl = 'http://localhost:${server.port}';

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'response_type': 'code',
      'client_id': id.identifier,
      'redirect_uri': redirectUrl,
      'scope': _scopes.join(' '),
      'access_type': 'offline',
    });

    await launchUrl(authUrl);

    final request = await server.first;
    final code = request.uri.queryParameters['code'];

    request.response
      ..statusCode = 200
      ..headers.set('content-type', 'text/html; charset=UTF-8')
      ..write(
          '<html><body><h1>ההתחברות הצליחה!</h1><script>window.close();</script></body></html>');
    await request.response.close();
    await server.close();

    if (code != null) {
      final client = http.Client();
      final credentials = await obtainAccessCredentialsViaCodeExchange(
        client,
        id,
        code,
        redirectUrl: redirectUrl,
      );
      _authenticatedClient = autoRefreshingClient(id, credentials, client);
    }
  }

  Future<http.Client?> _getAuthClient() async {
    if (Platform.isWindows) return _authenticatedClient;
    if (_currentUser != null) {
      final authHeaders = await _currentUser!.authHeaders;
      return _GoogleAuthClient(authHeaders);
    }
    return null;
  }

  // --- Sync Logic ---

  Future<SyncStatus> syncData() async {
    if (!isSignedIn) return SyncStatus.notSignedIn;

    if (_isSyncing) {
      // Coalesce: let the in-flight cycle finish, then run once more so this
      // request's local changes are not lost.
      _resyncQueued = true;
      return SyncStatus.success;
    }
    _isSyncing = true;

    try {
      final client = await _getAuthClient();
      if (client == null) return SyncStatus.notSignedIn;

      final driveApi = googleapis.DriveApi(client);
      const fileName = 'sofer_vmone_backup.json';

      List<Project> localProjects = await _storage.loadProjects();
      List<WorkSession> localHistory = await _storage.loadHistory();
      List<Expense> localExpenses = await _storage.loadExpenses();

      final fileList = await driveApi.files.list(
        q: "name = '$fileName' and trashed = false",
        $fields: 'files(id, modifiedTime)',
      );

      List<Project> cloudProjects = [];
      List<WorkSession> cloudHistory = [];
      List<Expense> cloudExpenses = [];
      String? fileId;

      if (fileList.files != null && fileList.files!.isNotEmpty) {
        fileId = fileList.files!.first.id;
        final media = await driveApi.files.get(
          fileId!,
          downloadOptions: googleapis.DownloadOptions.fullMedia,
        ) as googleapis.Media;

        final List<int> dataStore = [];
        await media.stream.forEach((element) => dataStore.addAll(element));

        if (dataStore.isNotEmpty) {
          final jsonString = utf8.decode(dataStore);
          final jsonMap = jsonDecode(jsonString);

          if (jsonMap['projects'] != null) {
            cloudProjects = (jsonMap['projects'] as List)
                .map((e) => Project.fromJson(e))
                .toList();
          }
          if (jsonMap['history'] != null) {
            cloudHistory = (jsonMap['history'] as List)
                .map((e) => WorkSession.fromJson(e))
                .toList();
          }
          if (jsonMap['expenses'] != null) {
            cloudExpenses = (jsonMap['expenses'] as List)
                .map((e) => Expense.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          }
        }
      }

      // Same merge rules the file import uses — see MergeService.
      final outcome = MergeService.mergeBackup(
        localProjects: localProjects,
        localHistory: localHistory,
        localExpenses: localExpenses,
        incomingProjects: cloudProjects,
        incomingHistory: cloudHistory,
        incomingExpenses: cloudExpenses,
      );
      final cleanProjects = outcome.projects;
      final cleanHistory = outcome.history;
      final cleanExpenses = outcome.expenses;

      await _storage.saveProjects(cleanProjects);
      await _storage.saveHistory(cleanHistory);
      await _storage.saveExpenses(cleanExpenses);

      final Map<String, dynamic> exportData = {
        'projects': cleanProjects.map((p) => p.toJson()).toList(),
        'history': cleanHistory.map((h) => h.toJson()).toList(),
        'expenses': cleanExpenses.map((e) => e.toJson()).toList(),
        'lastSync': DateTime.now().toIso8601String(),
      };

      final jsonContent = jsonEncode(exportData);
      final uploadMedia = googleapis.Media(
        Stream.value(utf8.encode(jsonContent)),
        utf8.encode(jsonContent).length,
      );

      final driveFile = googleapis.File()
        ..name = fileName
        ..description = 'Sofer vMone Data'
        ..mimeType = 'application/json';

      if (fileId != null) {
        await driveApi.files
            .update(driveFile, fileId, uploadMedia: uploadMedia);
      } else {
        await driveApi.files.create(driveFile, uploadMedia: uploadMedia);
      }

      lastSyncTime = DateTime.now();
      lastSyncError = null;
      debugPrint("Sync completed successfully.");
      return SyncStatus.success;
    } catch (e) {
      lastSyncError = e.toString();
      debugPrint("Sync failed: $e");
      return SyncStatus.failed;
    } finally {
      _isSyncing = false;
      if (_resyncQueued) {
        _resyncQueued = false;
        await syncData();
      }
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.addAll(_headers);

    if (request.method == 'GET' &&
        request.url.host.contains('googleapis.com')) {
      request.followRedirects = false;
      var response = await _client.send(request);

      if (response.statusCode >= 300 &&
          response.statusCode < 400 &&
          response.headers.containsKey('location')) {
        final location = response.headers['location']!;
        final newRequest = http.Request(request.method, Uri.parse(location));
        newRequest.headers.addAll(request.headers);
        newRequest.followRedirects = false;
        return _client.send(newRequest);
      }
      return response;
    }

    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}
