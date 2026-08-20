import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/l10n/app_localizations.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/screens/discovery_screen.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/theme/mesh_theme.dart';
import 'package:meshcore_open/widgets/mesh_ui.dart';

class _FakeMeshCoreConnector extends MeshCoreConnector {
  _FakeMeshCoreConnector(Contact contact)
    : discoveredContactsValue = <Contact>[contact];

  _FakeMeshCoreConnector.withContacts(this.discoveredContactsValue);

  final List<Contact> discoveredContactsValue;
  Contact? importedContact;
  Contact? removedContact;

  @override
  List<Contact> get discoveredContacts => discoveredContactsValue;

  @override
  Future<bool> importDiscoveredContact(Contact contact) async {
    importedContact = contact;
    return true;
  }

  @override
  Future<void> removeDiscoveredContact(Contact contact) async {
    removedContact = contact;
  }
}

Widget _buildTestApp(MeshCoreConnector connector) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<MeshCoreConnector>.value(value: connector),
      ChangeNotifierProvider<AppSettingsService>(
        create: (_) => AppSettingsService(),
      ),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DiscoveryScreen(),
    ),
  );
}

void main() {
  testWidgets('discovered contacts default to newest advert first', (
    tester,
  ) async {
    Contact contact(
      String name,
      int keyByte,
      DateTime lastAdvertAt, {
      DateTime? lastMessageAt,
    }) => Contact(
      publicKey: Uint8List(pubKeySize)..fillRange(0, pubKeySize, keyByte),
      name: name,
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: lastAdvertAt,
      lastMessageAt: lastMessageAt,
    );

    final connector = _FakeMeshCoreConnector.withContacts(<Contact>[
      contact(
        'Old advert',
        1,
        DateTime(2026, 1, 1),
        lastMessageAt: DateTime(2026, 4, 1),
      ),
      contact('Newest advert', 2, DateTime(2026, 3, 1)),
      contact('Middle advert', 3, DateTime(2026, 2, 1)),
      contact('Invalid future advert', 4, DateTime(2035, 1, 1)),
    ]);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    final newestY = tester.getTopLeft(find.text('Newest advert')).dy;
    final middleY = tester.getTopLeft(find.text('Middle advert')).dy;
    final oldestY = tester.getTopLeft(find.text('Old advert')).dy;
    final invalidFutureY = tester
        .getTopLeft(find.text('Invalid future advert'))
        .dy;

    expect(newestY, lessThan(middleY));
    expect(middleY, lessThan(oldestY));
    expect(oldestY, lessThan(invalidFutureY));
  });

  testWidgets('Delete key removes the selected discovered contact', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Selected Discovery',
      type: advTypeChat,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
    final connector = _FakeMeshCoreConnector(contact);

    await tester.pumpWidget(_buildTestApp(connector));
    await tester.pumpAndSettle();

    final shortcut = find.byKey(
      ValueKey('discovered_contact_delete_shortcut_${contact.publicKeyHex}'),
    );
    final focus = tester
        .widgetList<Focus>(
          find.descendant(of: shortcut, matching: find.byType(Focus)),
        )
        .firstWhere((widget) => widget.focusNode != null);
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();

    expect(connector.removedContact, same(contact));
  });

  testWidgets('discovered contact context menu can add the contact', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Discovered Node',
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

    final screenContext = tester.element(find.byType(DiscoveryScreen));
    final l10n = AppLocalizations.of(screenContext);
    expect(find.text(l10n.discoveredContacts_addContact), findsOneWidget);

    await tester.tap(find.text(l10n.discoveredContacts_addContact));
    await tester.pumpAndSettle();

    expect(connector.importedContact, same(contact));
    expect(find.text(l10n.discoveredContacts_contactAdded), findsOneWidget);

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.persist, isFalse);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.text(l10n.discoveredContacts_contactAdded), findsNothing);
  });

  testWidgets('discovered contact uses compact metadata layout', (
    tester,
  ) async {
    final contact = Contact(
      publicKey: Uint8List.fromList(
        List<int>.generate(pubKeySize, (index) => index + 1),
      ),
      name: 'Compact Repeater',
      type: advTypeRepeater,
      pathLength: 4,
      path: Uint8List.fromList([1, 2, 3, 4]),
      lastSeen: DateTime.now().subtract(
        const Duration(minutes: 2, seconds: 30),
      ),
    );

    await tester.pumpWidget(_buildTestApp(_FakeMeshCoreConnector(contact)));
    await tester.pumpAndSettle();

    expect(find.text('REPEATER'), findsNothing);
    expect(find.text('recently'), findsNothing);
    expect(find.text('2 m'), findsOneWidget);
    expect(find.text('4 HOPS'), findsOneWidget);
    expect(find.text('01020304..1d1e1f20'), findsOneWidget);
    expect(find.byIcon(Icons.trending_flat), findsNothing);
    final chipContext = tester.element(find.byType(RouteChip));
    final chipScheme = Theme.of(chipContext).colorScheme;
    final hopsText = tester.widget<Text>(find.text('4 HOPS'));
    expect(hopsText.style?.fontSize, 9.5);
    expect(hopsText.style?.color, chipScheme.onSurfaceVariant);
    expect(
      tester.widget<Text>(find.text('2 m')).style?.color,
      Color.lerp(chipScheme.onSurfaceVariant, MeshPalette.activity, 0.5),
    );
    final chipContainer = tester.widget<Container>(
      find.descendant(
        of: find.byType(RouteChip),
        matching: find.byType(Container),
      ),
    );
    final chipDecoration = chipContainer.decoration! as BoxDecoration;
    expect(
      chipDecoration.color,
      Color.alphaBlend(MeshPalette.blueBg, chipScheme.surfaceContainerHigh),
    );

    final timeRight = tester.getTopRight(find.text('2 m')).dx;
    final hopsRight = tester.getTopRight(find.byType(RouteChip)).dx;
    expect(hopsRight, closeTo(timeRight, 1));
  });
}
