import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/flood_scope.dart';

void main() {
  group('flood scope transport codes', () {
    final payload = Uint8List.fromList([0x12, 0x34, 0x56]);

    test('matches the firmware HMAC and little-endian code format', () {
      expect(calculateFloodScopeCode('de-mitte', 5, payload), 0x3878);
      expect(calculateFloodScopeCode('#de-mitte', 5, payload), 0x3878);
    });

    test('resolves a tag only to its matching known region', () {
      final code = calculateFloodScopeCode('de-mitte', 5, payload);

      expect(
        resolveFloodScopeRegion(code, 5, payload, ['pl-central', 'de-mitte']),
        'de-mitte',
      );
      expect(resolveFloodScopeRegion(code, 5, payload, ['pl-central']), isNull);
    });

    test('the tag changes with packet contents', () {
      final first = calculateFloodScopeCode('de-mitte', 5, payload);
      final second = calculateFloodScopeCode(
        'de-mitte',
        5,
        Uint8List.fromList([0x12, 0x34, 0x57]),
      );

      expect(second, isNot(first));
    });
  });
}
