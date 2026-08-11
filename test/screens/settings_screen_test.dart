import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';
import 'package:meshcore_open/screens/map_screen.dart';
import 'package:meshcore_open/screens/settings_screen.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final Uint8List _selfKey = Uint8List.fromList(
    List<int>.generate(32, (index) => index + 1),
  );
  Uint8List? importedPrivateKey;
  int _pathHashWidth = 2;
  int? selectedPathHashMode;

  @override
  bool get isConnected => true;

  @override
  String get deviceDisplayName => 'Test Companion';

  @override
  String get deviceIdLabel => 'test-device';

  @override
  String? get firmwareVersion => 'v1.17.0a-omeg';

  @override
  bool get supportsPathHashMode => true;

  @override
  int get pathHashByteWidth => _pathHashWidth;

  @override
  String? get selfName => 'My Companion';

  @override
  Uint8List? get selfPublicKey => _selfKey;

  @override
  double? get selfLatitude => 51.1079;

  @override
  double? get selfLongitude => 17.0385;

  @override
  Future<void> importPrivateKey(Uint8List privateKey) async {
    importedPrivateKey = Uint8List.fromList(privateKey);
  }

  @override
  Future<void> setPathHashMode(int mode) async {
    selectedPathHashMode = mode;
    _pathHashWidth = mode + 1;
    notifyListeners();
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'MeshCore Open',
      packageName: 'meshcore_open',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('device info shows the companion firmware version', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: _FakeMeshCoreConnector(),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Test Companion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Firmware Version'), findsOneWidget);
    expect(find.text('v1.17.0a-omeg'), findsOneWidget);
  });

  testWidgets('device info copies the self contact URI', (tester) async {
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

    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: _FakeMeshCoreConnector(),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('copy_self_share_link')));
    await tester.pump();

    final link = MeshCoreShareLink.tryParse(clipboardText!);
    expect(link, isA<MeshCoreContactShareLink>());
    expect((link! as MeshCoreContactShareLink).name, 'My Companion');
  });

  testWidgets('public key is in Identity rather than Device Info', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: _FakeMeshCoreConnector(),
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    final identityCard = find.byKey(const ValueKey('identity_card'));
    final deviceInfoCard = find.byKey(const ValueKey('device_info_card'));
    expect(
      find.descendant(of: identityCard, matching: find.text('Public Key')),
      findsOneWidget,
    );

    await tester.tap(find.text('Test Companion'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.descendant(of: deviceInfoCard, matching: find.text('Public Key')),
      findsNothing,
    );
  });

  testWidgets('node settings updates the companion path hash size', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: connector,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('2-byte hashes per hop (up to 32 hops)'), findsOneWidget);
    await tester.tap(find.text('Path Hash Size'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('path_hash_size_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3-byte hashes per hop (up to 21 hops)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('path_hash_size_save')));
    await tester.pumpAndSettle();

    expect(connector.selectedPathHashMode, 2);
    expect(find.text('Path hash size updated'), findsOneWidget);
  });

  testWidgets('change identity validates and imports a 64-byte key', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: connector,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Change Identity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.enterText(
      find.byKey(const ValueKey('private_key_input')),
      'abcd',
    );
    await tester.tap(find.byKey(const ValueKey('change_identity_confirm')));
    await tester.pump();
    expect(
      find.text(
        'Enter a valid 64-byte private key using 128 hexadecimal characters.',
      ),
      findsOneWidget,
    );
    expect(connector.importedPrivateKey, isNull);

    final privateKeyHex = List<String>.filled(64, 'ab').join();
    await tester.enterText(
      find.byKey(const ValueKey('private_key_input')),
      privateKeyHex,
    );
    await tester.tap(find.byKey(const ValueKey('change_identity_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      connector.importedPrivateKey,
      Uint8List.fromList(List.filled(64, 0xab)),
    );
    expect(find.text('Identity changed'), findsOneWidget);
  });

  testWidgets('location coordinates can be opened on the map', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      ChangeNotifierProvider<MeshCoreConnector>.value(
        value: _FakeMeshCoreConnector(),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [observer],
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.location_on_outlined));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('location_latitude_input')),
      '50.06143',
    );
    await tester.enterText(
      find.byKey(const ValueKey('location_longitude_input')),
      '19.93658',
    );
    await tester.tap(find.byKey(const ValueKey('location_show_on_map')));

    final route = observer.lastPushedRoute as MaterialPageRoute<void>;
    final mapScreen =
        route.builder(tester.element(find.byType(SettingsScreen))) as MapScreen;
    expect(mapScreen.highlightPosition?.latitude, 50.06143);
    expect(mapScreen.highlightPosition?.longitude, 19.93658);
    expect(mapScreen.hideBackButton, isFalse);

    route.navigator?.pop();
    await tester.pumpAndSettle();
  });
}
