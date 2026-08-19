import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage/prefs_manager.dart';
import '../utils/app_logger.dart';
import 'state_sync_backend.dart';

class StateSyncService extends ChangeNotifier {
  static const String _enabledKey = 'state_sync_enabled';
  static const String _folderIdKey = 'state_sync_folder_id';
  static const String _folderNameKey = 'state_sync_folder_name';
  static const String _folderPathKey = 'state_sync_folder_path';
  static const String _bundleAppId = 'meshcore-open';
  static const int _schemaVersion = 1;
  static const Duration _exportDebounce = Duration(seconds: 2);

  final StateSyncBackend _backend;
  Timer? _exportTimer;
  String? _pendingExportScope;
  bool _exportInFlight = false;

  StateSyncService({StateSyncBackend? backend})
    : _backend = backend ?? StateSyncBackend();

  bool _enabled = false;
  String? _folderId;
  String? _folderName;
  String? _folderPath;

  bool get isSupported => _backend.isSupported;
  bool get isEnabled => _enabled && hasFolder && isSupported;
  bool get hasFolder => _folderId != null && _folderId!.isNotEmpty;
  String? get folderName => _folderName;
  String? get folderPath => _folderPath ?? _folderName;

  Future<void> initialize() async {
    final prefs = PrefsManager.instance;
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _folderId = prefs.getString(_folderIdKey);
    _folderName = prefs.getString(_folderNameKey);
    _folderPath = prefs.getString(_folderPathKey);
    if (!isSupported) {
      _enabled = false;
    }
  }

  Future<bool> pickFolder() async {
    if (!isSupported) return false;
    final folder = await _backend.pickFolder();
    if (folder == null) return false;
    _folderId = folder.id;
    _folderName = folder.name;
    _folderPath = folder.displayPath;
    _enabled = true;
    final prefs = PrefsManager.instance;
    await prefs.setString(_folderIdKey, folder.id);
    await prefs.setString(_folderNameKey, folder.name);
    await prefs.setString(_folderPathKey, folder.displayPath);
    await prefs.setBool(_enabledKey, true);
    notifyListeners();
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled && isSupported && hasFolder;
    await PrefsManager.instance.setBool(_enabledKey, _enabled);
    notifyListeners();
  }

  Future<void> clearFolder() async {
    _enabled = false;
    _folderId = null;
    _folderName = null;
    _folderPath = null;
    final prefs = PrefsManager.instance;
    await prefs.remove(_enabledKey);
    await prefs.remove(_folderIdKey);
    await prefs.remove(_folderNameKey);
    await prefs.remove(_folderPathKey);
    notifyListeners();
  }

  Future<bool> importForNode(String selfPublicKeyHex) async {
    final scope = _scopeFor(selfPublicKeyHex);
    final folderId = _folderId;
    if (!isEnabled || folderId == null || scope.isEmpty) return false;
    try {
      if (!await _backend.folderExists(folderId)) return false;
      final bundle = await _backend.readJson(folderId, _bundleName(scope));
      if (bundle == null || bundle['appId'] != _bundleAppId) return false;
      if (bundle['schemaVersion'] != _schemaVersion) return false;
      if (bundle['scope'] != scope) return false;
      final remoteKeys = bundle['keys'];
      if (remoteKeys is! Map) return false;

      var changed = false;
      final prefs = PrefsManager.instance;
      for (final entry in remoteKeys.entries) {
        final key = entry.key.toString();
        if (!_shouldSyncKey(key, scope)) continue;
        final value = entry.value;
        if (value is! Map) continue;
        changed =
            await _mergeKey(scope, key, Map<String, dynamic>.from(value)) ||
            changed;
      }

      if (changed) {
        await prefs.setInt(
          'state_sync_last_imported_$scope',
          DateTime.now().millisecondsSinceEpoch,
        );
        await exportForNode(selfPublicKeyHex);
      }
      return changed;
    } catch (e) {
      appLogger.warn('State sync import failed: $e', tag: 'StateSync');
      return false;
    }
  }

  void scheduleExportForNode(String selfPublicKeyHex) {
    if (!isEnabled) return;
    final scope = _scopeFor(selfPublicKeyHex);
    if (scope.isEmpty) return;
    _pendingExportScope = scope;
    _exportTimer?.cancel();
    _exportTimer = Timer(_exportDebounce, () {
      final pending = _pendingExportScope;
      if (pending == null) return;
      unawaited(exportForNode(pending));
    });
  }

  Future<void> flushPendingExport() async {
    final pending = _pendingExportScope;
    _exportTimer?.cancel();
    _pendingExportScope = null;
    if (pending != null) {
      await exportForNode(pending);
    }
  }

