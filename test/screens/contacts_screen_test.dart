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
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/screens/telemetry_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/repeater_login_dialog.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector(this.contact);

  final Contact contact;
  Uint8List? sentFrame;

  @override
  List<Contact> get contacts => <Contact>[contact];

  @override
  bool get isConnected => true;

  @override
  bool get hasLoadedContacts => true;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    return const PathSelection(
      pathBytes: <int>[],
      hopCount: 0,
      useFlood: false,
    );
  }

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    sentFrame = Uint8List.fromList(data);
  }
}

Widget _buildTestApp(MeshCoreConnector connector) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
      ChangeNotifierProvider<UiViewStateService>(
        create: (_) => UiViewStateService(),
      ),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ContactsScreen(),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('contact menu opens telemetry and requests contact telemetry', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Telemetry Contact',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();

    final screenContext = tester.element(find.byType(ContactsScreen));
    final l10n = AppLocalizations.of(screenContext);
    expect(find.text(l10n.contact_telemetry), findsOneWidget);

    await tester.tap(find.text(l10n.contact_telemetry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(connector.sentFrame, buildSendTelemetryReq(contact.publicKey));
  });

  testWidgets('repeater telemetry prompts for login when unauthenticated', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Telemetry Repeater',
      type: advTypeRepeater,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );

    await tester.tap(find.text(l10n.contact_telemetry));
    await tester.pumpAndSettle();

    expect(find.byType(RepeaterLoginDialog), findsOneWidget);
    expect(find.byType(TelemetryScreen), findsNothing);
    expect(connector.sentFrame, isNull);
  });

  testWidgets('authenticated repeater telemetry skips login dialog', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Authenticated Repeater',
      type: advTypeRepeater,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);
    connector.rememberRemoteNodeAuthentication(
      contact,
      password: 'secret',
      isAdmin: true,
    );

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );

    await tester.tap(find.text(l10n.contact_telemetry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(RepeaterLoginDialog), findsNothing);
    expect(find.byType(TelemetryScreen), findsOneWidget);
    expect(
      connector.sentFrame,
      buildSendBinaryReq(
        contact.publicKey,
        payload: buildTelemetryBinaryPayload(),
      ),
    );
  });
}
