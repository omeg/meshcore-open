import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/path_trace_codec.dart';

void main() {
  group('encodeTraceRequestPath', () {
    test('uses one-byte trace mode for one-byte paths', () {
      final result = encodeTraceRequestPath(
        Uint8List.fromList([0x11, 0x22]),
        sourceHashByteWidth: 1,
      )!;

      expect(result.flags, 0);
      expect(result.hashByteWidth, 1);
      expect(result.payload, [0x11, 0x22]);
    });

    test('uses two-byte trace mode for two-byte paths', () {
      final result = encodeTraceRequestPath(
        Uint8List.fromList([0x11, 0x12, 0x21, 0x22]),
        sourceHashByteWidth: 2,
      )!;

      expect(result.flags, 1);
      expect(result.hashByteWidth, 2);
      expect(result.payload, [0x11, 0x12, 0x21, 0x22]);
    });

    test('down-converts three-byte source hops to two bytes', () {
      final result = encodeTraceRequestPath(
        Uint8List.fromList([0x11, 0x12, 0x13, 0x21, 0x22, 0x23]),
        sourceHashByteWidth: 3,
      )!;

      expect(result.flags, 1);
      expect(result.hashByteWidth, 2);
      expect(result.payload, [0x11, 0x12, 0x21, 0x22]);
    });

    test('mirrors a route around the target without duplicating the pivot', () {
      final result = encodeTraceRequestPath(
        Uint8List.fromList([0x11, 0x12, 0x21, 0x22]),
        sourceHashByteWidth: 2,
        targetPublicKey: Uint8List.fromList([0x31, 0x32, 0x33]),
        mirrorAroundTarget: true,
      )!;

      expect(result.payload, [
        0x11,
        0x12,
        0x21,
        0x22,
        0x31,
        0x32,
        0x21,
        0x22,
        0x11,
        0x12,
      ]);
    });

    test('rejects a path that is not aligned to the source width', () {
      final result = encodeTraceRequestPath(
        Uint8List.fromList([0x11, 0x12, 0x13]),
        sourceHashByteWidth: 2,
      );

      expect(result, isNull);
    });
  });

  test('reverseTraceSourcePath reverses hops without reversing hop bytes', () {
    final result = reverseTraceSourcePath(
      Uint8List.fromList([0x11, 0x12, 0x21, 0x22]),
      2,
    );

    expect(result, [0x21, 0x22, 0x11, 0x12]);
  });

  group('decodeTraceResponse', () {
    test('decodes two-byte hops and signed quarter-dB SNR values', () {
      final frame = Uint8List.fromList([
        0x89,
        0x00,
        0x04,
        0x01,
        1, 2, 3, 4, // tag
        0, 0, 0, 0, // auth
        0x11, 0x12, 0x21, 0x22, // path
        8, 0xFC, 4, // 2.0, -1.0, 1.0 dB
      ]);

      final result = decodeTraceResponse(frame);

      expect(result.hashByteWidth, 2);
      expect(result.path, [
        Uint8List.fromList([0x11, 0x12]),
        Uint8List.fromList([0x21, 0x22]),
      ]);
      expect(result.snr, [2.0, -1.0, 1.0]);
    });

    test('rejects truncated responses', () {
      final frame = Uint8List.fromList([
        0x89,
        0,
        2,
        1,
        1,
        2,
        3,
        4,
        0,
        0,
        0,
        0,
        0x11,
      ]);

      expect(() => decodeTraceResponse(frame), throwsFormatException);
    });
  });

  test('traceResponseMatchesTag accepts the originally sent tag', () {
    final frame = Uint8List.fromList([0x89, 0, 0, 0, 1, 2, 3, 4, 0, 0, 0, 0]);

    expect(
      traceResponseMatchesTag(
        frame,
        sentTag: Uint8List.fromList([1, 2, 3, 4]),
        acknowledgedTag: Uint8List.fromList([9, 9, 9, 9]),
      ),
      isTrue,
    );
  });
}
