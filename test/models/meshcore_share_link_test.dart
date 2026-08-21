import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/link_handler.dart';
import 'package:meshcore_open/models/channel.dart';
import 'package:meshcore_open/models/meshcore_share_link.dart';

void main() {
  const publicKeyHex =
      '4563b1621b584de5e922de7f75c01d3ffafeb5e7450406065c15a61e016aed09';
  const secretHex = 'cff8d9106784fcb460341fe32b43cb9f';

  group('MeshCore contact share links', () {
    test('parses and regenerates documented contact URI', () {
      final parsed = MeshCoreShareLink.tryParse(
        'meshcore://contact/add?name=Daniel+WebUI&public_key=$publicKeyHex&type=1',
      );

      expect(parsed, isA<MeshCoreContactShareLink>());
      final contact = parsed! as MeshCoreContactShareLink;
      expect(contact.name, 'Daniel WebUI');
      expect(contact.type, advTypeChat);
      expect(pubKeyToHex(contact.publicKey!), publicKeyHex);
      expect(MeshCoreShareLink.tryParse(contact.toUriString()), isNotNull);
    });

    test('parses compact contact forms with and without an empty path', () {
      for (final text in [
        '<$publicKeyHex:1:Daniel>',
        '<$publicKeyHex::2:PL-TK Ur-Nal:gun::high_brightness:>',
      ]) {
        final parsed = MeshCoreShareLink.tryParse(text);
        expect(parsed, isA<MeshCoreContactShareLink>(), reason: text);
      }

      final repeater =
          MeshCoreShareLink.tryParse(
                '<$publicKeyHex::2:PL-TK Ur-Nal:gun::high_brightness:>',
              )!
              as MeshCoreContactShareLink;
      expect(repeater.name, 'PL-TK Ur-Nal');
      expect(repeater.type, advTypeRepeater);
    });

    test('parses a raw public key as a chat contact', () {
      final parsed = MeshCoreShareLink.tryParse(publicKeyHex);

      expect(parsed, isA<MeshCoreContactShareLink>());
      final contact = parsed! as MeshCoreContactShareLink;
      expect(contact.name, '4563b162..016aed09');
      expect(contact.type, advTypeChat);
      expect(pubKeyToHex(contact.publicKey!), publicKeyHex);
    });

    test('parses legacy hex advertisement and extracts its preview', () {
      final advert = Uint8List.fromList([
        (payloadTypeADVERT << 2) | 1,
        0,
        ...hex2Uint8List(publicKeyHex),
        1,
        2,
        3,
        4,
        ...List<int>.filled(64, 0),
        0x80 | advTypeRoom,
        ...utf8.encode('SP7UNR room'),
        0,
      ]);
      final uri = 'meshcore://${pubKeyToHex(advert)}';

      final parsed = MeshCoreShareLink.tryParse(uri);

      expect(parsed, isA<MeshCoreContactShareLink>());
      final contact = parsed! as MeshCoreContactShareLink;
      expect(contact.advertData, advert);
      expect(contact.name, 'SP7UNR room');
      expect(contact.type, advTypeRoom);
      expect(pubKeyToHex(contact.publicKey!), publicKeyHex);
    });

    test('rejects invalid public keys and contact types', () {
      expect(
        MeshCoreShareLink.tryParse(
          'meshcore://contact/add?name=Alice&public_key=1234&type=1',
        ),
        isNull,
      );
      expect(
        MeshCoreShareLink.tryParse(
          'meshcore://contact/add?name=Alice&public_key=$publicKeyHex&type=9',
        ),
        isNull,
      );
    });
  });

  group('MeshCore channel share links', () {
    test('parses encoded names, secrets, and optional region scope', () {
      final parsed = MeshCoreShareLink.tryParse(
        'meshcore://channel/add?name=%23kielce&secret=$secretHex&region_scope=pl-south',
      );

      expect(parsed, isA<MeshCoreChannelShareLink>());
      final channel = parsed! as MeshCoreChannelShareLink;
      expect(channel.name, '#kielce');
      expect(channel.secretHex, secretHex);
      expect(channel.regionScope, 'pl-south');
      expect(channel.isPrivate, isFalse);
      expect(channel.toUriString(), contains('name=%23kielce'));
    });

    test('only arbitrary private channel names are editable', () {
      final private = MeshCoreChannelShareLink(
        name: 'Testy',
        secret: Channel.parsePskHex(secretHex),
      );
      final hashtag = MeshCoreChannelShareLink(
        name: '#testy',
        secret: Channel.parsePskHex(secretHex),
      );
      final public = MeshCoreChannelShareLink(
        name: 'Public',
        secret: Channel.parsePskHex(Channel.publicChannelPsk),
      );

      expect(private.isPrivate, isTrue);
      expect(hashtag.isPrivate, isFalse);
      expect(public.isPrivate, isFalse);
    });

    test('rejects malformed secrets', () {
      expect(
        MeshCoreShareLink.tryParse(
          'meshcore://channel/add?name=Testy&secret=1234',
        ),
        isNull,
      );
    });
  });

  test('finds multiple supported links and excludes sentence punctuation', () {
    final text =
        'Join meshcore://channel/add?name=Testy&secret=$secretHex. '
        'Then add <$publicKeyHex:3:SP7UNR room>.';

    final matches = MeshCoreShareLink.findInText(text);

    expect(matches, hasLength(2));
    expect(matches.first.text, endsWith(secretHex));
    expect(matches.last.link, isA<MeshCoreContactShareLink>());
  });

  test('message linkifier turns share links into tappable elements', () {
    final uri = 'meshcore://channel/add?name=Testy&secret=$secretHex';
    final elements = const MeshCoreLinkifier().parse([
      TextElement('Join $uri now'),
    ], const LinkifyOptions());

    final links = elements.whereType<LinkableElement>().toList();
    expect(links, hasLength(1));
    expect(links.single.url, uri);
  });
}
