import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/ble_device_name_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test('persists learned BLE device names by device ID', () async {
    final store = BleDeviceNameStore();

    await store.saveNames(<String, String>{
      'AA:BB:CC:DD:EE:FF': 'My Companion',
    });

    expect(store.loadNames(), <String, String>{
      'AA:BB:CC:DD:EE:FF': 'My Companion',
    });
  });

  test('ignores malformed and empty stored names', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ble_device_names': '{"known":" Companion ","empty":" "}',
    });
    PrefsManager.reset();
    await PrefsManager.initialize();

    expect(BleDeviceNameStore().loadNames(), <String, String>{
      'known': 'Companion',
    });
  });
}
