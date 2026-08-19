import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/repeater_settings_screen.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  void respondToLastCommand(Contact repeater, String response) {
    final command = _cliTextFromFrame(sentFrames.last);
    final prefix = command.substring(0, 3);
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
        ...utf8.encode('$prefix$response'),
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
    name: 'Advertised Repeater Name',
    type: advTypeRepeater,
    latitude: 51.1,
    longitude: 17.0,
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
      home: RepeaterSettingsScreen(
        repeater: repeater,
        password: 'test-password',
      ),
    ),
  );
}

String _cliTextFromFrame(Uint8List frame) {
  final bytes = <int>[];
  for (var i = 13; i < frame.length && frame[i] != 0; i++) {
    bytes.add(frame[i]);
  }
  return utf8.decode(bytes);
}

Finder _textFieldWithLabel(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
    description: 'TextField with label "$label"',
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('node-backed fields start with a styled unknown value', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();

    final nameField = tester.widget<TextField>(
      _textFieldWithLabel('Repeater Name'),
    );
    expect(nameField.controller?.text, isEmpty);
    expect(nameField.decoration?.hintText, 'Unknown');
    expect(nameField.decoration?.hintStyle?.fontStyle, FontStyle.italic);
    expect(find.text('Advertised Repeater Name'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Packet Forwarding'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.widgetWithText(SwitchListTile, 'Packet Forwarding'),
      findsNothing,
    );
    expect(find.widgetWithText(ListTile, 'Packet Forwarding'), findsOneWidget);
    expect(find.byKey(const ValueKey('unknown-repeat-picker')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('saving an entered value does not write unknown settings', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.enterText(_textFieldWithLabel('Repeater Name'), 'New Name');
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();

    expect(connector.sentFrames, hasLength(1));
    expect(
      _cliTextFromFrame(connector.sentFrames.single).substring(3),
      'set name New Name',
    );

    connector.respondToLastCommand(repeater, 'OK');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(connector.sentFrames, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('path hash mode is visible outside Advanced settings', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Path hash mode'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Path hash mode'), findsOneWidget);
    expect(find.byKey(const ValueKey('unknown-pathHashMode')), findsOneWidget);
    final pathHashPicker = find.byKey(const ValueKey('path-hash-mode-unknown'));
    await tester.ensureVisible(pathHashPicker);
    await tester.pumpAndSettle();
    await tester.tap(pathHashPicker);
    await tester.pumpAndSettle();

    expect(find.text('0 (1 byte hash)'), findsOneWidget);
    expect(find.text('1 (2 byte hash)'), findsOneWidget);
    expect(find.text('2 (3 byte hash)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('Channel Activity Detection can be assigned and saved', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Advanced'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Channel Activity Detection (CAD)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(
      find.byKey(const ValueKey('unknown-channelActivityDetection-picker')),
      findsOneWidget,
    );
    final cadPicker = find.byKey(
      const ValueKey('unknown-channelActivityDetection-picker'),
    );
    await tester.ensureVisible(cadPicker);
    await tester.pumpAndSettle();
    await tester.tap(cadPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable').last);
    await tester.pumpAndSettle();

    final cadSwitch = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Channel Activity Detection (CAD)'),
    );
    expect(cadSwitch.value, isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    expect(connector.sentFrames, hasLength(1));
    expect(
      _cliTextFromFrame(connector.sentFrames.single).substring(3),
      'set cad on',
    );

    connector.respondToLastCommand(repeater, 'OK');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('an unknown boolean can be assigned and saved', (tester) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Packet Forwarding'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('unknown-repeat-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable').last);
    await tester.pumpAndSettle();

    final forwarding = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Packet Forwarding'),
    );
    expect(forwarding.value, isTrue);

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    expect(connector.sentFrames, hasLength(1));
    expect(
      _cliTextFromFrame(connector.sentFrames.single).substring(3),
      'set repeat on',
    );

    connector.respondToLastCommand(repeater, 'OK');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('an unknown numeric slider can be assigned and saved', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Duty cycle'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final dutyCycleSlider = find.byWidgetPredicate(
      (widget) => widget is Slider && widget.min == 1 && widget.max == 100,
      description: 'Duty cycle slider',
    );
    final unknownSlider = tester.widget<Slider>(dutyCycleSlider);
    expect(unknownSlider.label, 'Unknown');
    expect(unknownSlider.onChanged, isNotNull);
    unknownSlider.onChanged!(42);
    await tester.pump();

    final assignedSlider = tester.widget<Slider>(dutyCycleSlider);
    expect(assignedSlider.value, 42);
    expect(assignedSlider.label, '42%');

    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    expect(connector.sentFrames, hasLength(1));
    expect(
      _cliTextFromFrame(connector.sentFrames.single).substring(3),
      'set dutycycle 42',
    );

    connector.respondToLastCommand(repeater, 'OK');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('a valid node response replaces the unknown value', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh Basic Settings'));
    await tester.pump();
    expect(connector.sentFrames, hasLength(1));
    expect(
      _cliTextFromFrame(connector.sentFrames.single).substring(3),
      'get name',
    );

    connector.respondToLastCommand(repeater, '> Node Name');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final nameField = tester.widget<TextField>(
      _textFieldWithLabel('Repeater Name'),
    );
    expect(nameField.controller?.text, 'Node Name');
    expect(nameField.decoration?.hintText, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });

  testWidgets('known values survive reopening during the login session', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final repeater = _makeRepeater();
    connector.rememberRemoteNodeAuthentication(
      repeater,
      password: 'test-password',
      isAdmin: true,
    );

    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh Basic Settings'));
    await tester.pump();
    connector.respondToLastCommand(repeater, '> Session Name');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();

    var nameField = tester.widget<TextField>(
      _textFieldWithLabel('Repeater Name'),
    );
    expect(nameField.controller?.text, 'Session Name');
    expect(nameField.decoration?.hintText, isNull);
    expect(connector.sentFrames, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    connector.clearRemoteNodeAuthentication(repeater);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(_buildTestApp(connector, repeater));
    await tester.pump();

    nameField = tester.widget<TextField>(_textFieldWithLabel('Repeater Name'));
    expect(nameField.controller?.text, isEmpty);
    expect(nameField.decoration?.hintText, 'Unknown');

    await tester.pumpWidget(const SizedBox.shrink());
    await connector.close();
  });
}
