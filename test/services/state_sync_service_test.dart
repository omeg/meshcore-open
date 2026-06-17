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
}
