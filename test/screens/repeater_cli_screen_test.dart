import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/repeater_cli_screen.dart';
import 'package:meshcore_open/services/repeater_command_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> sentFrames = [];

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
  }

  @override
  void trackRepeaterAck({
    required Contact contact,
    required PathSelection selection,
    required String text,
    required int timestampSeconds,
    int attempt = 0,
  }) {}

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrames.add(Uint8List.fromList(data));
  }

  void emitCliResponse(Contact repeater, String response) {
    _frames.add(
      Uint8List.fromList([
        respCodeContactMsgRecv,
        ...repeater.publicKey.take(6),
        0,
        txtTypeCliData,
        0,
        0,
        0,
        0,
        ...utf8.encode(response),
        0,
      ]),
    );
  }

  Future<void> close() => _frames.close();
}

Contact _makeRepeater() {
  return Contact(
    publicKey: Uint8List.fromList(
      List<int>.generate(pubKeySize, (index) => index + 1),
    ),
    name: 'Test Repeater',
    type: advTypeRepeater,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime(2026),
  );
}

Widget _buildTestApp(MeshCoreConnector connector, Contact repeater) {
  return ChangeNotifierProvider<MeshCoreConnector>.value(
    value: connector,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepeaterCliScreen(repeater: repeater, password: 'test-password'),
    ),
  );
}

bool _commandFieldHasFocus(WidgetTester tester) {
  return tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('command field regains focus after response and timeout', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_commandFieldHasFocus(tester), isTrue);

    await tester.enterText(find.byType(TextField), 'clock');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(connector.sentFrames, hasLength(1));
    expect(_commandFieldHasFocus(tester), isFalse);

    connector.emitCliResponse(repeater, 'ok');
    await tester.pump();
    await tester.pump();
    expect(find.text('ok'), findsOneWidget);
    expect(_commandFieldHasFocus(tester), isTrue);

    await tester.enterText(find.byType(TextField), 'version');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(connector.sentFrames, hasLength(2));
    expect(_commandFieldHasFocus(tester), isFalse);

    await tester.pump(RepeaterCommandService.defaultCommandTimeout);
    await tester.pump();
    expect(_commandFieldHasFocus(tester), isTrue);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });
}
