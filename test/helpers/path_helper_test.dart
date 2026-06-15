import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/path_hash.dart';
import 'package:meshcore_open/helpers/path_helper.dart';
import 'package:meshcore_open/models/contact.dart';

Contact _contact({
  required List<int> prefix,
  required String name,
  required int type,
}) {
  final key = Uint8List(32);
  key.setRange(0, prefix.length, prefix);
  return Contact(
    publicKey: key,
    name: name,
    type: type,
    pathLength: 0,
    path: Uint8List(0),
    lastSeen: DateTime.now(),
  );
}

void main() {
  test('resolvePathNames ignores chat nodes and keeps repeater/room nodes', () {
    final contacts = [
      _contact(prefix: [0xF2], name: 'MunTui', type: advTypeChat),
      _contact(prefix: [0x7E], name: 'zrepeater', type: advTypeRepeater),
      _contact(prefix: [0xBA], name: 'USS Ronald Reagan', type: advTypeRoom),
    ];

    final resolved = PathHelper.resolvePathNames([0xF2, 0x7E, 0xBA], contacts);

    expect(resolved, equals('F2 → zrepeater → USS Ronald Reagan'));
  });

  test('formats and resolves multibyte repeater path chunks', () {
    final contacts = [
      _contact(
        prefix: [0xA6, 0xE7],
        name: 'first repeater',
        type: advTypeRepeater,
      ),
      _contact(prefix: [0xD1, 0x1E], name: 'room server', type: advTypeRoom),
      _contact(prefix: [0xD1, 0xFF], name: 'wrong node', type: advTypeRepeater),
    ];
    final path = [0xA6, 0xE7, 0xD1, 0x1E];

    expect(PathHelper.formatPathHex(path, 2), equals('A6E7,D11E'));
    expect(
      PathHelper.resolvePathNames(path, contacts, 2),
      equals('first repeater → room server'),
    );
  });

  test(
    'normalizes stale byte-count path lengths when path bytes are known',
    () {
      expect(normalizePathLengthWithBytes(14, 14, 2), equals(7));
      expect(normalizePathLengthWithBytes(6, 6, 2), equals(3));
      expect(normalizePathLengthWithBytes(0x45, 10, 2), equals(5));
      expect(normalizePathLengthWithBytes(0x45, 14, 2), equals(7));
      expect(normalizePathLengthWithBytes(9, 6, 2), equals(9));
      expect(normalizePathLengthWithBytes(9, 10, 2), equals(9));
      expect(normalizePathLengthWithBytes(-1, 6, 2), equals(-1));
    },
  );

  test('encodes zero-hop paths without hash-width bits', () {
    expect(encodePathLenForHashWidth(0, 1), equals(0));
    expect(encodePathLenForHashWidth(0, 2), equals(0));
    expect(encodePathLenForHashWidth(0, 3), equals(0));
  });

  test('validates raw packet path_len like firmware', () {
    expect(isValidPacketPathLen(0x3F), isTrue); // 63 one-byte hops
    expect(isValidPacketPathLen(0x40 | 32), isTrue); // 32 two-byte hops
    expect(isValidPacketPathLen(0x80 | 21), isTrue); // 21 three-byte hops
    expect(isValidPacketPathLen(0x40 | 33), isFalse);
    expect(isValidPacketPathLen(0x80 | 22), isFalse);
    expect(isValidPacketPathLen(0xC0), isFalse); // 4-byte mode reserved
    expect(isValidPacketPathLen(0xFF), isFalse); // reserved mode, not flood
  });

  test('decodes companion receive 0xFF as direct', () {
    expect(decodeReceivedPathHopCount(0xFF), equals(0));
    expect(decodeReceivedPathHopCount(0x40 | 5), equals(5));
  });

  test('trims dangling partial multibyte path chunks', () {
    expect(trimPathBytesToWidth([0x04, 0xF9, 0x84], 2), equals([0x04, 0xF9]));
    expect(trimPathBytesToWidth([0x04], 2), isEmpty);
  });

  test(
    'reverses multibyte paths by hop without swapping bytes inside hops',
    () {
      expect(
        reversePathByHop([0x2D, 0x71, 0xD1, 0xE5], 2),
        equals([0xD1, 0xE5, 0x2D, 0x71]),
      );
      expect(
        reversePathByHop([0x01, 0x02, 0x03, 0xA0, 0xB0, 0xC0], 3),
        equals([0xA0, 0xB0, 0xC0, 0x01, 0x02, 0x03]),
      );
    },
  );
}
