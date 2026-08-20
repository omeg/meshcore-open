import 'dart:io';

String? readSystemTimeLocaleEnvironment() {
  final environment = Platform.environment;
  return _firstNonEmpty([
    environment['LC_ALL'],
    environment['LC_TIME'],
    environment['LANG'],
  ]);
}

String? _firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    if (value != null && value.trim().isNotEmpty) return value;
  }
  return null;
}
