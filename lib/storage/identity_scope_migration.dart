import 'package:shared_preferences/shared_preferences.dart';

import 'prefs_manager.dart';

/// Copies app data scoped to one companion identity into another identity.
///
/// Identity scopes use the first ten hexadecimal public-key characters, which
/// matches the storage classes throughout the app. Existing destination data
/// always wins so changing back to a previously used identity cannot overwrite
/// that identity's own history and preferences.
class IdentityScopeMigration {
  static const int _scopeLength = 10;

  static const List<String> _exactPrefixes = [
    'contacts',
    'discovered_contacts',
    'channels',
    'channel_order_',
    'contact_groups',
    'communities_v1',
    'contact_unread_count',
  ];

  static const List<String> _variablePrefixes = [
    'messages_',
    'channel_messages_',
    'channel_smaz_',
    'channel_cyr2lat_',
    'channel_region_',
    'contact_smaz_',
    'contact_cyr2lat_',
  ];

  static Future<int> copy({
    required String fromPublicKeyHex,
    required String toPublicKeyHex,
  }) async {
    final fromScope = _scopeFor(fromPublicKeyHex);
    final toScope = _scopeFor(toPublicKeyHex);
    if (fromScope == null || toScope == null || fromScope == toScope) return 0;

    final prefs = PrefsManager.instance;
    final sourceKeys = prefs.getKeys().toList(growable: false);
    var copiedCount = 0;

    for (final sourceKey in sourceKeys) {
      final destinationKey = _destinationKey(
        sourceKey,
        fromScope: fromScope,
        toScope: toScope,
      );
      if (destinationKey == null || prefs.containsKey(destinationKey)) {
        continue;
      }

      if (await _copyValue(prefs, sourceKey, destinationKey)) {
        copiedCount += 1;
      }
    }

    return copiedCount;
  }

  static String? _scopeFor(String publicKeyHex) {
    if (publicKeyHex.length < _scopeLength) return null;
    return publicKeyHex.substring(0, _scopeLength);
  }

  static String? _destinationKey(
    String sourceKey, {
    required String fromScope,
    required String toScope,
  }) {
    for (final prefix in _exactPrefixes) {
      if (sourceKey == '$prefix$fromScope') return '$prefix$toScope';
    }

    for (final prefix in _variablePrefixes) {
      final sourcePrefix = '$prefix$fromScope';
      if (sourceKey.startsWith(sourcePrefix)) {
        return '$prefix$toScope${sourceKey.substring(sourcePrefix.length)}';
      }
    }

    return null;
  }

  static Future<bool> _copyValue(
    SharedPreferences prefs,
    String sourceKey,
    String destinationKey,
  ) async {
    final value = prefs.get(sourceKey);
    return switch (value) {
      String value => prefs.setString(destinationKey, value),
      bool value => prefs.setBool(destinationKey, value),
      int value => prefs.setInt(destinationKey, value),
      double value => prefs.setDouble(destinationKey, value),
      List<String> value => prefs.setStringList(destinationKey, value),
      _ => false,
    };
  }
}
