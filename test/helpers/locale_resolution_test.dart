import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/locale_resolution.dart';

void main() {
  const supported = [Locale('en'), Locale('pl')];

  test('retains the region of a supported preferred language', () {
    expect(
      resolveAppLocale(const [Locale('en', 'GB')], supported),
      const Locale('en', 'GB'),
    );
  });

  test('falls through to another preferred supported language', () {
    expect(
      resolveAppLocale(const [
        Locale('fr', 'CA'),
        Locale('pl', 'PL'),
      ], supported),
      const Locale('pl', 'PL'),
    );
  });

  test('language override retains a matching platform region', () {
    expect(
      localeForLanguageOverride('en', const [
        Locale('pl', 'PL'),
        Locale('en', 'GB'),
      ]),
      const Locale('en', 'GB'),
    );
  });

  test('language override falls back when the platform has no match', () {
    expect(
      localeForLanguageOverride('en', const [Locale('pl', 'PL')]),
      const Locale('en'),
    );
    expect(localeForLanguageOverride(null, supported), isNull);
  });
}
