import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';

void main() {
  group('BLE scan display name', () {
    test('prefers the remembered SELF_INFO name', () {
      expect(
        MeshCoreConnector.selectBleDeviceDisplayName(
          rememberedName: 'Living Room Node',
          advertisedName: 'MeshCore-ab12',
          platformName: 'MeshCore-ab12',
        ),
        'Living Room Node',
      );
    });

    test('falls back to advertised then platform name', () {
      expect(
        MeshCoreConnector.selectBleDeviceDisplayName(
          advertisedName: 'Whisper-1234',
          platformName: 'MeshCore-ab12',
        ),
        'Whisper-1234',
      );
      expect(
        MeshCoreConnector.selectBleDeviceDisplayName(
          advertisedName: '',
          platformName: 'MeshCore-ab12',
        ),
        'MeshCore-ab12',
      );
    });
  });
}
