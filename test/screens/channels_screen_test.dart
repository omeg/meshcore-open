import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/screens/channels_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/services/ui_view_state_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final Channel channel = Channel.fromHex(
    0,
    'Public',
    Channel.publicChannelPsk,
  );
  final Uint8List _key = Uint8List.fromList(List<int>.filled(pubKeySize, 0xA5));

  @override
  bool get isConnected => true;

  @override
  String? get selfName => 'My Companion';

  @override
  Uint8List? get selfPublicKey => _key;

  @override
  String get selfPublicKeyHex => pubKeyToHex(_key);

  @override
  List<Channel> get channels => <Channel>[channel];

  @override
  Future<void> getChannels({int? maxChannels, bool force = false}) async {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('add channel lives in overflow instead of a floating button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(
            value: _FakeMeshCoreConnector(),
          ),
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
          home: ChannelsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ChannelsScreen)),
    );

    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.channels_addChannel), findsOneWidget);
    expect(find.text(l10n.settings_title), findsOneWidget);
    expect(find.text(l10n.common_disconnect), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(l10n.settings_title)).dy,
      lessThan(tester.getTopLeft(find.text(l10n.common_disconnect)).dy),
    );

    await tester.tap(find.text(l10n.channels_addChannel));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(l10n.channels_addChannel),
      ),
      findsOneWidget,
    );
  });
}
