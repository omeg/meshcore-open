import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';

void main() {
  group('buildImportPrivateKeyFrame', () {
    test('prefixes a complete 64-byte private identity with command 24', () {
      final privateKey = Uint8List.fromList(
        List<int>.generate(privateKeySize, (index) => index),
      );

      final frame = buildImportPrivateKeyFrame(privateKey);

      expect(frame, hasLength(1 + privateKeySize));
      expect(frame.first, cmdImportPrivateKey);
      expect(frame.sublist(1), privateKey);
    });

    test('rejects keys that are not exactly 64 bytes', () {
      expect(
        () => buildImportPrivateKeyFrame(Uint8List(privateKeySize - 1)),
        throwsArgumentError,
      );
      expect(
        () => buildImportPrivateKeyFrame(Uint8List(privateKeySize + 1)),
        throwsArgumentError,
      );
    });
  });
}