  Future<void> exportForNode(String selfPublicKeyHex) async {
    final scope = _scopeFor(selfPublicKeyHex);
    final folderId = _folderId;
    if (!isEnabled || folderId == null || scope.isEmpty || _exportInFlight) {
      return;
    }
    _exportInFlight = true;
    try {
      if (!await _backend.folderExists(folderId)) return;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final prefs = PrefsManager.instance;
      final keys = <String, Map<String, dynamic>>{};
      for (final key in prefs.getKeys()) {
        if (!_shouldSyncKey(key, scope)) continue;
        final encoded = _encodePrefValue(prefs, key, scope);
        if (encoded != null) keys[key] = encoded;
      }

      // A sync folder can contain newer state written by another device.
      // Merge it into this export before overwriting the shared bundle so a
      // smaller local cache cannot erase the remote contact/message history.
      final existing = await _backend.readJson(folderId, _bundleName(scope));
      _mergeExistingBundleIntoExport(scope, keys, existing);

      final bundle = {
        'schemaVersion': _schemaVersion,
        'appId': _bundleAppId,
        'scope': scope,
        'updatedAt': now,
        'keys': keys,
      };
      await _backend.writeJson(folderId, _bundleName(scope), bundle);
      await prefs.setInt('state_sync_last_exported_$scope', now);
      appLogger.info('Exported state sync bundle for $scope', tag: 'StateSync');
    } catch (e) {
      appLogger.warn('State sync export failed: $e', tag: 'StateSync');
    } finally {
      _exportInFlight = false;
      _pendingExportScope = null;
    }
  }

  String _scopeFor(String selfPublicKeyHex) {
    if (selfPublicKeyHex.length >= 10) return selfPublicKeyHex.substring(0, 10);
    return '';
  }

  String _bundleName(String scope) => 'meshcore-open-state-$scope.json';

  void _mergeExistingBundleIntoExport(
    String scope,
    Map<String, Map<String, dynamic>> localKeys,
    Map<String, dynamic>? existingBundle,
  ) {
    if (existingBundle == null ||
        existingBundle['appId'] != _bundleAppId ||
        existingBundle['schemaVersion'] != _schemaVersion ||
        existingBundle['scope'] != scope) {
      return;
    }
    final remoteKeys = existingBundle['keys'];
    if (remoteKeys is! Map) return;

    for (final entry in remoteKeys.entries) {
      final key = entry.key.toString();
      if (!_shouldSyncKey(key, scope) || entry.value is! Map) continue;
      final remote = Map<String, dynamic>.from(entry.value as Map);
      final local = localKeys[key];
      if (local == null) {
        localKeys[key] = remote;
        continue;
      }
      if (!_isMergeableStringKey(key, scope) ||
          local['type'] != 'string' ||
          remote['type'] != 'string' ||
          local['value'] is! String ||
          remote['value'] is! String) {
        continue;
      }
      localKeys[key] = {
        'type': 'string',
        'value': _mergeStringValue(
          scope,
          key,
          local['value'] as String,
          remote['value'] as String,
        ),
      };
    }
  }

  bool _isMergeableStringKey(String key, String scope) {
    return key == 'contacts$scope' ||
        key == 'discovered_contacts$scope' ||
        key.startsWith('messages_$scope') ||
        key.startsWith('channel_messages_$scope') ||
        key == 'channels$scope' ||
        key == 'contact_groups$scope';
  }

  bool _shouldSyncKey(String key, String scope) {
    if (key == 'app_settings') return true;
    if (key.startsWith('state_sync_')) return false;
    if (key == 'pending_messages' ||
        key == 'repeater_passwords' ||
        key == 'repeater_auto_clock_sync_after_login') {
      return false;
    }
    if (key.startsWith('contact_unread_count')) return false;
    if (key.startsWith('messages_$scope')) return true;
    if (key.startsWith('channel_messages_$scope')) return true;
    if (key == 'contacts$scope') return true;
    if (key == 'discovered_contacts$scope') return true;
    if (key == 'channels$scope') return true;
    if (key == 'channel_order_$scope') return true;
    if (key == 'contact_groups$scope') return true;
    if (key.startsWith('channel_smaz_$scope')) return true;
    if (key.startsWith('channel_cyr2lat_$scope')) return true;
    if (key.startsWith('channel_region_$scope')) return true;
    if (key.startsWith('contact_smaz_$scope')) return true;
    if (key.startsWith('contact_cyr2lat_$scope')) return true;
    return false;
  }

  Map<String, dynamic>? _encodePrefValue(
    dynamic prefs,
    String key,
    String scope,
  ) {
    final value = prefs.get(key);
    if (value is String) {
      return {
        'type': 'string',
        'value': _sanitizedStringForExport(key, value, scope),
      };
    }
    if (value is bool) return {'type': 'bool', 'value': value};
    if (value is int) return {'type': 'int', 'value': value};
    if (value is double) return {'type': 'double', 'value': value};
    if (value is List<String>) return {'type': 'stringList', 'value': value};
    return null;
  }

