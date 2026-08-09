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
  });

  test('device info without a release string leaves it unavailable', () {
    final connector = MeshCoreConnector();

    connector.handleFrameForTesting(<int>[respCodeDeviceInfo, 7, 50, 8]);

    expect(connector.firmwareVerCode, 7);
    expect(connector.firmwareVersion, isNull);
  });
}
