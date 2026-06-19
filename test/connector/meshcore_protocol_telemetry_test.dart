import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  test('builds a four-byte companion self-telemetry request', () {
    expect(buildSendTelemetryReq(null), [cmdSendTelemetryReq, 0, 0, 0]);
  });
}
