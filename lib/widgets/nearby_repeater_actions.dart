import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../helpers/public_key.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../screens/contacts_screen.dart';
import '../screens/discovery_screen.dart';
import '../screens/map_screen.dart';
import 'mesh_ui.dart';

enum _NearbyRepeaterAction { goToContact, copyPublicKey, showOnMap }

Future<void> showNearbyRepeaterActions(
  BuildContext context, {
  required String identityHex,
  required bool hasFullPublicKey,
  required bool isSavedContact,
  Contact? contact,
}) async {
  final navigator = Navigator.of(context);
  final l10n = context.l10n;

  final action = await showMeshSheet<_NearbyRepeaterAction>(
    context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(
            title: contact?.name ?? l10n.nearbyNodes_unknownRepeater,
            subtitle: hasFullPublicKey
                ? formatPublicKeyHex(identityHex)
                : identityHex,
          ),
          if (contact != null)
            ListTile(
              leading: const Icon(Icons.person_search),
              title: Text(l10n.nearbyNodes_goToContact),
              subtitle: Text(
                isSavedContact
                    ? l10n.contacts_title
                    : l10n.discoveredContacts_Title,
              ),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_NearbyRepeaterAction.goToContact),
            ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(
              hasFullPublicKey
                  ? l10n.nearbyNodes_copyPublicKey
                  : l10n.nearbyNodes_copyPublicKeyPrefix,
            ),
            onTap: () => Navigator.of(
              sheetContext,
            ).pop(_NearbyRepeaterAction.copyPublicKey),
          ),
          if (contact?.hasLocation ?? false)
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: Text(l10n.settings_locationShowOnMap),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_NearbyRepeaterAction.showOnMap),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );

  if (action == null || !context.mounted) return;

  switch (action) {
    case _NearbyRepeaterAction.goToContact:
      final publicKeyHex = contact!.publicKeyHex;
      if (isSavedContact) {
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                ContactsScreen(highlightedContactPublicKeyHex: publicKeyHex),
          ),
        );
      } else {
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) =>
                DiscoveryScreen(highlightedContactPublicKeyHex: publicKeyHex),
          ),
        );
      }
      break;
    case _NearbyRepeaterAction.copyPublicKey:
      await copyPublicKeyHex(context, identityHex, isPrefix: !hasFullPublicKey);
      break;
    case _NearbyRepeaterAction.showOnMap:
      final mappedContact = contact!;
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MapScreen(
            highlightPosition: LatLng(
              mappedContact.latitude!,
              mappedContact.longitude!,
            ),
            highlightLabel: mappedContact.name,
          ),
        ),
      );
      break;
  }
}
