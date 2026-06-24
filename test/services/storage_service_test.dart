import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/services/storage_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PrefsManager.reset();
    await PrefsManager.initialize();
    storage = StorageService();
  });

  group('repeater CLI history', () {
    test('stores commands per repeater', () async {
      await storage.saveRepeaterCliHistory('repeater-a', ['clock']);
      await storage.saveRepeaterCliHistory('repeater-b', ['get tx']);

      expect(
        await storage.loadRepeaterCliHistory('repeater-a'),
        equals(['clock']),
      );
      expect(
        await storage.loadRepeaterCliHistory('repeater-b'),
        equals(['get tx']),
      );
    });

    test('deduplicates commands with newest occurrence winning', () async {
      await storage.saveRepeaterCliHistory('repeater-a', [
        'clock',
        'get tx',
        'clock',
        'ver',
      ]);

      expect(
        await storage.loadRepeaterCliHistory('repeater-a'),
        equals(['get tx', 'clock', 'ver']),
      );
    });

    test('limits history to the newest 100 commands', () async {
      await storage.saveRepeaterCliHistory(
        'repeater-a',
        List.generate(105, (index) => 'cmd $index'),
      );

      final history = await storage.loadRepeaterCliHistory('repeater-a');

      expect(history, hasLength(StorageService.repeaterCliHistoryLimit));
      expect(history.first, 'cmd 5');
      expect(history.last, 'cmd 104');
    });

    test('clears stored command history for one repeater', () async {
      await storage.saveRepeaterCliHistory('repeater-a', ['clock']);
      await storage.saveRepeaterCliHistory('repeater-b', ['get tx']);

      await storage.clearRepeaterCliHistory('repeater-a');

      expect(await storage.loadRepeaterCliHistory('repeater-a'), isEmpty);
      expect(
        await storage.loadRepeaterCliHistory('repeater-b'),
        equals(['get tx']),
      );
    });
  });
}
