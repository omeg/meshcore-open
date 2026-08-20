import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/localized_time.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/app_settings_service.dart';
import 'package:provider/provider.dart';

class _FakeAppSettingsService extends AppSettingsService {
  AppSettings _value;

  _FakeAppSettingsService(TimeFormatPreference preference)
    : _value = AppSettings(timeFormatPreference: preference);

  @override
  AppSettings get settings => _value;

  void setPreference(TimeFormatPreference preference) {
    _value = _value.copyWith(timeFormatPreference: preference);
    notifyListeners();
  }
}

void main() {
  Future<List<String>> formatFor(
    WidgetTester tester, {
    required Locale locale,
    bool alwaysUse24HourFormat = false,
    TimeFormatPreference timeFormatPreference = TimeFormatPreference.system,
    DateFormatPreference dateFormatPreference = DateFormatPreference.system,
    String? customDatePattern,
  }) async {
    late List<String> result;
    final dateTime = DateTime(2026, 8, 20, 17, 5);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: [locale],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: alwaysUse24HourFormat),
          child: Builder(
            builder: (context) {
              result = [
                formatLocalizedTime(
                  context,
                  dateTime,
                  localeOverride: locale.toString(),
                  timeFormatPreference: timeFormatPreference,
                ),
                formatLocalizedMonthDay(
                  context,
                  dateTime,
                  localeOverride: locale.toString(),
                  dateFormatPreference: dateFormatPreference,
                  customDatePattern: customDatePattern,
                ),
                formatLocalizedNumericDate(
                  context,
                  dateTime,
                  localeOverride: locale.toString(),
                  dateFormatPreference: dateFormatPreference,
                  customDatePattern: customDatePattern,
                ),
                formatLocalizedFullDate(
                  context,
                  dateTime,
                  localeOverride: locale.toString(),
                  dateFormatPreference: dateFormatPreference,
                  customDatePattern: customDatePattern,
                ),
              ];
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    return result;
  }

  testWidgets('uses the locale clock and date conventions', (tester) async {
    expect(await formatFor(tester, locale: const Locale('en', 'US')), [
      '5:05\u202fPM',
      '8/20',
      '8/20/2026',
      'Thursday, August 20, 2026',
    ]);
    expect(await formatFor(tester, locale: const Locale('en', 'GB')), [
      '17:05',
      '20/08',
      '20/08/2026',
      'Thursday, 20 August 2026',
    ]);
  });

  testWidgets('honors the platform 24-hour clock preference', (tester) async {
    expect(
      await formatFor(
        tester,
        locale: const Locale('en', 'US'),
        alwaysUse24HourFormat: true,
      ),
      ['17:05', '8/20', '8/20/2026', 'Thursday, August 20, 2026'],
    );
  });

  testWidgets('app setting can force either clock convention', (tester) async {
    final twelveHour = await formatFor(
      tester,
      locale: const Locale('en', 'GB'),
      timeFormatPreference: TimeFormatPreference.twelveHour,
    );
    expect(twelveHour.first, '5:05 pm');

    final twentyFourHour = await formatFor(
      tester,
      locale: const Locale('en', 'US'),
      timeFormatPreference: TimeFormatPreference.twentyFourHour,
    );
    expect(twentyFourHour.first, '17:05');
  });

  testWidgets('custom pattern controls the displayed clock', (tester) async {
    late String result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            result = formatLocalizedTime(
              context,
              DateTime(2026, 8, 20, 17, 5, 9),
              localeOverride: 'en_US',
              timeFormatPreference: TimeFormatPreference.custom,
              customTimePattern: 'HH:mm:ss',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(result, '17:05:09');
    expect(isValidCustomTimePattern('HH:mm:ss'), isTrue);
    expect(isValidCustomTimePattern("HH:mm '"), isFalse);
    expect(isValidCustomTimePattern(''), isFalse);
  });

  testWidgets('date presets and custom patterns apply to every date style', (
    tester,
  ) async {
    final preset = await formatFor(
      tester,
      locale: const Locale('en', 'GB'),
      dateFormatPreference: DateFormatPreference.monthDayYear,
    );
    expect(preset.skip(1), everyElement('08/20/2026'));

    final custom = await formatFor(
      tester,
      locale: const Locale('en', 'US'),
      dateFormatPreference: DateFormatPreference.custom,
      customDatePattern: 'yyyy.MM.dd',
    );
    expect(custom.skip(1), everyElement('2026.08.20'));
    expect(isValidCustomDatePattern('EEE, d MMM yyyy'), isTrue);
    expect(isValidCustomDatePattern("yyyy-MM-dd '"), isFalse);
    expect(isValidCustomDatePattern(''), isFalse);
  });

  testWidgets('uses and reacts to the persisted app preference', (
    tester,
  ) async {
    final service = _FakeAppSettingsService(TimeFormatPreference.twelveHour);
    final dateTime = DateTime(2026, 8, 20, 17, 5);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsService>.value(
        value: service,
        child: MaterialApp(
          locale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Builder(
            builder: (context) => Text(
              formatLocalizedTime(context, dateTime, localeOverride: 'en_US'),
            ),
          ),
        ),
      ),
    );
    expect(find.text('5:05 PM'), findsOneWidget);

    service.setPreference(TimeFormatPreference.twentyFourHour);
    await tester.pump();
    expect(find.text('17:05'), findsOneWidget);
  });

  testWidgets('OS date/time locale can differ from the app language', (
    tester,
  ) async {
    final dateTime = DateTime(2026, 8, 20, 17, 5);
    late List<String> result;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en', 'US'),
        supportedLocales: const [Locale('en', 'US')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Builder(
          builder: (context) {
            result = [
              formatLocalizedTime(context, dateTime, localeOverride: 'pl_PL'),
              formatLocalizedMonthDay(
                context,
                dateTime,
                localeOverride: 'pl_PL',
              ),
              formatLocalizedNumericDate(
                context,
                dateTime,
                localeOverride: 'pl_PL',
              ),
              formatLocalizedFullDate(
                context,
                dateTime,
                localeOverride: 'pl_PL',
              ),
            ];
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(result, [
      '17:05',
      '20.08',
      '20.08.2026',
      'czwartek, 20 sierpnia 2026',
    ]);
  });
}
