import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';

void main() {
  group('DirectRepeater hash-prefix variants', () {
    test('matches the same repeater observed with a wider hash prefix', () {
      final repeater = DirectRepeater(hashPrefix: [0xA6], snr: 1.0);

      expect(repeater.matchesHashPrefixVariant([0xA6, 0xE7]), isTrue);
      expect(repeater.matchesHashPrefixVariant([0xA7, 0xE7]), isFalse);
    });

    test('updates to the longer hash prefix when available', () {
      final repeater = DirectRepeater(hashPrefix: [0xA6], snr: 1.0);

      repeater.update(2.0, observedPathHops: 3, hashPrefix: [0xA6, 0xE7]);

      expect(repeater.hashPrefix, equals([0xA6, 0xE7]));
      expect(repeater.snr, equals(2.0));
      expect(repeater.averageSnr, equals(1.5));
      expect(repeater.snrSampleCount, equals(2));
      expect(repeater.observedPathHops, equals(3));
    });

    test('does not downgrade to a shorter hash prefix', () {
      final repeater = DirectRepeater(hashPrefix: [0xA6, 0xE7], snr: 1.0);

      repeater.update(2.0, observedPathHops: 1, hashPrefix: [0xA6]);

      expect(repeater.hashPrefix, equals([0xA6, 0xE7]));
    });

    test('sorts by accumulated average SNR', () {
      final strong = DirectRepeater(hashPrefix: [0x01], snr: 1.0);
      strong.update(5.0, observedPathHops: 1);
      final weak = DirectRepeater(hashPrefix: [0x02], snr: 2.0);
      weak.update(2.0, observedPathHops: 1);
      final repeaters = [weak, strong]
        ..sort(DirectRepeater.compareByAverageSnr);

      expect(strong.averageSnr, equals(3.0));
      expect(weak.averageSnr, equals(2.0));
      expect(repeaters.first, same(strong));
    });
  });

  group('shouldIgnoreLateTcpConnectError', () {
    test('returns true for manual cancel during disconnecting state', () {
      final result = MeshCoreConnector.shouldIgnoreLateTcpConnectError(
        manualDisconnect: true,
        state: MeshCoreConnectionState.disconnecting,
        activeTransport: MeshCoreTransportType.bluetooth,
        tcpManagerConnected: false,
      );

      expect(result, isTrue);
    });

    test(
      'returns true for manual cancel after reaching disconnected state',
      () {
        final result = MeshCoreConnector.shouldIgnoreLateTcpConnectError(
          manualDisconnect: true,
          state: MeshCoreConnectionState.disconnected,
          activeTransport: MeshCoreTransportType.bluetooth,
          tcpManagerConnected: false,
        );

        expect(result, isTrue);
      },
    );

    test('returns false when not a manual disconnect', () {
      final result = MeshCoreConnector.shouldIgnoreLateTcpConnectError(
        manualDisconnect: false,
        state: MeshCoreConnectionState.disconnecting,
        activeTransport: MeshCoreTransportType.bluetooth,
        tcpManagerConnected: false,
      );

      expect(result, isFalse);
    });

    test('returns false for connected state handshake failures', () {
      final result = MeshCoreConnector.shouldIgnoreLateTcpConnectError(
        manualDisconnect: true,
        state: MeshCoreConnectionState.connected,
        activeTransport: MeshCoreTransportType.tcp,
        tcpManagerConnected: true,
      );

      expect(result, isFalse);
    });

    test('returns false when TCP is still active while disconnecting', () {
      final result = MeshCoreConnector.shouldIgnoreLateTcpConnectError(
        manualDisconnect: true,
        state: MeshCoreConnectionState.disconnecting,
        activeTransport: MeshCoreTransportType.tcp,
        tcpManagerConnected: true,
      );

      expect(result, isFalse);
    });
  });

  group('shouldResetStateAfterTcpConnectAbort', () {
    test('returns true when TCP connect is still in connecting state', () {
      final result = MeshCoreConnector.shouldResetStateAfterTcpConnectAbort(
        state: MeshCoreConnectionState.connecting,
        activeTransport: MeshCoreTransportType.tcp,
      );

      expect(result, isTrue);
    });

    test('returns false when state is already disconnected', () {
      final result = MeshCoreConnector.shouldResetStateAfterTcpConnectAbort(
        state: MeshCoreConnectionState.disconnected,
        activeTransport: MeshCoreTransportType.tcp,
      );

      expect(result, isFalse);
    });

    test('returns false when transport switched away from TCP', () {
      final result = MeshCoreConnector.shouldResetStateAfterTcpConnectAbort(
        state: MeshCoreConnectionState.connecting,
        activeTransport: MeshCoreTransportType.bluetooth,
      );

      expect(result, isFalse);
    });
  });
}
