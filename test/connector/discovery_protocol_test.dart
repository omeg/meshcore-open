import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  test('builds full-key zero-hop repeater discovery request', () {
    final payload = buildDiscoveryRequestPayload(0x78563412);

    expect(
      payload,
      orderedEquals(<int>[
        0x80,
        1 << advTypeRepeater,
        0x12,
        0x34,
        0x56,
        0x78,
        0,
        0,
        0,
        0,
      ]),
    );
    expect(
      buildSendControlDataFrame(payload).first,
      equals(cmdSendControlData),
    );
  });

  test('parses repeater discovery response with radio strength', () {
    final publicKey = List<int>.generate(pubKeySize, (index) => index);
    final frame = Uint8List.fromList(<int>[
      pushCodeControlData,
      28, // companion received SNR: 7.0 dB
      0xB6, // companion received RSSI: -74 dBm
      0, // zero-hop
      0x90 | advTypeRepeater,
      20, // repeater received request SNR: 5.0 dB
      0x12,
      0x34,
      0x56,
      0x78,
      ...publicKey,
    ]);

    final response = parseDiscoveryResponseFrame(frame);

    expect(response, isNotNull);
    expect(response!.tag, 0x78563412);
    expect(response.nodeType, advTypeRepeater);
    expect(response.rssi, -74);
    expect(response.snr, 7.0);
    expect(response.responderSnr, 5.0);
    expect(response.pathLength, 0);
    expect(response.publicKey, orderedEquals(publicKey));
  });

  test('ignores unrelated and malformed control frames', () {
    expect(
      parseDiscoveryResponseFrame(Uint8List.fromList(<int>[respCodeOk])),
      isNull,
    );
    expect(
      parseDiscoveryResponseFrame(
        Uint8List.fromList(<int>[
          pushCodeControlData,
          0,
          0,
          0,
          controlSubtypeDiscoverResp << 4,
        ]),
      ),
      isNull,
    );
  });
}
