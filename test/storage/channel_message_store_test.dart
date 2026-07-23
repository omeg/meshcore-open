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
}
