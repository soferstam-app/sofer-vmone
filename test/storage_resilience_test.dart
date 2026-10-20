import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sofer_vmone/storage_service.dart';

void main() {
  tearDown(() => StorageService.demoStore = null);

  test('a malformed notification time falls back safely', () async {
    StorageService.demoStore = MemoryStore({'notification_time': 'not-a-time'});
    expect(await StorageService().getNotificationTime(),
        const TimeOfDay(hour: 20, minute: 0));
  });

  test('an out-of-range notification time falls back safely', () async {
    StorageService.demoStore = MemoryStore({'notification_time': '24:99'});
    expect(await StorageService().getNotificationTime(),
        const TimeOfDay(hour: 20, minute: 0));
  });
}
