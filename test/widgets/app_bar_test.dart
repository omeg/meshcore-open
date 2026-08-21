import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:meshcore_open/widgets/battery_indicator.dart';
import 'package:meshcore_open/widgets/radio_stats_entry.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector({required this.connected, this.radioStats = false});

  final bool connected;
  final bool radioStats;

  @override
  bool get isConnected => connected;

  @override
  int? get batteryMillivolts => 3900;

  @override
  int? get batteryPercent => 65;

  @override
  int? get currentSf => 9;

  @override
  bool get supportsCompanionRadioStats => radioStats;
}

Widget _testApp(
  MeshCoreConnector connector, {
  bool showRadioStatsIndicator = true,
}) {
  return ChangeNotifierProvider<MeshCoreConnector>.value(
    value: connector,
    child: MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: AppBarTitle.custom(
            const Text('Custom title'),
            showRadioStatsIndicator: showRadioStatsIndicator,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('custom app-bar titles include battery and SNR when connected', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_FakeMeshCoreConnector(connected: true)));

    expect(find.text('Custom title'), findsOneWidget);
    expect(find.byType(BatteryIndicator), findsOneWidget);
    expect(find.byType(SNRIndicator), findsOneWidget);
  });

  testWidgets('app-bar indicators stay hidden while disconnected', (
    tester,
  ) async {
    await tester.pumpWidget(_testApp(_FakeMeshCoreConnector(connected: false)));

    expect(find.byType(BatteryIndicator), findsNothing);
    expect(find.byType(SNRIndicator), findsNothing);
  });

  testWidgets('radio stats can be hidden without removing other indicators', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        _FakeMeshCoreConnector(connected: true, radioStats: true),
        showRadioStatsIndicator: false,
      ),
    );

    expect(find.byType(BatteryIndicator), findsOneWidget);
    expect(find.byType(SNRIndicator), findsOneWidget);
    expect(find.byType(RadioStatsIconButton), findsNothing);
  });
}