  String _sanitizedStringForExport(String key, String value, String scope) {
    if (key == 'channels$scope') {
      final local = _decodeList(value);
      for (final channel in local) {
        channel['unreadCount'] = 0;
      }
      return jsonEncode(local);
    }
    return value;
  }

  Future<bool> _mergeKey(
    String scope,
    String key,
    Map<String, dynamic> remote,
  ) async {
    final prefs = PrefsManager.instance;
    final type = remote['type'] as String?;
    final remoteValue = remote['value'];

    if (type != 'string') {
      return _writeSimpleValue(key, type, remoteValue);
    }

    if (remoteValue is! String) return false;
    final localValue = prefs.getString(key);
    final mergedValue = _mergeStringValue(scope, key, localValue, remoteValue);
    if (mergedValue == localValue) return false;
    await prefs.setString(key, mergedValue);
    return true;
  }

  Future<bool> _writeSimpleValue(
    String key,
    String? type,
    dynamic remoteValue,
  ) async {
    final prefs = PrefsManager.instance;
    switch (type) {
      case 'bool':
        if (remoteValue is! bool || prefs.getBool(key) == remoteValue) {
          return false;
        }
        await prefs.setBool(key, remoteValue);
        return true;
      case 'int':
        if (remoteValue is! int || prefs.getInt(key) == remoteValue) {
          return false;
        }
        await prefs.setInt(key, remoteValue);
        return true;
      case 'double':
        if (remoteValue is! num ||
            prefs.getDouble(key) == remoteValue.toDouble()) {
          return false;
        }
        await prefs.setDouble(key, remoteValue.toDouble());
        return true;
      case 'stringList':
        if (remoteValue is! List) return false;
        final list = remoteValue.map((entry) => entry.toString()).toList();
        if (listEquals(prefs.getStringList(key), list)) return false;
        await prefs.setStringList(key, list);
        return true;
    }
    return false;
  }

  String _mergeStringValue(
    String scope,
    String key,
    String? localValue,
    String remoteValue,
  ) {
    if (key == 'contacts$scope' || key == 'discovered_contacts$scope') {
      return jsonEncode(_mergeContacts(localValue, remoteValue));
    }
    if (key.startsWith('messages_$scope')) {
      return jsonEncode(_mergeMessages(localValue, remoteValue));
    }
    if (key.startsWith('channel_messages_$scope')) {
      return jsonEncode(_mergeChannelMessages(localValue, remoteValue));
    }
    if (key == 'channels$scope') {
      return jsonEncode(_mergeChannels(localValue, remoteValue));
    }
    if (key == 'contact_groups$scope') {
      return jsonEncode(_mergeContactGroups(localValue, remoteValue));
    }
    return remoteValue;
  }

  List<Map<String, dynamic>> _mergeContacts(String? local, String remote) {
    final merged = <String, Map<String, dynamic>>{};
    for (final entry in _decodeList(local)) {
      final key = entry['publicKey']?.toString();
      if (key != null && key.isNotEmpty) merged[key] = entry;
    }
    for (final entry in _decodeList(remote)) {
      final key = entry['publicKey']?.toString();
      if (key == null || key.isEmpty) continue;
      final current = merged[key];
      if (current == null) {
        merged[key] = entry;
      } else {
        merged[key] = _newerContact(current, entry);
      }
    }
    final list = merged.values.toList();
    list.sort((a, b) => _contactSortTime(b).compareTo(_contactSortTime(a)));
    return list;
  }

  Map<String, dynamic> _newerContact(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final localTime = _contactSortTime(local);
    final remoteTime = _contactSortTime(remote);
    final winner = remoteTime >= localTime
        ? Map<String, dynamic>.from(remote)
        : Map<String, dynamic>.from(local);
    final localOverride = local['pathOverride'];
    if (localOverride != null && winner['pathOverride'] == null) {
      winner['pathOverride'] = localOverride;
      winner['pathOverrideBytes'] = local['pathOverrideBytes'];
    }
    return winner;
  }

  int _contactSortTime(Map<String, dynamic> entry) {
    return _asInt(entry['lastModified']) ??
        _asInt(entry['lastSeen']) ??
        _asInt(entry['lastMessageAt']) ??
        0;
  }

  List<Map<String, dynamic>> _mergeMessages(String? local, String remote) {
    return _mergeMessageList(
      local,
      remote,
      statusRank: (value) {
        switch (_asInt(value)) {
          case 2:
            return 3; // delivered
          case 1:
            return 2; // sent
          case 0:
            return 1; // pending
          default:
            return 0; // failed / unknown
        }
      },
    );
  }

