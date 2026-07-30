import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../models/remote_node_auth_session.dart';
import '../services/storage_service.dart';
import 'repeater_login_dialog.dart';
import 'room_login_dialog.dart';

bool contactRequiresRemoteAuthentication(Contact contact) {
  return contact.type == advTypeRepeater || contact.type == advTypeRoom;
}

Future<RemoteNodeAuthSession?> ensureRemoteNodeAuthenticated(
  BuildContext context, {
  required Contact contact,
  bool forceLogin = false,
}) async {
  assert(contactRequiresRemoteAuthentication(contact));
  final connector = context.read<MeshCoreConnector>();
  final existing = connector.remoteNodeAuthSession(contact);
  if (!forceLogin && existing != null) {
    return existing;
  }

  if (forceLogin) {
    connector.clearRemoteNodeAuthentication(contact);
  }
  if (!context.mounted) return null;

  return showDialog<RemoteNodeAuthSession>(
    context: context,
    builder: (_) => contact.type == advTypeRoom
        ? RoomLoginDialog(room: contact)
        : RepeaterLoginDialog(repeater: contact),
  );
}

Future<void> forgetRemoteNodeCredentials(
  BuildContext context, {
  required Contact contact,
}) async {
  context.read<MeshCoreConnector>().clearRemoteNodeAuthentication(contact);
  await StorageService().removeRepeaterPassword(contact.publicKeyHex);
}
