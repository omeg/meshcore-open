import 'package:flutter/foundation.dart';

import 'path_hash.dart';
import 'path_helper.dart';

class TraceRequestEncoding {
  final Uint8List payload;
  final int flags;
  final int hashByteWidth;

  const TraceRequestEncoding({
    required this.payload,
    required this.flags,
    required this.hashByteWidth,
  });
}

class TraceResponsePayload {
  final List<Uint8List> path;
  final List<double> snr;
  final int hashByteWidth;

  const TraceResponsePayload({
    required this.path,
    required this.snr,
    required this.hashByteWidth,
  });
}

int traceHashByteWidth(int sourceHashByteWidth) {
  final width = normalizePathHashByteWidth(sourceHashByteWidth);
  return width == 1 ? 1 : 2;
}

Uint8List reverseTraceSourcePath(Uint8List pathBytes, int sourceHashByteWidth) {
  final hops = PathHelper.splitPathBytes(pathBytes, sourceHashByteWidth);
  return Uint8List.fromList(hops.reversed.expand((hop) => hop).toList());
}

TraceRequestEncoding? encodeTraceRequestPath(
  Uint8List sourcePath, {
  required int sourceHashByteWidth,
  Uint8List? targetPublicKey,
  bool mirrorAroundTarget = false,
}) {
  final sourceWidth = normalizePathHashByteWidth(sourceHashByteWidth);
  if (sourcePath.length % sourceWidth != 0) return null;

  final traceWidth = traceHashByteWidth(sourceWidth);
  final outbound = <Uint8List>[];
  for (final hop in PathHelper.splitPathBytes(sourcePath, sourceWidth)) {
    if (hop.length < traceWidth) return null;
    outbound.add(Uint8List.fromList(hop.sublist(0, traceWidth)));
  }

  if (mirrorAroundTarget && targetPublicKey != null) {
    if (targetPublicKey.length < traceWidth) return null;
    final target = Uint8List.fromList(targetPublicKey.sublist(0, traceWidth));
    if (outbound.isEmpty || !listEquals(outbound.last, target)) {
      outbound.add(target);
    }
  }

  final encoded = <Uint8List>[...outbound];
  if (mirrorAroundTarget && outbound.length > 1) {
    encoded.addAll(outbound.sublist(0, outbound.length - 1).reversed);
  }

  return TraceRequestEncoding(
    payload: Uint8List.fromList(encoded.expand((hop) => hop).toList()),
    flags: traceWidth == 1 ? 0 : 1,
    hashByteWidth: traceWidth,
  );
}

TraceResponsePayload decodeTraceResponse(Uint8List frame) {
  if (frame.length < 12) {
    throw const FormatException('Trace response is too short');
  }

  final pathLenByte = frame[2];
  final flags = frame[3];
  var width = 1 << (flags & 0x03);
  var pathLength = pathLenByte == 0xFF ? 0 : pathLenByte;
  final payloadBytes = frame.length - 12;

  // Compatibility with firmware variants that packed hop count and width
  // into the path-length byte.
  if (pathLength > payloadBytes && (pathLenByte & 0xC0) != 0) {
    final packedWidth = ((pathLenByte & 0xC0) >> 6) + 1;
    final packedLength = (pathLenByte & 0x3F) * packedWidth;
    if (packedLength <= payloadBytes) {
      width = packedWidth;
      pathLength = packedLength;
    }
  }

  if (width != 1 && width != 2 && width != 4) {
    throw FormatException('Unsupported trace hash width: $width');
  }
  if (pathLength % width != 0) {
    throw const FormatException('Trace path is not aligned to its hash width');
  }

  final snrCount = pathLength ~/ width + 1;
  if (pathLength + snrCount > payloadBytes) {
    throw const FormatException('Trace response payload is truncated');
  }

  final pathBytes = frame.sublist(12, 12 + pathLength);
  final snrOffset = 12 + pathLength;
  return TraceResponsePayload(
    path: PathHelper.splitPathBytes(pathBytes, width),
    snr: frame
        .sublist(snrOffset, snrOffset + snrCount)
        .map((value) => value.toSigned(8).toDouble() / 4)
        .toList(),
    hashByteWidth: width,
  );
}

bool traceResponseMatchesTag(
  Uint8List frame, {
  Uint8List? sentTag,
  Uint8List? acknowledgedTag,
}) {
  if (frame.length < 8) return false;
  final responseTag = frame.sublist(4, 8);
  return (sentTag != null && listEquals(responseTag, sentTag)) ||
      (acknowledgedTag != null && listEquals(responseTag, acknowledgedTag));
}
