import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/public_key.dart';

void main() {
  test('formats a public key using its first and last four bytes', () {
    final publicKey = Uint8List.fromList(
      List<int>.generate(32, (index) => index + 1),
    );

    expect(formatPublicKey(publicKey), '01020304..1d1e1f20');
  });

  test('leaves a protocol key prefix unchanged', () {
    expect(formatPublicKeyHex('a1b2c3d4e5f6'), 'a1b2c3d4e5f6');
  });
}
