import 'package:flutter/foundation.dart';

import '../models/contact.dart';
import '../connector/meshcore_protocol.dart';
import 'path_hash.dart';

class PathHelper {
  static String formatHopHex(List<int> pathBytes) {
    return pathBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  static List<Uint8List> splitPathBytes(
    List<int> pathBytes, [
    int hashByteWidth = 1,
  ]) {
    final width = normalizePathHashByteWidth(hashByteWidth);
    final chunks = <Uint8List>[];
    for (var i = 0; i < pathBytes.length; i += width) {
      final end = (i + width).clamp(0, pathBytes.length).toInt();
      chunks.add(Uint8List.fromList(pathBytes.sublist(i, end)));
    }
    return chunks;
  }

  static String formatPathHex(List<int> pathBytes, [int hashByteWidth = 1]) {
    return splitPathBytes(pathBytes, hashByteWidth).map(formatHopHex).join(',');
  }

  static String formatMessagePathHex(
    List<int> pathBytes,
    int hashByteWidth, {
    Iterable<List<int>> pathVariants = const [],
    bool reverse = false,
  }) {
    List<int> selectedPath = pathBytes;
    if (selectedPath.isEmpty) {
      for (final variant in pathVariants) {
        if (variant.isNotEmpty) {
          selectedPath = variant;
          break;
        }
      }
    }

    final alignedPath = trimPathBytesToWidth(selectedPath, hashByteWidth);
    final displayPath = reverse
        ? reversePathByHop(alignedPath, hashByteWidth)
        : alignedPath;
    return formatPathHex(displayPath, hashByteWidth);
  }

  static String hopHex(int byte) {
    return byte.toRadixString(16).padLeft(2, '0').toUpperCase();
  }

  static String? hopName(int byte, List<Contact> allContacts) {
    final matches = allContacts
        .where(
          (c) =>
              c.publicKey.first == byte &&
              (c.type == advTypeRepeater || c.type == advTypeRoom),
        )
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first.name;
    return matches.map((c) => c.name).join(' | ');
  }

  static String resolvePathNames(
    List<int> pathBytes,
    List<Contact> allContacts, [
    int hashByteWidth = 1,
  ]) {
    final width = normalizePathHashByteWidth(hashByteWidth);
    if (width == 1) {
      return pathBytes
          .map((b) => hopName(b, allContacts) ?? hopHex(b))
          .join(' \u2192 ');
    }
    return splitPathBytes(pathBytes, width)
        .map((hopBytes) {
          final hex = formatHopHex(hopBytes);
          final matches = allContacts
              .where(
                (c) =>
                    c.publicKey.length >= hopBytes.length &&
                    listEquals(
                      c.publicKey.sublist(0, hopBytes.length),
                      hopBytes,
                    ) &&
                    (c.type == advTypeRepeater || c.type == advTypeRoom),
              )
              .toList();
          if (matches.isEmpty) return hex;
          if (matches.length == 1) return matches.first.name;
          return matches.map((c) => c.name).join(' | ');
        })
        .join(' \u2192 ');
  }
}
