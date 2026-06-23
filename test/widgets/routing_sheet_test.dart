import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/widgets/routing_sheet.dart';

Contact _contact({int? pathOverride}) {
  return Contact(
    publicKey: Uint8List.fromList(List.generate(32, (index) => index + 1)),
    name: 'Node',
    type: advTypeChat,
    pathLength: 2,
    path: Uint8List.fromList([0x11, 0x22]),
    pathOverride: pathOverride,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

void main() {
  test('routing mode distinguishes forced direct from manual paths', () {
    expect(contactRoutingMode(_contact()), ContactRoutingMode.auto);
    expect(
      contactRoutingMode(_contact(pathOverride: -1)),
      ContactRoutingMode.flood,
    );
    expect(
      contactRoutingMode(_contact(pathOverride: 0)),
      ContactRoutingMode.direct,
    );
    expect(
      contactRoutingMode(_contact(pathOverride: 2)),
      ContactRoutingMode.manual,
    );
  });
}
