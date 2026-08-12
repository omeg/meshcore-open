import 'dart:math' as math;
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

const int maxPathHashByteWidth = 3;
const int pathLenHopCountMask = 0x3f;
const int pathLenHashWidthShift = 6;
const int pathLenHashWidthMask = 0x03;

int normalizePathHashByteWidth(int width) {
  return width.clamp(1, maxPathHashByteWidth).toInt();
}

int maxPathHopCountForWidth(int width) {
  final w = normalizePathHashByteWidth(width);
  if (w == 1) return maxPathSize;
  return math.min(maxPathSize ~/ w, 0x3f);
}

bool isValidPacketPathLen(int pathLenRaw) {
  // Mirrors firmware Packet::isValidPathLen(): low 6 bits are hop count,
  // high 2 bits encode hash width minus one, and width mode 3 is reserved.
  final hashCount = pathLenRaw & pathLenHopCountMask;
  final hashSize =
      ((pathLenRaw >> pathLenHashWidthShift) & pathLenHashWidthMask) + 1;
  if (hashSize > maxPathHashByteWidth) return false;
  return hashCount * hashSize <= maxPathSize;
}

int pathHopCountForBytes(int byteCount, int hashByteWidth) {
  if (byteCount <= 0) return 0;
  final w = normalizePathHashByteWidth(hashByteWidth);
  return byteCount ~/ w;
}

int pathHopCountForBytesCeil(int byteCount, int hashByteWidth) {
  if (byteCount <= 0) return 0;
  final w = normalizePathHashByteWidth(hashByteWidth);
  return (byteCount + w - 1) ~/ w;
}

bool pathBytesAlignToWidth(List<int> pathBytes, int hashByteWidth) {
  final w = normalizePathHashByteWidth(hashByteWidth);
  return pathBytes.length % w == 0;
}

int alignedPathByteCount(int byteCount, int hashByteWidth) {
  if (byteCount <= 0) return 0;
  final w = normalizePathHashByteWidth(hashByteWidth);
  return byteCount - (byteCount % w);
}

Uint8List trimPathBytesToWidth(List<int> pathBytes, int hashByteWidth) {
  final alignedLength = alignedPathByteCount(pathBytes.length, hashByteWidth);
  if (alignedLength == pathBytes.length) return Uint8List.fromList(pathBytes);
  if (alignedLength == 0) return Uint8List(0);
  return Uint8List.fromList(pathBytes.sublist(0, alignedLength));
}

int? normalizePathLengthWithBytes(
  int? pathLength,
  int pathByteCount,
  int hashByteWidth,
) {
  if (pathLength == null || pathLength < 0 || pathByteCount <= 0) {
    return pathLength;
  }
  final w = normalizePathHashByteWidth(hashByteWidth);
  if (w <= 1) return pathLength;
  final observedHopCount = pathHopCountForBytes(pathByteCount, w);
  if (observedHopCount <= 0) return pathLength;
  if (pathLength == pathByteCount || pathLength == observedHopCount * w) {
    return observedHopCount;
  }
  if (pathLength > maxPathHopCountForWidth(w)) {
    final encodedWidth = decodePathHashWidth(pathLength);
    final encodedHopCount = decodePathHopCount(pathLength);
    final encodedByteLen = decodePathByteLen(pathLength);
    if (encodedWidth == w &&
        encodedHopCount > 0 &&
        encodedByteLen > 0 &&
        encodedByteLen <= pathByteCount) {
      return observedHopCount;
    }
    return observedHopCount;
  }
  return pathLength;
}

int? encodePathLenForHashWidth(int hopCount, int hashByteWidth) {
  final w = normalizePathHashByteWidth(hashByteWidth);
  if (hopCount < 0 || hopCount > maxPathHopCountForWidth(w)) return null;
  if (hopCount == 0) return 0;
  if (w == 1 && hopCount == maxPathSize) return maxPathSize;
  return ((w - 1) << pathLenHashWidthShift) | hopCount;
}

int decodePathHashWidth(int pathLenRaw) {
  if (pathLenRaw == 0xff) return 1;
  return normalizePathHashByteWidth(
    ((pathLenRaw >> pathLenHashWidthShift) & pathLenHashWidthMask) + 1,
  );
}

int decodePathHopCount(int pathLenRaw) {
  if (pathLenRaw == 0xff) return -1;
  if (pathLenRaw == maxPathSize) return maxPathSize;
  return pathLenRaw & pathLenHopCountMask;
}

int decodeReceivedPathHopCount(int pathLenRaw) {
  if (pathLenRaw == 0xff) return 0;
  // Companion receive frames and raw radio packets always use the encoded
  // path_len layout. In that context 0x40 is a zero-hop path using two-byte
  // hashes, not the legacy 64-hop contact-record value.
  return pathLenRaw & pathLenHopCountMask;
}

int decodeReceivedPathByteLen(int pathLenRaw) {
  final hopCount = decodeReceivedPathHopCount(pathLenRaw);
  if (hopCount <= 0) return 0;
  final width = decodePathHashWidth(pathLenRaw);
  return (hopCount * width).clamp(0, maxPathSize).toInt();
}

int decodePathByteLen(int pathLenRaw) {
  final hopCount = decodePathHopCount(pathLenRaw);
  if (hopCount <= 0) return 0;
  final width = pathLenRaw == maxPathSize ? 1 : decodePathHashWidth(pathLenRaw);
  return (hopCount * width).clamp(0, maxPathSize).toInt();
}

Uint8List reversePathByHop(List<int> pathBytes, int hashByteWidth) {
  if (pathBytes.isEmpty) return Uint8List(0);
  final w = normalizePathHashByteWidth(hashByteWidth);
  final reversed = <int>[];
  for (var i = pathBytes.length; i > 0; i -= w) {
    final start = math.max(0, i - w);
    reversed.addAll(pathBytes.sublist(start, i));
  }
  return Uint8List.fromList(reversed);
}
