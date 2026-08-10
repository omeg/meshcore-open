import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';
import 'package:meshcore_open/screens/settings_screen.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final Uint8List _selfKey = Uint8List.fromList(
    List<int>.generate(32, (index) => index + 1),
  );

  @override
  bool get isConnected => true;

  @override
  String get deviceDisplayName => 'Test Companion';

  @override
  String get deviceIdLabel => 'test-device';

  @override
  String? get firmwareVersion => 'v1.17.0a-omeg';

  @override
  String? get selfName => 'My Companion';

  @override
  Uint8List? get selfPublicKey => _selfKey;
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
    await tester.tap(find.text('Test Companion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.byKey(const ValueKey('copy_self_share_link')));
    await tester.pump();

    final link = MeshCoreShareLink.tryParse(clipboardText!);
    expect(link, isA<MeshCoreContactShareLink>());
    expect((link! as MeshCoreContactShareLink).name, 'My Companion');
  });
}
