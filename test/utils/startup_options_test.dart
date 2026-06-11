import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/utils/startup_options.dart';

void main() {
  test('parses --ble-address value', () {
    final options = StartupOptions.parse([
      '--ble-address',
      'cf:de:b5:89:55:f5',
    ]);

    expect(options.bleAddress, 'CF:DE:B5:89:55:F5');
  });

  test('parses --ble-address=value', () {
    final options = StartupOptions.parse(['--ble-address=AA:BB:CC:DD:EE:FF']);

    expect(options.bleAddress, 'AA:BB:CC:DD:EE:FF');
  });

  test('rejects invalid BLE address', () {
    expect(
      () => StartupOptions.parse(['--ble-address', 'not-a-mac']),
      throwsFormatException,
    );
  });
}
