import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_uuids.dart';

void main() {
  group('MeshCore device names', () {
    test('accepts each known firmware prefix', () {
      for (final prefix in MeshCoreUuids.deviceNamePrefixes) {
        expect(MeshCoreUuids.isKnownDeviceName('${prefix}device'), isTrue);
      }
    });

    test('checks both platform and advertised names', () {
      expect(
        MeshCoreUuids.matchesDeviceNames(
          platformName: 'MeshCore-1234',
          advertisedName: '',
        ),
        isTrue,
      );
      expect(
        MeshCoreUuids.matchesDeviceNames(
          platformName: 'Cached desktop name',
          advertisedName: 'Whisper-abcd',
        ),
        isTrue,
      );
    });

    test('rejects unrelated and empty names', () {
      expect(
        MeshCoreUuids.matchesDeviceNames(
          platformName: 'Wireless headphones',
          advertisedName: 'Audio Device',
        ),
        isFalse,
      );
      expect(
        MeshCoreUuids.matchesDeviceNames(platformName: '', advertisedName: ''),
        isFalse,
      );
    });
  });
}
