import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:meshcore_open/storage/prefs_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PrefsManager.reset();
    await PrefsManager.initialize();
  });

  tearDown(PrefsManager.reset);

  test('time format defaults to system behavior', () async {
    final service = AppSettingsService();
    await service.loadSettings();

    expect(service.settings.timeFormatPreference, TimeFormatPreference.system);
  });

  test('time format selection is persisted', () async {
    final service = AppSettingsService();
    await service.loadSettings();
    await service.setTimeFormatPreference(TimeFormatPreference.twentyFourHour);

    final stored =
        jsonDecode(PrefsManager.instance.getString('app_settings')!)
            as Map<String, dynamic>;
    expect(stored['time_format'], '24_hour');

    final restored = AppSettingsService();
    await restored.loadSettings();
    expect(
      restored.settings.timeFormatPreference,
      TimeFormatPreference.twentyFourHour,
    );
  });

  test('custom time pattern is persisted', () async {
    final service = AppSettingsService();
    await service.loadSettings();
    await service.setCustomTimePattern('HH:mm:ss');
    await service.setTimeFormatPreference(TimeFormatPreference.custom);

    final restored = AppSettingsService();
    await restored.loadSettings();
    expect(restored.settings.timeFormatPreference, TimeFormatPreference.custom);
    expect(restored.settings.customTimePattern, 'HH:mm:ss');
  });

  test('date format and custom pattern are persisted', () async {
    final service = AppSettingsService();
    await service.loadSettings();
    await service.setCustomDatePattern('EEE, d MMM yyyy');
    await service.setDateFormatPreference(DateFormatPreference.custom);

    final restored = AppSettingsService();
    await restored.loadSettings();
    expect(restored.settings.dateFormatPreference, DateFormatPreference.custom);
    expect(restored.settings.customDatePattern, 'EEE, d MMM yyyy');
  });
}
