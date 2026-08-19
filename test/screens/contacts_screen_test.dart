import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';
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
  Contact? removedContact;
  bool removeAllContactsCalled = false;
  bool contactSyncSlow = false;
  bool contactSyncFailure = false;
  bool contactPersistenceSuspended = false;
  int getContactsCalls = 0;
  final Uint8List _selfKey = Uint8List.fromList(
    List<int>.filled(pubKeySize, 0xA5),
  );

  @override
  List<Contact> get contacts => <Contact>[contact];

  @override
  bool get isConnected => true;

  @override
  bool get hasLoadedContacts => true;

  @override
  bool get isContactSyncSlow => contactSyncSlow;

  @override
  bool get contactSyncFailed => contactSyncFailure;

  @override
  bool get isContactPersistenceSuspended => contactPersistenceSuspended;

  @override
  String? get selfName => 'My Companion';

  @override
  Uint8List? get selfPublicKey => _selfKey;

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

  @override
  Future<void> removeContact(Contact contact) async {
    removedContact = contact;
  }

  @override
  Future<void> removeAllContacts() async {
    removeAllContactsCalled = true;
  }

  @override
  Future<void> getContacts({int? since, bool preserveExisting = false}) async {
    getContactsCalls++;
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

  testWidgets('contacts menu copies the self contact URI', (tester) async {
    String? clipboardText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Contact',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );

    await tester.pumpWidget(_buildTestApp(_FakeMeshCoreConnector(contact)));
    await tester.pumpAndSettle();
    final screenContext = tester.element(find.byType(ContactsScreen));
    final l10n = AppLocalizations.of(screenContext);

    await tester.tap(find.byTooltip(l10n.contacts_moreOptions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.shareLink_copySelfShareLink));
    await tester.pump();

    final link = MeshCoreShareLink.tryParse(clipboardText!);
    expect(link, isA<MeshCoreContactShareLink>());
    expect((link! as MeshCoreContactShareLink).name, 'My Companion');
  });

  testWidgets('failed contact sync shows rollback warning and retry', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector(
      Contact(
        publicKey: Uint8List.fromList(List<int>.filled(pubKeySize, 1)),
        name: 'Cached Contact',
        type: advTypeChat,
        pathLength: 0,
        path: Uint8List(0),
        lastSeen: DateTime.now(),
      ),
    )..contactSyncFailure = true;

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );

    expect(find.byKey(const ValueKey('contact_sync_notice')), findsOneWidget);
    expect(find.text(l10n.contacts_syncFailedWarning), findsOneWidget);

    await tester.tap(find.text(l10n.common_retry));
    await tester.pump();

    expect(connector.getContactsCalls, 1);
  });

  testWidgets('contact add explains why changes are blocked during sync', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector(
      Contact(
        publicKey: Uint8List.fromList(List<int>.filled(pubKeySize, 2)),
        name: 'Contact',
        type: advTypeChat,
        pathLength: 0,
        path: Uint8List(0),
        lastSeen: DateTime.now(),
      ),
    )..contactPersistenceSuspended = true;

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();

    expect(find.text(l10n.contacts_syncChangesDisabled), findsOneWidget);
  });

  testWidgets('Delete key confirms removal of the selected contact', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Selected Contact',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    final shortcut = find.byKey(
      ValueKey('contact_delete_shortcut_${contact.publicKeyHex}'),
    );
    final focus = tester
        .widgetList<Focus>(
          find.descendant(of: shortcut, matching: find.byType(Focus)),
        )
        .firstWhere((widget) => widget.focusNode != null);
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(ContactsScreen)),
    );
    expect(
      find.text(l10n.contacts_removeConfirm(contact.name)),
      findsOneWidget,
    );
    expect(connector.removedContact, isNull);

    final cancelButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, l10n.common_cancel),
    );
    expect(cancelButton.autofocus, isTrue);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextButton>(),
      same(cancelButton),
    );

    await tester.tap(find.text(l10n.common_delete));
    await tester.pumpAndSettle();

    expect(connector.removedContact, same(contact));
  });

  testWidgets('contacts menu confirms before deleting all contacts', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Contact',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    final screenContext = tester.element(find.byType(ContactsScreen));
    final l10n = AppLocalizations.of(screenContext);
    await tester.tap(find.byTooltip(l10n.contacts_moreOptions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.contacts_deleteAllContacts));
    await tester.pumpAndSettle();

    expect(find.text(l10n.contacts_deleteAllContactsConfirm), findsOneWidget);
    expect(connector.removeAllContactsCalled, isFalse);

    final cancelButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, l10n.common_cancel),
    );
    expect(cancelButton.autofocus, isTrue);

    await tester.tap(find.text(l10n.common_cancel));
    await tester.pumpAndSettle();
    expect(connector.removeAllContactsCalled, isFalse);

    await tester.tap(find.byTooltip(l10n.contacts_moreOptions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.contacts_deleteAllContacts));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.common_deleteAll));
    await tester.pumpAndSettle();

    expect(connector.removeAllContactsCalled, isTrue);
  });

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
