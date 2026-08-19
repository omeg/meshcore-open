import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import 'snack_bar_builder.dart';

const int _publicKeyEndChars = 8;

/// Formats a full public key as four leading bytes, two dots, and four
/// trailing bytes. Short protocol prefixes are returned unchanged.
String formatPublicKeyHex(String publicKeyHex) {
  if (publicKeyHex.length != pubKeySize * 2) return publicKeyHex;
  return '${publicKeyHex.substring(0, _publicKeyEndChars)}..'
      '${publicKeyHex.substring(publicKeyHex.length - _publicKeyEndChars)}';
}

String formatPublicKey(Uint8List publicKey) =>
    formatPublicKeyHex(pubKeyToHex(publicKey));

/// Copies the complete public key, irrespective of its shortened UI form.
Future<void> copyPublicKeyHex(
  BuildContext context,
  String publicKeyHex, {
  bool isPrefix = false,
}) async {
  await Clipboard.setData(ClipboardData(text: publicKeyHex));
  if (!context.mounted) return;
  showDismissibleSnackBar(
    context,
    content: Text(
      isPrefix
          ? context.l10n.nearbyNodes_keyPrefixCopied
          : context.l10n.nearbyNodes_keyCopied,
    ),
  );
}
