import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/storage/channel_message_store.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test('persists channel message flood scope metadata', () async {
    final store = ChannelMessageStore()..setPublicKeyHex = '0123456789abcdef';
    final message = ChannelMessage(
      senderName: 'Node',
      text: 'hello',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      channelIndex: 2,
      floodScope: 'de-mitte',
      floodScopeCode: 0x3878,
    );

    await store.saveChannelMessages(2, [message]);
    final loaded = await store.loadChannelMessages(2);

    expect(loaded, hasLength(1));
    expect(loaded.single.floodScope, 'de-mitte');
    expect(loaded.single.floodScopeCode, 0x3878);
  });

  test('persists channel message arrival timestamp', () async {
    final store = ChannelMessageStore()..setPublicKeyHex = '0123456789abcdef';
    final sentAt = DateTime(2090, 8, 16, 19, 54);
    final receivedAt = DateTime(2026, 8, 19, 20, 14);
    final message = ChannelMessage(
      senderName: 'Bad clock',
      text: 'hello',
      timestamp: sentAt,
      receivedAt: receivedAt,
      isOutgoing: false,
      status: ChannelMessageStatus.sent,
      channelIndex: 3,
    );

    await store.saveChannelMessages(3, [message]);
    final loaded = await store.loadChannelMessages(3);

    expect(loaded.single.timestamp, sentAt);
    expect(loaded.single.receivedAt, receivedAt);
    expect(loaded.single.orderTimestamp, receivedAt);
  });

  test('restores an orphaned pending send as failed', () async {
    final store = ChannelMessageStore()..setPublicKeyHex = '0123456789abcdef';
    final message = ChannelMessage(
      senderName: 'Me',
      text: 'unfinished',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      isOutgoing: true,
      status: ChannelMessageStatus.pending,
      channelIndex: 1,
    );

    await store.saveChannelMessages(1, [message]);
    final loaded = await store.loadChannelMessages(1);

    expect(loaded.single.status, ChannelMessageStatus.failed);
  });

  test('persists verified channel reply metadata', () async {
    final store = ChannelMessageStore()..setPublicKeyHex = '0123456789abcdef';
    final message = ChannelMessage(
      senderName: 'Me',
      text: 'reply',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1000),
      isOutgoing: true,
      channelIndex: 2,
      replyToMessageId: 'original-id',
      replyToSenderName: 'Node',
      replyToText: 'original text',
      isReplyTargetVerified: true,
    );

    await store.saveChannelMessages(2, [message]);
    final loaded = await store.loadChannelMessages(2);

    expect(loaded.single.replyToMessageId, 'original-id');
    expect(loaded.single.replyToSenderName, 'Node');
    expect(loaded.single.replyToText, 'original text');
    expect(loaded.single.isReplyTargetVerified, isTrue);
  });

  test('legacy channel reply metadata is unverified', () async {
    SharedPreferences.setMockInitialValues({
      'channel_messages_01234567892':
          '[{"senderName":"Node","text":"reply","timestamp":1000,'
          '"isOutgoing":false,"status":1,"channelIndex":2,'
          '"replyToMessageId":"guessed-id","replyToSenderName":"Other",'
          '"replyToText":"guessed text"}]',
    });
    PrefsManager.reset();
    await PrefsManager.initialize();
    final store = ChannelMessageStore()..setPublicKeyHex = '0123456789abcdef';

    final loaded = await store.loadChannelMessages(2);

    expect(loaded.single.isReplyTargetVerified, isFalse);
  });
}
