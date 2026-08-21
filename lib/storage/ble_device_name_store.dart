import 'dart:convert';

import 'prefs_manager.dart';

/// Persists the node name learned from SELF_INFO for each BLE device ID.
class BleDeviceNameStore {
  static const String _key = 'ble_device_names';

  Map<String, String> loadNames() {
    final encoded = PrefsManager.instance.getString(_key);
    if (encoded == null) return <String, String>{};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, String>{};

      final names = <String, String>{};
      for (final entry in decoded.entries) {
        final deviceId = entry.key.toString().trim();
        final name = entry.value is String
            ? (entry.value as String).trim()
            : '';
        if (deviceId.isNotEmpty && name.isNotEmpty) {
          names[deviceId] = name;
        }
      }
      return names;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> saveNames(Map<String, String> names) async {
    await PrefsManager.instance.setString(_key, jsonEncode(names));
  }
}
