import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/screens/neighbors_screen.dart';
import 'package:provider/provider.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector({required this.repeater, this.neighbor});

  final Contact repeater;
  final Contact? neighbor;
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();

  @override
  List<Contact> get contacts => <Contact>[repeater, ?neighbor];

  @override
  List<Contact> get allContactsUnfiltered => contacts;

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    return const PathSelection(pathBytes: [], hopCount: -1, useFlood: true);
  }

  @override
  int calculateTimeout({
    required int pathLength,
    int messageBytes = 100,
    String? contactKey,
    int? deviceTimeoutMs,
  }) {
    return 60000;
  }

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {}

  void respondWithNeighbor(List<int> keyPrefix) {
    const tag = <int>[0x11, 0x22, 0x33, 0x44];
    _frames.add(Uint8List.fromList(<int>[respCodeSent, 0, ...tag]));
    _frames.add(
      Uint8List.fromList(<int>[
        pushCodeBinaryResponse,
        0,
        ...tag,
        1,
        0,
        1,
        0,
        ...keyPrefix,
        5,
        0,
        0,
        0,
        24,
      ]),
    );
  }

  Future<void> close() => _frames.close();
}

Contact _contact(String name, List<int> key, {double? latitude}) {
  return Contact(
    publicKey: Uint8List.fromList(key),
    name: name,
    type: advTypeRepeater,
    pathLength: -1,
    path: Uint8List(0),
    latitude: latitude,
    longitude: latitude == null ? null : 21.01,
    lastSeen: DateTime(2026),
  );
}

Widget _testApp(_FakeMeshCoreConnector connector) {
  return ChangeNotifierProvider<MeshCoreConnector>.value(
    value: connector,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: NeighborsScreen(
        repeater: connector.repeater,
        password: 'test-password',
      ),
    ),
  );
}

void main() {
  final repeaterKey = List<int>.generate(pubKeySize, (index) => index + 1);
  final neighborKey = <int>[
    0xA1,
    0xB2,
    0xC3,
    0xD4,
    ...List<int>.generate(pubKeySize - 4, (index) => index + 5),
  ];

  testWidgets('known neighbor exposes the nearby repeater actions', (
    tester,
  ) async {
    final neighbor = _contact('Known Neighbor', neighborKey, latitude: 52.23);
    final connector = _FakeMeshCoreConnector(
      repeater: _contact('Managed Repeater', repeaterKey),
      neighbor: neighbor,
    );
    addTearDown(connector.close);

    await tester.pumpWidget(_testApp(connector));
    await tester.pump();
    connector.respondWithNeighbor(neighborKey.take(4).toList());
    await tester.pumpAndSettle();

    await tester.longPress(find.text(neighbor.name));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(NeighborsScreen)),
    );
    expect(find.text(l10n.nearbyNodes_goToContact), findsOneWidget);
    expect(find.text(l10n.nearbyNodes_copyPublicKey), findsOneWidget);
    expect(find.text(l10n.settings_locationShowOnMap), findsOneWidget);
  });

  testWidgets('unknown neighbor offers copying its public key prefix', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector(
      repeater: _contact('Managed Repeater', repeaterKey),
    );
    addTearDown(connector.close);

    await tester.pumpWidget(_testApp(connector));
    await tester.pump();
    connector.respondWithNeighbor(neighborKey.take(4).toList());
    await tester.pumpAndSettle();

    await tester.longPress(find.textContaining('a1b2c3d4'));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(NeighborsScreen)),
    );
    expect(find.text(l10n.nearbyNodes_goToContact), findsNothing);
    expect(find.text(l10n.nearbyNodes_copyPublicKeyPrefix), findsOneWidget);
    expect(find.text(l10n.settings_locationShowOnMap), findsNothing);
  });
}
