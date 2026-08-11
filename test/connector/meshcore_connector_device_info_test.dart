import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  test('device info separates the firmware release from its protocol code', () {
    final connector = MeshCoreConnector();
    final frame = Uint8List(82);
    frame[0] = respCodeDeviceInfo;
    frame[1] = 13;
    frame[2] = 50;
    frame[3] = 8;
    final versionBytes = utf8.encode('v1.17.0a-omeg');
    frame.setRange(60, 60 + versionBytes.length, versionBytes);

    connector.handleFrameForTesting(frame);

    expect(connector.firmwareVerCode, 13);
    expect(connector.firmwareVersion, 'v1.17.0a-omeg');
    expect(connector.supportsPathHashMode, isTrue);
    expect(connector.pathHashByteWidth, 1);
  });

  test('device info without a release string leaves it unavailable', () {
    final connector = MeshCoreConnector();

    connector.handleFrameForTesting(<int>[respCodeDeviceInfo, 7, 50, 8]);

    expect(connector.firmwareVerCode, 7);
    expect(connector.firmwareVersion, isNull);
    expect(connector.supportsPathHashMode, isFalse);
  });

  test('device info reports the active multibyte path hash width', () {
    final connector = MeshCoreConnector();
    final frame = Uint8List(82);
    frame[0] = respCodeDeviceInfo;
    frame[1] = 10;
    frame[81] = 2;

    connector.handleFrameForTesting(frame);

    expect(connector.supportsPathHashMode, isTrue);
    expect(connector.pathHashByteWidth, 3);
  });

  test(
    'setting path hash mode waits for an ACK before updating width',
    () async {
      final connector = _RecordingPathHashConnector();
      addTearDown(connector.dispose);

      await connector.setPathHashMode(2);

      expect(connector.frames, <Uint8List>[
        Uint8List.fromList(<int>[cmdSetPathHashMode, 0, 2]),
      ]);
      expect(connector.waitForAck, isTrue);
      expect(connector.pathHashByteWidth, 3);
    },
  );

  test('rejected path hash mode does not update local width', () async {
    final connector = _RecordingPathHashConnector(
      sendError: Exception('rejected'),
    );
    addTearDown(connector.dispose);

    await expectLater(connector.setPathHashMode(1), throwsException);

    expect(connector.pathHashByteWidth, 1);
  });
}

class _RecordingPathHashConnector extends MeshCoreConnector {
  _RecordingPathHashConnector({this.sendError});

  final Object? sendError;
  final List<Uint8List> frames = <Uint8List>[];
  bool waitForAck = false;

  @override
  bool get isConnected => true;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    frames.add(Uint8List.fromList(data));
    waitForAck = waitForGenericAck;
    if (sendError case final error?) throw error;
  }
}
