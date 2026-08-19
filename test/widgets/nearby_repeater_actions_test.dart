import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/contacts_screen.dart';
import 'package:meshcore_open/screens/nearby_nodes_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector({required this.contact, required this.repeater});

  final Contact? contact;
  final DirectRepeater repeater;
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  @override
  bool get isConnected => true;

  @override
  int? get currentSf => 9;

  @override
  List<DirectRepeater> get directRepeaters => <DirectRepeater>[repeater];

  @override
  List<Contact> get contacts =>
      contact == null ? <Contact>[] : <Contact>[contact!];

  @override
  List<Contact> get allContacts => contacts;

  @override
  List<Contact> get allContactsUnfiltered => contacts;

  @override
  List<Contact> get discoveredContacts =>
      contact == null ? <Contact>[] : <Contact>[contact!];

  @override
  bool get hasLoadedContacts => true;

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    if (data.length < 7 || data.first != cmdSendControlData) return;
    final tag = data[3] | (data[4] << 8) | (data[5] << 16) | (data[6] << 24);
    final publicKey =
        contact?.publicKey ??
        Uint8List.fromList(List<int>.generate(pubKeySize, (index) => index));
    _frames.add(
      Uint8List.fromList(<int>[
        pushCodeControlData,
        24,
        0xB6,
        0,
        (controlSubtypeDiscoverResp << 4) | advTypeRepeater,
        20,
        tag & 0xFF,
        (tag >> 8) & 0xFF,
        (tag >> 16) & 0xFF,
        (tag >> 24) & 0xFF,
        ...publicKey,
      ]),
    );
  }

  @override
  void dispose() {
    _frames.close();
    super.dispose();
  }
}

Contact _repeaterContact() {
  return Contact(
    publicKey: Uint8List.fromList(<int>[
      0x11,
      0x22,
      ...List<int>.generate(pubKeySize - 2, (index) => index + 2),
    ]),
    name: 'Known Repeater',
    type: advTypeRepeater,
    pathLength: 0,
    path: Uint8List(0),
    latitude: 52.23,
    longitude: 21.01,
    lastSeen: DateTime.now(),
  );
}

Widget _testApp(_FakeMeshCoreConnector connector, Widget home) {
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
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
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

  testWidgets('discovery nearby repeaters expose contact actions', (
    tester,
  ) async {
    final contact = _repeaterContact();
    final connector = _FakeMeshCoreConnector(
      contact: contact,
      repeater: DirectRepeater(hashPrefix: <int>[0x11, 0x22], snr: 6),
    );
    addTearDown(connector.dispose);

    await tester.pumpWidget(_testApp(connector, const NearbyNodesScreen()));
    await tester.pump();

    expect(find.text(contact.name), findsOneWidget);
    expect(find.text('11220203..1c1d1e1f'), findsOneWidget);
    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(NearbyNodesScreen)),
    );
    expect(find.text(l10n.nearbyNodes_goToContact), findsOneWidget);
    expect(find.text(l10n.nearbyNodes_copyPublicKey), findsOneWidget);
    expect(find.text(l10n.settings_locationShowOnMap), findsOneWidget);
  });

  testWidgets('SNR nearby repeaters expose contact actions', (tester) async {
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
    final contact = _repeaterContact();
    final connector = _FakeMeshCoreConnector(
      contact: contact,
      repeater: DirectRepeater(hashPrefix: <int>[0x11, 0x22], snr: 6),
    );
    addTearDown(connector.dispose);

    await tester.pumpWidget(
      _testApp(connector, Scaffold(body: SNRIndicator(connector: connector))),
    );
    await tester.tap(find.byType(SNRIndicator));
    await tester.pumpAndSettle();

    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(SNRIndicator)));
    expect(find.text(l10n.nearbyNodes_goToContact), findsOneWidget);
    expect(find.text(l10n.nearbyNodes_copyPublicKey), findsOneWidget);
    expect(find.text(l10n.settings_locationShowOnMap), findsOneWidget);

    await tester.tap(find.text(l10n.nearbyNodes_copyPublicKey));
    await tester.pump();
    expect(clipboardText, contact.publicKeyHex);
  });

  testWidgets('unresolved SNR repeaters copy only the known key prefix', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector(
      contact: null,
      repeater: DirectRepeater(hashPrefix: <int>[0x11, 0x22], snr: 6),
    );
    addTearDown(connector.dispose);

    await tester.pumpWidget(
      _testApp(connector, Scaffold(body: SNRIndicator(connector: connector))),
    );
    await tester.tap(find.byType(SNRIndicator));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('1122').first);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(SNRIndicator)));
    expect(find.text(l10n.nearbyNodes_goToContact), findsNothing);
    expect(find.text(l10n.nearbyNodes_copyPublicKeyPrefix), findsOneWidget);
    expect(find.text(l10n.settings_locationShowOnMap), findsNothing);
  });

  testWidgets('going to a saved contact preserves discovered contacts', (
    tester,
  ) async {
    final contact = _repeaterContact();
    final connector = _FakeMeshCoreConnector(
      contact: contact,
      repeater: DirectRepeater(hashPrefix: <int>[0x11, 0x22], snr: 6),
    );
    addTearDown(connector.dispose);

    await tester.pumpWidget(
      _testApp(connector, Scaffold(body: SNRIndicator(connector: connector))),
    );
    await tester.tap(find.byType(SNRIndicator));
    await tester.pumpAndSettle();
    await tester.longPress(find.text(contact.name));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(tester.element(find.byType(SNRIndicator)));
    await tester.tap(find.text(l10n.nearbyNodes_goToContact));
    await tester.pumpAndSettle();

    expect(find.byType(ContactsScreen), findsOneWidget);
    expect(connector.discoveredContacts, contains(same(contact)));
  });
}
