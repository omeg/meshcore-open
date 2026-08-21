import 'dart:convert';
import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import 'channel.dart';
import 'contact.dart';

sealed class MeshCoreShareLink {
  const MeshCoreShareLink();

  String toUriString();

  static MeshCoreShareLink? tryParse(String text) {
    final trimmed = text.trim();
    return _tryParseUri(trimmed) ??
        _tryParseCompactContact(trimmed) ??
        _tryParseRawContactPublicKey(trimmed);
  }

  static List<MeshCoreShareLinkMatch> findInText(String text) {
    final matches = <MeshCoreShareLinkMatch>[];
    final candidates = RegExp(
      r'meshcore://[^\s<>\[\](){}]+|<[0-9a-fA-F]{64}:[^>\r\n]+>',
      caseSensitive: false,
    );

    for (final match in candidates.allMatches(text)) {
      var candidate = match.group(0)!;
      var link = tryParse(candidate);
      while (link == null &&
          candidate.isNotEmpty &&
          _trailingPunctuation.hasMatch(candidate[candidate.length - 1])) {
        candidate = candidate.substring(0, candidate.length - 1);
        link = tryParse(candidate);
      }
      if (link == null) continue;
      matches.add(
        MeshCoreShareLinkMatch(
          start: match.start,
          end: match.start + candidate.length,
          text: candidate,
          link: link,
        ),
      );
    }
    return matches;
  }

  static final RegExp _trailingPunctuation = RegExp(r'[.,;:!?]');

  static MeshCoreShareLink? _tryParseUri(String text) {
    if (!text.toLowerCase().startsWith('meshcore://')) return null;

    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme.toLowerCase() != 'meshcore') return null;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (host == 'contact' && path == '/add') {
      final name = uri.queryParameters['name']?.trim();
      final publicKeyHex = uri.queryParameters['public_key'];
      final type = int.tryParse(uri.queryParameters['type'] ?? '');
      if (name == null ||
          name.isEmpty ||
          !_isHex(publicKeyHex, expectedLength: pubKeySize * 2) ||
          type == null ||
          type < advTypeChat ||
          type > advTypeSensor) {
        return null;
      }
      return MeshCoreContactShareLink(
        name: name,
        publicKey: hex2Uint8List(publicKeyHex!),
        type: type,
      );
    }

    if (host == 'channel' && path == '/add') {
      final name = uri.queryParameters['name']?.trim();
      final secretHex = uri.queryParameters['secret'];
      if (name == null ||
          name.isEmpty ||
          !_isHex(secretHex, expectedLength: 32)) {
        return null;
      }
      final regionScope = uri.queryParameters['region_scope']?.trim();
      return MeshCoreChannelShareLink(
        name: name,
        secret: Channel.parsePskHex(secretHex!),
        regionScope: regionScope == null || regionScope.isEmpty
            ? null
            : regionScope,
      );
    }

    // Legacy contact business cards are raw advertisement packets encoded as
    // hex immediately after the scheme: meshcore://<hex>.
    if (uri.path.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        _isHex(uri.host) &&
        uri.host.length >= 196) {
      final advertData = hex2Uint8List(uri.host);
      final preview = _tryDecodeAdvert(advertData);
      return MeshCoreContactShareLink(
        name: preview?.name,
        publicKey: preview?.publicKey,
        type: preview?.type,
        advertData: advertData,
      );
    }

