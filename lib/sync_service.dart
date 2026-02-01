import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as googleapis;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'storage_service.dart';

class SyncService {
  // Singleton pattern
  static final SyncService instance = SyncService._internal();
  SyncService._internal();

  // Scopes
  static const _scopes = [
    'email',
    googleapis.DriveApi.driveFileScope,
  ];

  // Windows Config – מוגדר ב-build: --dart-define=GOOGLE_OAUTH_CLIENT_ID=... --dart-define=GOOGLE_OAUTH_CLIENT_SECRET=...
  static const String _windowsClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID', defaultValue: '');
  static const String _windowsClientSecret =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_SECRET', defaultValue: '');

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
    if (_windowsClientId.isEmpty || _windowsClientSecret.isEmpty) {
      debugPrint(
          'Windows OAuth: לא הוגדרו GOOGLE_OAUTH_CLIENT_ID / GOOGLE_OAUTH_CLIENT_SECRET. השתמש ב--dart-define בבנייה.');
      return;
    }
    final id = ClientId(_windowsClientId, _windowsClientSecret);
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

  Future<void> syncData() async {
    if (!isSignedIn) return;

    try {
      final client = await _getAuthClient();
      if (client == null) return;

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

      final mergedProjects = _mergeLists<Project>(
          localProjects, cloudProjects, (p) => p.id, (p) => p.lastUpdated);

      final mergedHistory = _mergeLists<WorkSession>(
          localHistory, cloudHistory, (s) => s.id, (s) => s.lastUpdated);

      final mergedExpenses = _mergeLists<Expense>(
          localExpenses, cloudExpenses, (e) => e.id, (e) => e.date);

      final cleanProjects = _purgeOldDeleted(
          mergedProjects, (p) => p.isDeleted, (p) => p.lastUpdated);
      final cleanHistory = _purgeOldDeleted(
          mergedHistory, (s) => s.isDeleted, (s) => s.lastUpdated);

      await _storage.saveProjects(cleanProjects);
      await _storage.saveHistory(cleanHistory);
      await _storage.saveExpenses(mergedExpenses);

      final Map<String, dynamic> exportData = {
        'projects': cleanProjects.map((p) => p.toJson()).toList(),
        'history': cleanHistory.map((h) => h.toJson()).toList(),
        'expenses': mergedExpenses.map((e) => e.toJson()).toList(),
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

      debugPrint("Sync completed successfully.");
    } catch (e) {
      debugPrint("Sync failed: $e");
    }
  }

  List<T> _mergeLists<T>(List<T> local, List<T> cloud, String Function(T) getId,
      DateTime Function(T) getLastUpdated) {
    final Map<String, T> map = {};

    for (var item in local) {
      map[getId(item)] = item;
    }

    for (var item in cloud) {
      final id = getId(item);
      if (map.containsKey(id)) {
        final localItem = map[id] as T;
        if (getLastUpdated(item).isAfter(getLastUpdated(localItem))) {
          map[id] = item;
        }
      } else {
        map[id] = item;
      }
    }

    return map.values.toList();
  }

  List<T> _purgeOldDeleted<T>(List<T> items, bool Function(T) getIsDeleted,
      DateTime Function(T) getLastUpdated) {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return items.where((item) {
      if (getIsDeleted(item)) {
        return getLastUpdated(item).isAfter(thirtyDaysAgo);
      }
      return true;
    }).toList();
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
