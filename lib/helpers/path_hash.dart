import 'dart:math' as math;
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

const int maxPathHashByteWidth = 3;

int normalizePathHashByteWidth(int width) {
  return width.clamp(1, maxPathHashByteWidth).toInt();
}

int maxPathHopCountForWidth(int width) {
  final w = normalizePathHashByteWidth(width);
  if (w == 1) return maxPathSize;
  return math.min(maxPathSize ~/ w, 0x3f);
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
  return pathLength;
}

int? encodePathLenForHashWidth(int hopCount, int hashByteWidth) {
  final w = normalizePathHashByteWidth(hashByteWidth);
  if (hopCount < 0 || hopCount > maxPathHopCountForWidth(w)) return null;
  if (w == 1 && hopCount == maxPathSize) return maxPathSize;
  return ((w - 1) << 6) | hopCount;
}

int decodePathHashWidth(int pathLenRaw) {
  if (pathLenRaw == 0xff) return 1;
  return normalizePathHashByteWidth(((pathLenRaw >> 6) & 0x03) + 1);
}

int decodePathHopCount(int pathLenRaw) {
  if (pathLenRaw == 0xff) return -1;
  if (pathLenRaw == maxPathSize) return maxPathSize;
  return pathLenRaw & 0x3f;
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
