import 'package:latlong2/latlong.dart';

import '../connector/meshcore_protocol.dart';
import 'path_hash.dart';
import '../models/contact.dart';

class PathHopResolver {
  const PathHopResolver._();

  static List<Contact?> resolve({
    required List<int> pathBytes,
    required List<Contact> contacts,
    LatLng? endpoint,
    bool resolveFromEnd = false,
    int pathHashByteWidth = 1,
  }) {
    final width = normalizePathHashByteWidth(pathHashByteWidth);
    final alignedBytes = trimPathBytesToWidth(pathBytes, width);
    final hopPrefixes = <List<int>>[];
    for (var i = 0; i < alignedBytes.length; i += width) {
      hopPrefixes.add(alignedBytes.sublist(i, i + width));
    }

    final candidatesByPrefix = <String, List<Contact>>{};
    for (final contact in contacts) {
      if (contact.publicKey.length < width) continue;
      if (contact.type != advTypeRepeater && contact.type != advTypeRoom) {
        continue;
      }
      final prefix = _prefixKey(contact.publicKey.sublist(0, width));
      candidatesByPrefix.putIfAbsent(prefix, () => <Contact>[]).add(contact);
    }
    for (final candidates in candidatesByPrefix.values) {
      candidates.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    }

    final resolved = List<Contact?>.filled(hopPrefixes.length, null);
    final indexes = resolveFromEnd
        ? List<int>.generate(
            hopPrefixes.length,
            (i) => hopPrefixes.length - 1 - i,
          )
        : List<int>.generate(hopPrefixes.length, (i) => i);
    final distance = Distance();
    var previousPosition = endpoint;

    for (final index in indexes) {
      final candidates = candidatesByPrefix[_prefixKey(hopPrefixes[index])];
      if (candidates == null || candidates.isEmpty) continue;

      var bestIndex = 0;
      if (previousPosition != null && candidates.length > 1) {
        double? nearestDistance;
        for (var i = 0; i < candidates.length; i++) {
          final position = _positionOf(candidates[i]);
          if (position == null) continue;
          final candidateDistance = distance(previousPosition, position);
          if (nearestDistance == null || candidateDistance < nearestDistance) {
            nearestDistance = candidateDistance;
            bestIndex = i;
          }
        }
      }

      final contact = candidates.removeAt(bestIndex);
      resolved[index] = contact;
      previousPosition = _positionOf(contact) ?? previousPosition;
    }

    return resolved;
  }

  static String _prefixKey(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static LatLng? _positionOf(Contact contact) {
    if (!contact.hasLocation ||
        contact.latitude == null ||
        contact.longitude == null) {
      return null;
    }
    return LatLng(contact.latitude!, contact.longitude!);
  }
}
