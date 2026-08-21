import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/public_key.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/repeater_hub_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:provider/provider.dart';

Contact _repeater({double? latitude, double? longitude}) {
  return Contact(
    publicKey: Uint8List.fromList(
      List<int>.generate(pubKeySize, (index) => index + 1),
    ),
    name: 'Test Repeater',
    type: advTypeRepeater,
    latitude: latitude,
    longitude: longitude,
    pathLength: -1,
    path: Uint8List(0),
    lastSeen: DateTime(2026),
  );
}

Widget _buildTestApp(Contact repeater) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => MeshCoreConnector()),
      ChangeNotifierProvider(create: (_) => AppSettingsService()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepeaterHubScreen(
        repeater: repeater,
        password: 'test-password',
        isAdmin: true,
      ),
    ),
  );
}

void main() {
  testWidgets('location shortcut is shown beside coordinates only when set', (
    tester,
  ) async {
    final locatedRepeater = _repeater(latitude: 51.1, longitude: 17.0);
    await tester.pumpWidget(_buildTestApp(locatedRepeater));
    await tester.pumpAndSettle();

    final mapButton = find.byKey(const ValueKey('repeater_show_on_map'));
    final coordinates = find.text('51.1000, 17.0000');
    final publicKey = find.text(
      formatPublicKeyHex(locatedRepeater.publicKeyHex),
    );
    final copyIcon = find.byIcon(Icons.copy_outlined);

    expect(mapButton, findsOneWidget);
    expect(tester.getCenter(mapButton).dy, greaterThan(kToolbarHeight));
    expect(
      tester.getTopLeft(mapButton).dx - tester.getTopRight(coordinates).dx,
      lessThanOrEqualTo(4),
    );
    expect(
      tester.getTopLeft(copyIcon).dx - tester.getTopRight(publicKey).dx,
      lessThanOrEqualTo(4),
    );

    await tester.pumpWidget(_buildTestApp(_repeater()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('repeater_show_on_map')), findsNothing);
  });
}