  List<Map<String, dynamic>> _mergeChannelMessages(
    String? local,
    String remote,
  ) {
    return _mergeMessageList(
      local,
      remote,
      statusRank: (value) {
        switch (_asInt(value)) {
          case 1:
            return 2; // sent
          case 0:
            return 1; // pending
          default:
            return 0; // failed / unknown
        }
      },
      channelMessage: true,
    );
  }

  List<Map<String, dynamic>> _mergeMessageList(
    String? local,
    String remote, {
    required int Function(dynamic value) statusRank,
    bool channelMessage = false,
  }) {
    final merged = <String, Map<String, dynamic>>{};
    void addAll(List<Map<String, dynamic>> entries) {
      for (final entry in entries) {
        final key = _messageKey(entry, channelMessage: channelMessage);
        final current = merged[key];
        if (current == null) {
          merged[key] = entry;
          continue;
        }
        final currentRank = statusRank(current['status']);
        final nextRank = statusRank(entry['status']);
        final currentTime =
            _asInt(current['deliveredAt']) ??
            _asInt(current['sentAt']) ??
            _asInt(current['timestamp']) ??
            0;
        final nextTime =
            _asInt(entry['deliveredAt']) ??
            _asInt(entry['sentAt']) ??
            _asInt(entry['timestamp']) ??
            0;
        final winner =
            nextRank > currentRank ||
                (nextRank == currentRank && nextTime >= currentTime)
            ? Map<String, dynamic>.from(entry)
            : Map<String, dynamic>.from(current);
        winner['reactions'] = {
          ...((current['reactions'] as Map?) ?? const {}),
          ...((entry['reactions'] as Map?) ?? const {}),
        };
        merged[key] = winner;
      }
    }

    addAll(_decodeList(local));
    addAll(_decodeList(remote));
    final list = merged.values.toList();
    list.sort(
      (a, b) =>
          (_asInt(a['timestamp']) ?? 0).compareTo(_asInt(b['timestamp']) ?? 0),
    );
    return list;
  }

  String _messageKey(
    Map<String, dynamic> entry, {
    required bool channelMessage,
  }) {
    final packetHash = entry['packetHash']?.toString();
    if (packetHash != null && packetHash.isNotEmpty) {
      return 'packet:$packetHash';
    }
    final messageId = entry['messageId']?.toString();
    if (messageId != null && messageId.isNotEmpty) return 'id:$messageId';
    final sender = channelMessage
        ? entry['senderName']?.toString()
        : entry['senderKey']?.toString();
    return 'fallback:$sender:${entry['isOutgoing']}:${entry['timestamp']}:${entry['text']}';
  }

  List<Map<String, dynamic>> _mergeChannels(String? local, String remote) {
    final merged = <int, Map<String, dynamic>>{};
    final localUnread = <int, int>{};
    for (final channel in _decodeList(local)) {
      final index = _asInt(channel['index']);
      if (index == null) continue;
      localUnread[index] = _asInt(channel['unreadCount']) ?? 0;
      merged[index] = channel;
    }
    for (final channel in _decodeList(remote)) {
      final index = _asInt(channel['index']);
      if (index == null) continue;
      final current = merged[index];
      if (current == null || !_channelIsEmpty(channel)) {
        merged[index] = channel;
      }
    }
    for (final entry in merged.entries) {
      entry.value['unreadCount'] = localUnread[entry.key] ?? 0;
    }
    final list = merged.values.toList();
    list.sort(
      (a, b) => (_asInt(a['index']) ?? 0).compareTo(_asInt(b['index']) ?? 0),
    );
    return list;
  }

  bool _channelIsEmpty(Map<String, dynamic> channel) {
    final name = channel['name']?.toString() ?? '';
    final psk = channel['psk']?.toString() ?? '';
    return name.isEmpty && (psk.isEmpty || RegExp(r'^A+=*$').hasMatch(psk));
  }

  List<Map<String, dynamic>> _mergeContactGroups(String? local, String remote) {
    final groups = <String, Set<String>>{};
    void addAll(List<Map<String, dynamic>> entries) {
      for (final entry in entries) {
        final name = entry['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final members =
            (entry['members'] as List?)
                ?.map((value) => value.toString())
                .where((value) => value.isNotEmpty) ??
            const Iterable<String>.empty();
        groups.putIfAbsent(name, () => <String>{}).addAll(members);
      }
    }

    addAll(_decodeList(local));
    addAll(_decodeList(remote));
    final list = groups.entries
        .map((entry) => {'name': entry.key, 'members': entry.value.toList()})
        .toList();
    list.sort((a, b) => a['name'].toString().compareTo(b['name'].toString()));
    return list;
  }

  List<Map<String, dynamic>> _decodeList(String? value) {
    if (value == null || value.isEmpty) return [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  void dispose() {
    _exportTimer?.cancel();
    super.dispose();
  }
}
