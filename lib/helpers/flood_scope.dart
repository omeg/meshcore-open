import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Computes the packet-specific transport code used by MeshCore for a flood
/// scope. The scope key is the first 16 bytes of SHA-256("#region").
int calculateFloodScopeCode(String region, int payloadType, Uint8List payload) {
  final normalized = region.startsWith('#') ? region : '#$region';
  final scopeKey = crypto.sha256
      .convert(utf8.encode(normalized))
      .bytes
      .sublist(0, 16);
  final input = Uint8List(1 + payload.length)
    ..[0] = payloadType
    ..setRange(1, payload.length + 1, payload);
  final digest = crypto.Hmac(crypto.sha256, scopeKey).convert(input).bytes;
  var code = digest[0] | (digest[1] << 8);

  // Firmware reserves the all-zero and all-one transport codes.
  if (code == 0) code = 1;
  if (code == 0xffff) code = 0xfffe;
  return code;
}

/// Resolves a packet transport code against the region names known to the app.
String? resolveFloodScopeRegion(
  int scopeCode,
  int payloadType,
  Uint8List payload,
  Iterable<String> regions,
) {
  for (final region in regions) {
    if (region.isEmpty) continue;
    if (calculateFloodScopeCode(region, payloadType, payload) == scopeCode) {
      return region;
    }
  }
  return null;
}
