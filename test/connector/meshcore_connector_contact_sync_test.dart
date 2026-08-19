import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test('contact sync timeout restores the pre-sync contact snapshot', () async {
    final connector = _RecordingContactConnector();
    addTearDown(connector.dispose);
    final cached = _contact(1, 'Cached');
    final partial = _contact(2, 'Partial');
    connector.replaceContactsForTesting(<Contact>[cached]);

    await connector.getContacts();
    expect(connector.isLoadingContacts, isTrue);
    expect(connector.isContactPersistenceSuspended, isTrue);
    expect(connector.contacts, isEmpty);

    connector.replaceContactsForTesting(<Contact>[partial]);
    connector.triggerContactSyncWarningForTesting();
    expect(connector.isContactSyncSlow, isTrue);

    connector.triggerContactSyncTimeoutForTesting();

    expect(connector.isLoadingContacts, isFalse);
    expect(connector.isContactPersistenceSuspended, isFalse);
    expect(connector.isContactSyncSlow, isFalse);
    expect(connector.contactSyncFailed, isTrue);
    expect(connector.hasLoadedContacts, isTrue);
    expect(connector.contacts, <Contact>[cached]);
    expect(connector.knownContactKeys, <String>{cached.publicKeyHex});
  });

  test('completed contact sync commits the enumerated device list', () async {
    final connector = _RecordingContactConnector();
    addTearDown(connector.dispose);
    connector.replaceContactsForTesting(<Contact>[_contact(1, 'Cached')]);

    await connector.getContacts();
    connector.handleFrameForTesting(<int>[respCodeContactsStart, 0, 0, 0, 0]);
    connector.handleFrameForTesting(<int>[respCodeEndOfContacts, 0, 0, 0, 0]);

    expect(connector.isLoadingContacts, isFalse);
    expect(connector.contactSyncFailed, isFalse);
    expect(connector.hasLoadedContacts, isTrue);
    expect(connector.contacts, isEmpty);
    expect(connector.knownContactKeys, isEmpty);
  });

  test(
    'contact mutations are rejected while enumeration is incomplete',
    () async {
      final connector = _RecordingContactConnector();
      addTearDown(connector.dispose);

      await connector.getContacts();
      final imported = await connector.importDiscoveredContact(
        _contact(3, 'Manual'),
      );
      await connector.getContacts();

      expect(imported, isFalse);
      expect(connector.frames, hasLength(1));
      expect(connector.frames.single.first, cmdGetContacts);
    },
  );
}

Contact _contact(int seed, String name) {
  return Contact(
    publicKey: Uint8List.fromList(List<int>.filled(pubKeySize, seed)),
    name: name,
    type: advTypeChat,
    pathLength: 0,
    path: Uint8List(0),
    lastSeen: DateTime.fromMillisecondsSinceEpoch(seed * 1000),
  );
}

class _RecordingContactConnector extends MeshCoreConnector {
  final List<Uint8List> frames = <Uint8List>[];

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
  }
}
