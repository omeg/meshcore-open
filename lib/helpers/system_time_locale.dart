import 'system_time_locale_stub.dart'
    if (dart.library.io) 'system_time_locale_io.dart';

String? readSystemTimeLocale() {
  return normalizeSystemTimeLocale(readSystemTimeLocaleEnvironment());
}

String? normalizeSystemTimeLocale(String? value) {
  if (value == null) return null;
  final normalized = value
      .trim()
      .split('.')
      .first
      .split('@')
      .first
      .replaceAll('-', '_');
  if (normalized.isEmpty || normalized == 'C' || normalized == 'POSIX') {
    return null;
  }
  return normalized;
}
