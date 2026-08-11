import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/companion_core_stats.dart';

Uint8List _coreStatsFrame() => Uint8List.fromList([
  respCodeStats,
  statsTypeCore,
  0x74, 0x0E, // battery: 3700 mV
  0x04, 0x93, 0x01, 0x00, // uptime: 103172 seconds
  0x02, 0x00, // error flags
  0x03, // queue length
]);

void main() {
  test('CompanionCoreStats.tryParse golden 11-byte core frame', () {
    final stats = CompanionCoreStats.tryParse(_coreStatsFrame());

    expect(stats, isNotNull);
    expect(stats!.batteryMillivolts, 3700);
    expect(stats.uptimeSecs, 103172);
    expect(stats.errorFlags, 2);
    expect(stats.queueLength, 3);
  });

  test('CompanionCoreStats.tryParse rejects non-core and short frames', () {
    expect(
      CompanionCoreStats.tryParse(
        Uint8List.fromList([
          respCodeStats,
          statsTypeRadio,
          ...List.filled(9, 0),
        ]),
      ),
      isNull,
    );
    expect(CompanionCoreStats.tryParse(Uint8List(10)), isNull);
  });

  test('MeshCoreConnector routes core stats responses', () {
    final connector = MeshCoreConnector();
    addTearDown(connector.dispose);

    connector.handleFrameForTesting(_coreStatsFrame());

    expect(connector.latestCoreStats?.uptimeSecs, 103172);
  });
}
