import 'package:flutter/widgets.dart';

/// Resolves a supported app language without discarding the platform region.
Locale resolveAppLocale(
  List<Locale>? preferredLocales,
  Iterable<Locale> supportedLocales,
) {
  if (preferredLocales != null) {
    for (final preferredLocale in preferredLocales) {
      if (supportedLocales.any(
        (locale) => locale.languageCode == preferredLocale.languageCode,
      )) {
        return preferredLocale;
      }
    }
  }
  return basicLocaleListResolution(preferredLocales, supportedLocales);
}

/// Applies an app language override while retaining a matching platform
/// locale's script and region when available.
Locale? localeForLanguageOverride(
  String? languageCode,
  Iterable<Locale> platformLocales,
) {
  if (languageCode == null) return null;
  for (final locale in platformLocales) {
    if (locale.languageCode == languageCode) return locale;
  }
  return Locale(languageCode);
}
