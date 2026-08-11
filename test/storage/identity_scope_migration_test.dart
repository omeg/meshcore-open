import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/storage/identity_scope_migration.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

void main() {
  const oldPublicKey = '0123456789abcdef';
  const oldScope = '0123456789';
  const newPublicKey = 'abcdef0123456789';
  const newScope = 'abcdef0123';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  test(
    'copies every identity-scoped storage family to the new scope',
    () async {
      final prefs = PrefsManager.instance;
      final scopedValues = <String, Object>{
        'contacts$oldScope': '[{"publicKey":"contact"}]',
        'discovered_contacts$oldScope': '[{"publicKey":"discovered"}]',
        'channels$oldScope': '[{"index":0}]',
        'channel_order_$oldScope': '[0,1]',
        'contact_groups$oldScope': '[{"id":"friends"}]',
        'communities_v1$oldScope': '[{"id":"community"}]',
        'contact_unread_count$oldScope': '{"contact":2}',
        'messages_${oldScope}contact': '[{"text":"hello"}]',
        'channel_messages_${oldScope}0': '[{"text":"channel"}]',
        'channel_smaz_${oldScope}0': true,
        'channel_cyr2lat_${oldScope}0': true,
        'channel_cyr2lat_${oldScope}profile_0': 'profile',
        'channel_region_${oldScope}0': 'region',
        'contact_smaz_${oldScope}contact': true,
        'contact_cyr2lat_${oldScope}contact': true,
        'contact_cyr2lat_${oldScope}profile_contact': 'profile',
      };
      for (final entry in scopedValues.entries) {
        switch (entry.value) {
          case String value:
            await prefs.setString(entry.key, value);
          case bool value:
            await prefs.setBool(entry.key, value);
        }
      }
      await prefs.setString('app_settings', '{"theme_mode":"dark"}');
      await prefs.setString('regions', '["region"]');

      final copied = await IdentityScopeMigration.copy(
        fromPublicKeyHex: oldPublicKey,
        toPublicKeyHex: newPublicKey,
      );

      expect(copied, scopedValues.length);
      for (final entry in scopedValues.entries) {
        final destinationKey = entry.key.replaceFirst(oldScope, newScope);
        expect(prefs.get(destinationKey), entry.value, reason: destinationKey);
        expect(prefs.get(entry.key), entry.value, reason: entry.key);
      }
      expect(prefs.getString('app_settings'), '{"theme_mode":"dark"}');
      expect(prefs.getString('regions'), '["region"]');
    },
  );

  test('preserves data already stored for the destination identity', () async {
    final prefs = PrefsManager.instance;
    await prefs.setString('contacts$oldScope', 'old identity contacts');
    await prefs.setString('contacts$newScope', 'new identity contacts');
    await prefs.setString('messages_${oldScope}contact', 'old messages');

    final copied = await IdentityScopeMigration.copy(
      fromPublicKeyHex: oldPublicKey,
      toPublicKeyHex: newPublicKey,
    );

    expect(copied, 1);
    expect(prefs.getString('contacts$newScope'), 'new identity contacts');
    expect(prefs.getString('messages_${newScope}contact'), 'old messages');
  });

  test('does nothing for missing or unchanged storage scopes', () async {
    expect(
      await IdentityScopeMigration.copy(
        fromPublicKeyHex: oldPublicKey,
        toPublicKeyHex: oldPublicKey,
      ),
      0,
    );
    expect(
      await IdentityScopeMigration.copy(
        fromPublicKeyHex: 'short',
        toPublicKeyHex: newPublicKey,
      ),
      0,
    );
  });
}
