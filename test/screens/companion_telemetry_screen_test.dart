import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/cayenne_lpp.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/screens/companion_telemetry_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}

  void emit(Uint8List frame) => _frames.add(frame);

  Future<void> close() => _frames.close();
}

Widget _buildTestApp(MeshCoreConnector connector) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: MeshTheme.dark(),
      home: const CompanionTelemetryScreen(),
    ),
  );
}

List<int> _int16BigEndian(int value) {
  return [(value >> 8) & 0xff, value & 0xff];
}

Uint8List _channelThreeTelemetryFrame() {
  return Uint8List.fromList([
    pushCodeTelemetryResponse,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    3,
    CayenneLpp.lppAccelerometer,
    ..._int16BigEndian(60),
    ..._int16BigEndian(-1040),
    ..._int16BigEndian(40),
    3,
    CayenneLpp.lppGyrometer,
    ..._int16BigEndian(42),
    ..._int16BigEndian(-9),
    ..._int16BigEndian(77),
  ]);
}

void main() {
  testWidgets('channel columns leave long telemetry values on one line', (
    tester,
  ) async {
    // Widget tests use the deliberately wide Ahem test font. This width keeps
    // the row at the same fit boundary while still failing with a 50/50 split.
    tester.view.physicalSize = const Size(620, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final connector = _FakeMeshCoreConnector();
    addTearDown(connector.close);

    await tester.pumpWidget(_buildTestApp(connector));
    connector.emit(_channelThreeTelemetryFrame());
    await tester.pump();

    const value = 'X: 0.06, Y: -1.04, Z: 0.04';
    final valueFinder = find.text(value);
    expect(valueFinder, findsOneWidget);

    final paragraph = tester.renderObject<RenderParagraph>(valueFinder);
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: value.length),
    );
    expect(boxes, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
