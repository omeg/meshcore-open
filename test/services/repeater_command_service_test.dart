import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/repeater_command_service.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final List<Uint8List> sentFrames = [];
  final List<_SendWaiter> _sendWaiters = [];
  int prepareCalls = 0;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    prepareCalls++;
    return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
  }

  @override
  void trackRepeaterAck({
    required Contact contact,
    required PathSelection selection,
    required String text,
    required int timestampSeconds,
    int attempt = 0,
  }) {}

  @override
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) {
    return 1;
  }

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrames.add(Uint8List.fromList(data));
    for (final waiter in List<_SendWaiter>.of(_sendWaiters)) {
      if (sentFrames.length >= waiter.count && !waiter.completer.isCompleted) {
        waiter.completer.complete();
        _sendWaiters.remove(waiter);
      }
    }
  }

  Future<void> waitForSendCount(int count) {
    if (sentFrames.length >= count) return Future<void>.value();
    final waiter = _SendWaiter(count);
    _sendWaiters.add(waiter);
    return waiter.completer.future;
  }
}

class _SendWaiter {
  final int count;
  final Completer<void> completer = Completer<void>();

  _SendWaiter(this.count);
}

Uint8List _makeKey() {
  return Uint8List.fromList(List<int>.generate(32, (i) => 0xA0 + i));
}

Contact _makeContact() {
  return Contact(
    publicKey: _makeKey(),
    name: 'Repeater',
    type: 1,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime(2026),
  );
}

String _cliTextFromFrame(Uint8List frame) {
  final bytes = <int>[];
  for (var i = 13; i < frame.length && frame[i] != 0; i++) {
    bytes.add(frame[i]);
  }
  return utf8.decode(bytes);
}

void main() {
  test(
    'sendCommandUntilSuccessful retries until a prefixed response arrives',
    () async {
      final connector = _FakeMeshCoreConnector();
      final service = RepeaterCommandService(connector);
      final contact = _makeContact();
      final attempts = <int>[];

      final future = service.sendCommandUntilSuccessful(
        contact,
        'clock',
        onAttempt: attempts.add,
      );

      await connector.waitForSendCount(1);
      await connector.waitForSendCount(2);

      final secondCommand = _cliTextFromFrame(connector.sentFrames[1]);
      final responsePrefix = secondCommand.substring(0, 3);
      service.handleResponse(contact, '${responsePrefix}ok');

      await expectLater(future, completion('ok'));
      expect(connector.sentFrames, hasLength(2));
      expect(attempts, [1, 2]);
      expect(connector.prepareCalls, 2);
    },
  );

  test(
    'sendCommandUntilSuccessful can cancel the active command wait',
    () async {
      final connector = _FakeMeshCoreConnector();
      final service = RepeaterCommandService(connector);
      final contact = _makeContact();
      final controller = RepeaterCommandRetryController();

      final future = service.sendCommandUntilSuccessful(
        contact,
        'clock',
        cancellation: controller,
      );

      await connector.waitForSendCount(1);
      controller.cancel();

      await expectLater(
        future,
        throwsA(isA<RepeaterCommandCancelledException>()),
      );
      expect(connector.sentFrames, hasLength(1));
    },
  );
}
