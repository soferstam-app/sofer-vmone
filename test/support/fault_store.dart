import 'dart:async';

import 'package:sofer_vmone/storage_service.dart';

/// Faults target durable operations, not reads or widgets' memory state.
class FaultStore extends MemoryStore {
  FaultStore(super.initial);
  String? failKey;
  Set<int> failOperations = {};
  int operations = 0;
  String? blockedKey;
  Completer<void>? blocked;
  Completer<void>? release;

  void arm(String key) => failKey = key;
  void failAt(Set<int> steps) {
    operations = 0;
    failOperations = {...steps};
  }

  Future<void> _before(String key) async {
    operations++;
    if (key == failKey || failOperations.remove(operations)) {
      failKey = null;
      throw StateError('Injected failure: $key');
    }
    if (key == blockedKey) {
      blockedKey = null;
      blocked!.complete();
      await release!.future;
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    await _before(key);
    await super.setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _before(key);
    await super.setBool(key, value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await _before(key);
    await super.setInt(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _before(key);
    await super.remove(key);
  }
}
