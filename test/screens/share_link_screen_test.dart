import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';
import 'package:meshcore_open/screens/share_link_screen.dart';
import 'package:provider/provider.dart';

Widget _testApp(MeshCoreChannelShareLink link) {
  return ChangeNotifierProvider(
    create: (_) => MeshCoreConnector(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ShareLinkScreen(link: link),
    ),
  );
}

void main() {
  const secret = 'cff8d9106784fcb460341fe32b43cb9f';

  testWidgets('private channel share allows changing its local name', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        MeshCoreChannelShareLink(
          name: 'Original name',
          secret: Channel.parsePskHex(secret),
        ),
      ),
    );

    final field = find.byKey(const ValueKey('share_link_channel_name'));
    expect(field, findsOneWidget);
    expect(find.text('Original name'), findsWidgets);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextField)),
      'My local name',
    );
    expect(find.text('My local name'), findsOneWidget);
  });

  testWidgets('hashtag channel share keeps its canonical name', (tester) async {
    await tester.pumpWidget(
      _testApp(
        MeshCoreChannelShareLink(
          name: '#kielce',
          secret: Channel.parsePskHex(secret),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('share_link_channel_name')), findsNothing);
    expect(find.text('#kielce'), findsWidgets);
  });
}
