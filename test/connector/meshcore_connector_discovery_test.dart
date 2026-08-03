import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

Uint8List _buildNewAdvertFrame({
  required int publicKeyByte,
  required int advertisedTimestamp,
  required String name,
}) {
  final writer = BytesBuilder();
  writer.addByte(pushCodeNewAdvert);
  writer.add(Uint8List(pubKeySize)..fillRange(0, pubKeySize, publicKeyByte));
  writer.addByte(advTypeChat);
  writer.addByte(0); // flags
  writer.addByte(0); // zero-hop path
  writer.add(Uint8List(maxPathSize));

  final nameBytes = Uint8List(maxNameSize);
  final encodedName = name.codeUnits;
  nameBytes.setRange(0, encodedName.length, encodedName);
  writer.add(nameBytes);

  writer.add(
    Uint8List.fromList(<int>[
      advertisedTimestamp & 0xFF,
      (advertisedTimestamp >> 8) & 0xFF,
      (advertisedTimestamp >> 16) & 0xFF,
      (advertisedTimestamp >> 24) & 0xFF,
    ]),
  );
  writer.add(Uint8List(12)); // latitude, longitude, last modified
  return Uint8List.fromList(writer.toBytes());
}

Uint8List _buildRepeatAdvertFrame(int publicKeyByte) {
  final publicKey = Uint8List(pubKeySize)
    ..fillRange(0, pubKeySize, publicKeyByte);
  return Uint8List.fromList(<int>[pushCodeAdvert, ...publicKey]);
}

void main() {
  test('compact repeat advert updates discovery recency', () async {
    final connector = MeshCoreConnector();
    addTearDown(connector.dispose);

    connector.handleFrameForTesting(
      _buildNewAdvertFrame(
        publicKeyByte: 1,
        advertisedTimestamp: 2000000000,
        name: 'Nearby node',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    connector.handleFrameForTesting(
      _buildNewAdvertFrame(
        publicKeyByte: 2,
        advertisedTimestamp: 2100000000,
        name: 'Other node',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));

    connector.handleFrameForTesting(_buildRepeatAdvertFrame(1));

    final nearby = connector.discoveredContacts.singleWhere(
      (contact) => contact.name == 'Nearby node',
    );
    final other = connector.discoveredContacts.singleWhere(
      (contact) => contact.name == 'Other node',
    );

    expect(nearby.lastSeen.isAfter(other.lastSeen), isTrue);
  });
}
