import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  test('NOT_FOUND advances an empty channel slot without waiting', () async {
    final connector = MeshCoreConnector();
    addTearDown(connector.dispose);
    connector.startChannelSyncForTesting();

    connector.handleFrameForTesting(<int>[respCodeErr, errCodeNotFound]);
    await Future<void>.delayed(Duration.zero);

    expect(connector.isSyncingChannels, isFalse);
    expect(connector.hasLoadedChannels, isTrue);
  });

  test(
    'setChannel waits for firmware acknowledgement before updating',
    () async {
      final connector = _RecordingChannelConnector();
      addTearDown(() {
        connector.connected = false;
        connector.dispose();
      });
      final psk = Channel.parsePskHex(Channel.publicChannelPsk);

      await connector.setChannel(0, 'Public', psk);

      expect(connector.frames, hasLength(1));
      expect(connector.frames.single.first, cmdSetChannel);
      expect(connector.waitForAck, <bool>[true]);
      expect(connector.channels, hasLength(1));
      expect(connector.channels.single.index, 0);
      expect(connector.channels.single.name, 'Public');
      expect(connector.channels.single.psk, psk);
    },
  );

  test(
    'setChannel does not update local state when firmware rejects it',
    () async {
      final connector = _RecordingChannelConnector(
        sendError: Exception('rejected'),
      );
      addTearDown(() {
        connector.connected = false;
        connector.dispose();
      });

      await expectLater(
        connector.setChannel(
          0,
          'Public',
          Channel.parsePskHex(Channel.publicChannelPsk),
        ),
        throwsException,
      );

      expect(connector.channels, isEmpty);
    },
  );
}

class _RecordingChannelConnector extends MeshCoreConnector {
  _RecordingChannelConnector({this.sendError});

  final Object? sendError;
  final List<Uint8List> frames = <Uint8List>[];
  final List<bool> waitForAck = <bool>[];
  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    frames.add(Uint8List.fromList(data));
    waitForAck.add(waitForGenericAck);
    if (sendError case final error?) throw error;
  }
}
