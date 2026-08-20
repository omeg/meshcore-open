import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/helpers/system_time_locale.dart';

void main() {
  test('normalizes a POSIX LC_TIME locale for intl', () {
    expect(normalizeSystemTimeLocale('pl_PL.UTF-8'), 'pl_PL');
    expect(normalizeSystemTimeLocale('en-GB.UTF-8'), 'en_GB');
    expect(normalizeSystemTimeLocale('sr_RS@latin'), 'sr_RS');
  });

  test('ignores invariant POSIX locales', () {
    expect(normalizeSystemTimeLocale(null), isNull);
    expect(normalizeSystemTimeLocale(''), isNull);
    expect(normalizeSystemTimeLocale('C.UTF-8'), isNull);
    expect(normalizeSystemTimeLocale('POSIX'), isNull);
  });
}
