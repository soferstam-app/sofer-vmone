import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:sofer_vmone/storage_service.dart';

@JS('soferAccountRequest')
external JSFunction? get _accountRequest;

@JS('soferAccountRequest')
external JSPromise<JSString> _request(JSString method, JSString? body);

@JS('soferAccountLoadFailed')
external void _showLoadFailure();

@JS('soferAccountSignOut')
external JSPromise<JSAny?> _signOut();

@JS('soferAccountLinkPhone')
external JSFunction? get _linkPhone;

@JS('soferAccountLinkPhone')
external void _openPhoneLink();

@JS('soferAccountPassword')
external JSFunction? get _accountPassword;

@JS('soferAccountPassword')
external void _openAccountPassword();

class AccountStore extends MemoryStore {
  AccountStore._(this._revision, Map<String, Object> values)
      : _committed = MemoryStore(values),
        super({});

  static bool get enabled => _accountRequest != null;
  static void Function()? get linkPhone =>
      _linkPhone == null ? null : () => _openPhoneLink();
  static void Function()? get managePassword =>
      _accountPassword == null ? null : () => _openAccountPassword();

  static Future<void> signOut() async {
    await _signOut().toDart;
  }

  static Future<AccountStore> load() async {
    try {
      final result = await _call('GET');
      return AccountStore._(result['revision'] as int,
          Map<String, Object>.from(result['values'] as Map));
    } catch (_) {
      _showLoadFailure();
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> _call(String method,
      [Map<String, Object>? payload]) async {
    final raw = await _request(
            method.toJS, payload == null ? null : jsonEncode(payload).toJS)
        .toDart;
    final result = jsonDecode(raw.toDart) as Map<String, dynamic>;
    if (result['status'] != 200) {
      throw StateError('Account storage request failed (${result['status']})');
    }
    return result['body'] as Map<String, dynamic>;
  }

  int _revision;
  MemoryStore _committed;
  Future<void> _queue = Future.value();

  @override
  Map<String, Object> get snapshot => _committed.snapshot;
  @override
  String? getString(String key) => _committed.getString(key);
  @override
  bool? getBool(String key) => _committed.getBool(key);
  @override
  int? getInt(String key) => _committed.getInt(key);

  @override
  Future<void> setString(String key, String value) =>
      transaction((store) => store.setString(key, value));
  @override
  Future<void> setBool(String key, bool value) =>
      transaction((store) => store.setBool(key, value));
  @override
  Future<void> setInt(String key, int value) =>
      transaction((store) => store.setInt(key, value));
  @override
  Future<void> remove(String key) => transaction((store) => store.remove(key));

  @override
  Future<void> transaction(Future<void> Function(KeyValueStore) write) {
    final operation = _queue.then((_) async {
      final previous = snapshot;
      final staged = MemoryStore(previous);
      await write(staged);
      final values = staged.snapshot;
      if (mapEquals(previous, values)) return;
      final result =
          await _call('PUT', {'revision': _revision, 'values': values});
      _revision = result['revision'] as int;
      _committed = staged;
    });
    _queue = operation.catchError((Object _) {});
    return operation;
  }
}
