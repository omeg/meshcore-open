import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/repeater_settings_session_snapshot.dart';

void main() {
  test('remembers and clears a remote-node authentication session', () {
    final connector = MeshCoreConnector();
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Repeater',
      type: advTypeRepeater,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime(2026),
    );

    final session = connector.rememberRemoteNodeAuthentication(
      contact,
      password: 'secret',
      isAdmin: true,
    );

    expect(connector.isRemoteNodeAuthenticated(contact), isTrue);
    expect(connector.remoteNodeAuthSession(contact), same(session));
    expect(session.password, 'secret');
    expect(session.isAdmin, isTrue);

    connector.rememberRepeaterSettingsSessionSnapshot(
      contact,
      RepeaterSettingsSessionSnapshot(
        valuesByKey: const {'name': 'Fetched Repeater'},
      ),
    );
    expect(
      connector.repeaterSettingsSessionSnapshot(contact)?.valuesByKey['name'],
      'Fetched Repeater',
    );

    connector.clearRemoteNodeAuthentication(contact);

    expect(connector.isRemoteNodeAuthenticated(contact), isFalse);
    expect(connector.remoteNodeAuthSession(contact), isNull);
    expect(connector.repeaterSettingsSessionSnapshot(contact), isNull);
    connector.dispose();
  });
}
