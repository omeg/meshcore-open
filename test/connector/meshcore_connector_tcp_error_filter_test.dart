import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

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

    test('adds sample counts when absorbing a narrower hash variant', () {
      final narrow = DirectRepeater(hashPrefix: [0xA6], snr: 1.0)
        ..update(3.0, observedPathHops: 1);
      final wide = DirectRepeater(hashPrefix: [0xA6, 0xE7], snr: 5.0)
        ..update(7.0, observedPathHops: 2)
        ..update(9.0, observedPathHops: 2);

      wide.absorb(narrow);

      expect(wide.hashPrefix, equals([0xA6, 0xE7]));
      expect(wide.snrSampleCount, equals(5));
      expect(wide.averageSnr, equals(5.0));
    });

    test('sorts by accumulated packet count before average SNR', () {
      final frequent = DirectRepeater(hashPrefix: [0x01], snr: 1.0);
      frequent.update(1.0, observedPathHops: 1);
      frequent.update(1.0, observedPathHops: 1);
      final strong = DirectRepeater(hashPrefix: [0x02], snr: 9.0);
      strong.update(9.0, observedPathHops: 1);
      final repeaters = [strong, frequent]
        ..sort(DirectRepeater.compareByPacketCount);

      expect(frequent.snrSampleCount, equals(3));
      expect(strong.averageSnr, greaterThan(frequent.averageSnr));
      expect(repeaters.first, same(frequent));
    });

    test('tracks packet paths using their encoded hash width', () {
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 64,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeGRPTXT,
        ),
        isTrue,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 4,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeGRPTXT,
        ),
        isTrue,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 3,
          pathByteLength: 6,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeGRPTXT,
        ),
        isTrue,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 3,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeGRPTXT,
        ),
        isFalse,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 2,
          payloadByteLength: 0,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeGRPTXT,
        ),
        isFalse,
      );
    });

    test('ignores direct and telemetry request/response packet paths', () {
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 2,
          payloadByteLength: 1,
          routeType: 2, // ROUTE_TYPE_DIRECT
          payloadType: payloadTypeGRPTXT,
        ),
        isFalse,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 2,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeREQ,
        ),
        isFalse,
      );
      expect(
        DirectRepeater.shouldTrackPacketPath(
          packetHashWidth: 2,
          pathByteLength: 2,
          payloadByteLength: 1,
          routeType: 1, // ROUTE_TYPE_FLOOD
          payloadType: payloadTypeRESPONSE,
        ),
        isFalse,
      );
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
