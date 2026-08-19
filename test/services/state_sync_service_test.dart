import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:meshcore_open/services/state_sync_backend.dart';
import 'package:meshcore_open/services/state_sync_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';

class _FakeStateSyncBackend extends StateSyncBackend {
  final Map<String, Map<String, dynamic>> files = {};

  @override
  bool get isSupported => true;

  @override
  Future<StateSyncFolder?> pickFolder() async {
    return const StateSyncFolder(
      id: 'sync-folder',
      name: 'Sync',
      displayPath: '/tmp/Sync',
    );
  }

  @override
  Future<bool> folderExists(String id) async => id == 'sync-folder';

  @override
  Future<Map<String, dynamic>?> readJson(String folderId, String name) async {
    return files[name];
  }

  @override
  Future<void> writeJson(
    String folderId,
    String name,
    Map<String, dynamic> json,
  ) async {
    files[name] = json;
  }
}

void main() {
  const selfKey = '0123456789abcdef';
  const scope = '0123456789';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  test(
    'exports discovered contacts but excludes unread, pending, and passwords',
    () async {
      final backend = _FakeStateSyncBackend();
      final service = StateSyncService(backend: backend);
      await service.initialize();
      await service.pickFolder();

      final prefs = PrefsManager.instance;
      await prefs.setString(
        'discovered_contacts$scope',
        '[{"publicKey":"abc"}]',
      );
      await prefs.setString('contacts$scope', '[{"publicKey":"def"}]');
      await prefs.setString('contact_unread_count$scope', '{"abc":2}');
      await prefs.setString('pending_messages', '{"abc":"hello"}');
      await prefs.setString('repeater_passwords', '{"abc":"secret"}');

      await service.exportForNode(selfKey);

      final bundle = backend.files['meshcore-open-state-$scope.json']!;
      final keys = bundle['keys'] as Map<String, dynamic>;
      expect(keys, contains('discovered_contacts$scope'));
      expect(keys, contains('contacts$scope'));
      expect(keys, isNot(contains('contact_unread_count$scope')));
      expect(keys, isNot(contains('pending_messages')));
      expect(keys, isNot(contains('repeater_passwords')));
    },
  );

  test('imports and merges discovered contacts by newest timestamp', () async {
    final backend = _FakeStateSyncBackend();
    final service = StateSyncService(backend: backend);
    await service.initialize();
    await service.pickFolder();

    final prefs = PrefsManager.instance;
    await prefs.setString(
      'discovered_contacts$scope',
      '[{"publicKey":"same","name":"old","lastSeen":1000}]',
    );
    backend.files['meshcore-open-state-$scope.json'] = {
      'schemaVersion': 1,
      'appId': 'meshcore-open',
      'scope': scope,
      'updatedAt': 2000,
      'keys': {
        'discovered_contacts$scope': {
          'type': 'string',
          'value': '[{"publicKey":"same","name":"new","lastSeen":2000}]',
        },
      },
    };

    final changed = await service.importForNode(selfKey);

    expect(changed, isTrue);
    expect(
      prefs.getString('discovered_contacts$scope'),
      '[{"publicKey":"same","name":"new","lastSeen":2000}]',
    );
  });

  test(
    'export preserves discovered contacts already in the sync bundle',
    () async {
      final backend = _FakeStateSyncBackend();
      final service = StateSyncService(backend: backend);
      await service.initialize();
      await service.pickFolder();

      final prefs = PrefsManager.instance;
      await prefs.setString(
        'discovered_contacts$scope',
        '[{"publicKey":"local","name":"Local","lastSeen":2000}]',
      );
      backend.files['meshcore-open-state-$scope.json'] = {
        'schemaVersion': 1,
        'appId': 'meshcore-open',
        'scope': scope,
        'updatedAt': 1000,
        'keys': {
          'discovered_contacts$scope': {
            'type': 'string',
            'value': '[{"publicKey":"remote","name":"Remote","lastSeen":1000}]',
          },
        },
      };

      await service.exportForNode(selfKey);

      final bundle = backend.files['meshcore-open-state-$scope.json']!;
      final keys = bundle['keys'] as Map<String, dynamic>;
      final discovered = keys['discovered_contacts$scope'] as Map;
      expect(
        discovered['value'],
        '[{"publicKey":"local","name":"Local","lastSeen":2000},{"publicKey":"remote","name":"Remote","lastSeen":1000}]',
      );
    },
  );

  test(
    'legacy future-dated messages do not displace recent history on import',
    () async {
      final backend = _FakeStateSyncBackend();
      final service = StateSyncService(backend: backend);
      await service.initialize();
      await service.pickFolder();

      final now = DateTime.now();
      final recentTimestamp = now
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final corruptTimestamp = now
          .add(const Duration(days: 3650))
          .millisecondsSinceEpoch;
      final prefs = PrefsManager.instance;
      await prefs.setString(
        'channel_messages_${scope}3',
        '[{"messageId":"recent","timestamp":$recentTimestamp,'
            '"status":1,"senderName":"Recent","text":"new"}]',
      );
      backend.files['meshcore-open-state-$scope.json'] = {
        'schemaVersion': 1,
        'appId': 'meshcore-open',
        'scope': scope,
        'updatedAt': recentTimestamp,
        'keys': {
          'channel_messages_${scope}3': {
            'type': 'string',
            'value':
                '[{"messageId":"future-1","timestamp":$corruptTimestamp,'
                '"status":1,"senderName":"Bad clock","text":"old 1"},'
                '{"messageId":"future-2","timestamp":${corruptTimestamp + 1},'
                '"status":1,"senderName":"Bad clock","text":"old 2"}]',
          },
        },
      };

      await service.importForNode(selfKey);

      final imported = prefs.getString('channel_messages_${scope}3');
      expect(imported, isNotNull);
      expect(
        (jsonDecode(imported!) as List)
            .map((entry) => (entry as Map)['messageId'])
            .toList(),
        ['future-1', 'future-2', 'recent'],
      );
    },
  );

  test(
    'channel history is ordered by arrival instead of sender time',
    () async {
      final backend = _FakeStateSyncBackend();
      final service = StateSyncService(backend: backend);
      await service.initialize();
      await service.pickFolder();

      final now = DateTime.now();
      final firstArrival = now
          .subtract(const Duration(minutes: 3))
          .millisecondsSinceEpoch;
      final secondArrival = now
          .subtract(const Duration(minutes: 2))
          .millisecondsSinceEpoch;
      final lastArrival = now
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      final corruptSenderTimestamp = now
          .add(const Duration(days: 3650))
          .millisecondsSinceEpoch;
      final prefs = PrefsManager.instance;
      await prefs.setString(
        'channel_messages_${scope}3',
        '[{"messageId":"last","timestamp":${now.millisecondsSinceEpoch},'
            '"receivedAt":$lastArrival,"status":1,"senderName":"Recent",'
            '"text":"new"}]',
      );
      backend.files['meshcore-open-state-$scope.json'] = {
        'schemaVersion': 1,
        'appId': 'meshcore-open',
        'scope': scope,
        'updatedAt': now.millisecondsSinceEpoch,
        'keys': {
          'channel_messages_${scope}3': {
            'type': 'string',
            'value':
                '[{"messageId":"first","timestamp":$corruptSenderTimestamp,'
                '"receivedAt":$firstArrival,"status":1,'
                '"senderName":"Bad clock","text":"old 1"},'
                '{"messageId":"second",'
                '"timestamp":${corruptSenderTimestamp + 1},'
                '"receivedAt":$secondArrival,"status":1,'
                '"senderName":"Bad clock","text":"old 2"}]',
          },
        },
      };

      await service.importForNode(selfKey);

      final imported = prefs.getString('channel_messages_${scope}3');
      expect(imported, isNotNull);
      expect(
        (jsonDecode(imported!) as List)
            .map((entry) => (entry as Map)['messageId'])
            .toList(),
        ['first', 'second', 'last'],
      );
    },
  );

  test(
    'sent channel snapshot replaces pending snapshot with the same message ID',
    () async {
      final backend = _FakeStateSyncBackend();
      final service = StateSyncService(backend: backend);
      await service.initialize();
      await service.pickFolder();

      final now = DateTime.now().millisecondsSinceEpoch;
      final prefs = PrefsManager.instance;
      await prefs.setString(
        'channel_messages_${scope}1',
        '[{"messageId":"outgoing-1","packetHash":"packet-1",'
            '"timestamp":$now,"receivedAt":$now,"status":1,'
            '"isOutgoing":true,"senderName":"Me","text":"hello"}]',
      );
      backend.files['meshcore-open-state-$scope.json'] = {
        'schemaVersion': 1,
        'appId': 'meshcore-open',
        'scope': scope,
        'updatedAt': now,
        'keys': {
          'channel_messages_${scope}1': {
            'type': 'string',
            'value':
                '[{"messageId":"outgoing-1","packetHash":null,'
                '"timestamp":$now,"receivedAt":${now - 1000},"status":0,'
                '"isOutgoing":true,"senderName":"Me","text":"hello"}]',
          },
        },
      };

      await service.importForNode(selfKey);

      final imported =
          jsonDecode(prefs.getString('channel_messages_${scope}1')!) as List;
      expect(imported, hasLength(1));
      expect(imported.single['messageId'], 'outgoing-1');
      expect(imported.single['status'], 1);
      expect(imported.single['packetHash'], 'packet-1');
      expect(imported.single['receivedAt'], now - 1000);

      final exported =
          jsonDecode(
                (backend.files['meshcore-open-state-$scope.json']!['keys']
                        as Map<
                          String,
                          dynamic
                        >)['channel_messages_${scope}1']['value']
                    as String,
              )
              as List;
      expect(exported, hasLength(1));
      expect(exported.single['status'], 1);
    },
  );
}