    return null;
  }

  static MeshCoreShareLink? _tryParseCompactContact(String text) {
    final match = RegExp(r'^<([0-9a-fA-F]{64}):(.*)>$').firstMatch(text);
    if (match == null) return null;

    final fields = match.group(2)!.split(':');
    int typeIndex;
    final firstType = int.tryParse(fields.first);
    if (firstType != null &&
        firstType >= advTypeChat &&
        firstType <= advTypeSensor) {
      typeIndex = 0;
    } else if (fields.length >= 3) {
      final secondType = int.tryParse(fields[1]);
      if (secondType == null ||
          secondType < advTypeChat ||
          secondType > advTypeSensor) {
        return null;
      }
      typeIndex = 1;
    } else {
      return null;
    }

    if (fields.length <= typeIndex + 1) return null;
    final name = fields[typeIndex + 1].trim();
    if (name.isEmpty) return null;
    return MeshCoreContactShareLink(
      name: name,
      publicKey: hex2Uint8List(match.group(1)!),
      type: int.parse(fields[typeIndex]),
    );
  }

  static MeshCoreShareLink? _tryParseRawContactPublicKey(String text) {
    if (!_isHex(text, expectedLength: pubKeySize * 2)) return null;

    // A bare public key carries no display metadata. Treat it as a chat
    // contact and use the same concise key representation shown in the UI as
    // its editable contact name.
    final name = '${text.substring(0, 8)}..${text.substring(text.length - 8)}';
    return MeshCoreContactShareLink(
      name: name,
      publicKey: hex2Uint8List(text),
      type: advTypeChat,
    );
  }

  static bool _isHex(String? value, {int? expectedLength}) {
    if (value == null || value.isEmpty || value.length.isOdd) return false;
    if (expectedLength != null && value.length != expectedLength) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  static _AdvertPreview? _tryDecodeAdvert(Uint8List data) {
    try {
      var offset = 0;
      final header = data[offset++];
      final routeType = header & 0x03;
      final payloadType = (header >> 2) & 0x0F;
      if (payloadType != payloadTypeADVERT) return null;
      if (routeType == 0 || routeType == 3) offset += 4;
      if (offset >= data.length) return null;

      final encodedPathLength = data[offset++];
      final hashWidth = (encodedPathLength >> 6) + 1;
      if (hashWidth > 3) return null;
      offset += (encodedPathLength & 0x3F) * hashWidth;

      // Public key + timestamp + signature + flags.
      if (data.length - offset < pubKeySize + 4 + 64 + 1) return null;
      final publicKey = Uint8List.fromList(
        data.sublist(offset, offset + pubKeySize),
      );
      offset += pubKeySize + 4 + 64;
      final flags = data[offset++];
      final type = flags & 0x0F;
      if (type < advTypeChat || type > advTypeSensor) return null;
      if ((flags & 0x10) != 0) offset += 8;
      if (offset > data.length) return null;

      var name = '';
      if ((flags & 0x80) != 0 && offset < data.length) {
        final end = data.indexOf(0, offset);
        final nameBytes = data.sublist(offset, end == -1 ? data.length : end);
        name = utf8.decode(nameBytes, allowMalformed: true).trim();
      }
      return _AdvertPreview(
        name: name.isEmpty ? null : name,
        publicKey: publicKey,
        type: type,
      );
    } on RangeError {
      return null;
    }
  }
}

class MeshCoreContactShareLink extends MeshCoreShareLink {
  final String? name;
  final Uint8List? publicKey;
  final int? type;
  final Uint8List? advertData;

  const MeshCoreContactShareLink({
    this.name,
    this.publicKey,
    this.type,
    this.advertData,
  });

  factory MeshCoreContactShareLink.fromContact(Contact contact) {
    return MeshCoreContactShareLink(
      name: contact.name,
      publicKey: Uint8List.fromList(contact.publicKey),
      type: contact.type,
    );
  }

  bool get hasStructuredContact =>
      name != null && publicKey != null && type != null;

  Contact toContact() {
    if (!hasStructuredContact) {
      throw const FormatException('Contact details are unavailable');
    }
    return Contact(
      publicKey: Uint8List.fromList(publicKey!),
      name: name!,
      type: type!,
      pathLength: 0,
      path: Uint8List(0),
      lastSeen: DateTime.now(),
    );
  }

  @override
  String toUriString() {
    if (hasStructuredContact) {
      return Uri(
        scheme: 'meshcore',
        host: 'contact',
        path: '/add',
        queryParameters: {
          'name': name!,
          'public_key': pubKeyToHex(publicKey!),
          'type': type!.toString(),
        },
      ).toString();
    }
    if (advertData != null) {
      return 'meshcore://${pubKeyToHex(advertData!)}';
    }
    throw const FormatException('Contact link has no data');
  }
}

class MeshCoreChannelShareLink extends MeshCoreShareLink {
  final String name;
  final Uint8List secret;
  final String? regionScope;

  const MeshCoreChannelShareLink({
    required this.name,
    required this.secret,
    this.regionScope,
  });

  factory MeshCoreChannelShareLink.fromChannel(
    Channel channel, {
    String? regionScope,
  }) {
    return MeshCoreChannelShareLink(
      name: channel.name,
      secret: Uint8List.fromList(channel.psk),
      regionScope: regionScope,
    );
  }

  String get secretHex => Channel.formatPskHex(secret);

  bool get isPrivate =>
      secretHex != Channel.publicChannelPsk && !name.startsWith('#');

  @override
  String toUriString() {
    return Uri(
      scheme: 'meshcore',
      host: 'channel',
      path: '/add',
      queryParameters: {
        'name': name,
        'secret': secretHex,
        if (regionScope != null && regionScope!.isNotEmpty)
          'region_scope': regionScope!,
      },
    ).toString();
  }
}

class MeshCoreShareLinkMatch {
  final int start;
  final int end;
  final String text;
  final MeshCoreShareLink link;

  const MeshCoreShareLinkMatch({
    required this.start,
    required this.end,
    required this.text,
    required this.link,
  });
}

class _AdvertPreview {
  final String? name;
  final Uint8List publicKey;
  final int type;

  const _AdvertPreview({
    required this.name,
    required this.publicKey,
    required this.type,
  });
}
