import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';
import 'package:meshcore_open/screens/channel_chat_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:meshcore_open/widgets/battery_indicator.dart';
import 'package:meshcore_open/widgets/radio_stats_entry.dart';
import 'package:meshcore_open/widgets/snr_indicator.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  final Uint8List _key = Uint8List.fromList(
    List<int>.generate(pubKeySize, (index) => index + 1),
  );

  Uint8List get key => _key;

  @override
  bool get isConnected => true;

  @override
  String? get selfName => 'My Companion';

  @override
  Uint8List? get selfPublicKey => _key;

  @override
  String get selfPublicKeyHex => pubKeyToHex(_key);
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  testWidgets('channel menu actions and full-screen region selector', (
    tester,
  ) async {
    final connector = _FakeMeshCoreConnector();
    final channel = Channel.fromHex(
      0,
      'Test Channel',
      Channel.publicChannelPsk,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
          ChangeNotifierProvider<AppSettingsService>(
            create: (_) => AppSettingsService(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChannelChatScreen(channel: channel),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ChannelChatScreen)),
    );

    expect(find.text(l10n.chat_unread(0)), findsOneWidget);
    expect(find.text(l10n.channels_public), findsNothing);
    expect(find.byTooltip(l10n.channels_regionSelect_Title), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l10n.channels_regionSelect_Title), findsOneWidget);
    expect(find.text(l10n.settings_title), findsOneWidget);
    expect(find.text(l10n.common_disconnect), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(l10n.channels_regionSelect_Title)).dy,
      lessThan(tester.getTopLeft(find.text(l10n.shareLink_shareMyContact)).dy),
    );
    expect(
      tester.getTopLeft(find.text(l10n.settings_title)).dy,
      lessThan(tester.getTopLeft(find.text(l10n.common_disconnect)).dy),
    );

    await tester.tap(find.text(l10n.channels_regionSelect_Title));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(Scaffold), findsOneWidget);
    expect(
      tester.getSize(find.byType(Scaffold)),
      tester.view.physicalSize / tester.view.devicePixelRatio,
    );
    expect(find.byType(BatteryIndicator), findsNothing);
    expect(find.byType(SNRIndicator), findsNothing);
    expect(find.byType(RadioStatsIconButton), findsNothing);

    Navigator.of(
      tester.element(find.text(l10n.channels_regionSelect_Title)),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.shareLink_shareMyContact));
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    final parsed = MeshCoreShareLink.tryParse(textField.controller!.text);
    expect(parsed, isA<MeshCoreContactShareLink>());
    final contact = parsed! as MeshCoreContactShareLink;
    expect(contact.name, 'My Companion');
    expect(pubKeyToHex(contact.publicKey!), pubKeyToHex(connector.key));
    await tester.pump(const Duration(milliseconds: 100));
  });
}
