import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import 'system_time_locale.dart';

final Map<String, DateFormat> _monthDayFormats = {};
final Map<String, DateFormat> _numericDateFormats = {};
final Map<String, DateFormat> _fullDateFormats = {};
final Map<String, DateFormat> _localeTimeFormats = {};
final Map<String, DateFormat> _locale24HourTimeFormats = {};
final Map<String, DateFormat> _locale12HourTimeFormats = {};
final Map<String, DateFormat> _customTimeFormats = {};
final Map<String, DateFormat> _customDateFormats = {};

final String? _systemTimeLocale = readSystemTimeLocale();

/// Formats a clock time using the app preference. System mode follows the OS
/// date/time locale and its 12-/24-hour clock preference.
String formatLocalizedTime(
  BuildContext context,
  DateTime dateTime, {
  String? localeOverride,
  TimeFormatPreference? timeFormatPreference,
  String? customTimePattern,
}) {
  final settingsService = Provider.of<AppSettingsService?>(context);
  final preference =
      timeFormatPreference ??
      settingsService?.settings.timeFormatPreference ??
      TimeFormatPreference.system;
  final locale =
      localeOverride ??
      _systemTimeLocale ??
      Localizations.localeOf(context).toString();

  if (preference == TimeFormatPreference.twelveHour) {
    final formatter = _locale12HourTimeFormats.putIfAbsent(
      locale,
      () => DateFormat('h:mm a', locale),
    );
    return formatter.format(dateTime);
  }

  if (preference == TimeFormatPreference.twentyFourHour) {
    final formatter = _locale24HourTimeFormats.putIfAbsent(
      locale,
      () => DateFormat.Hm(locale),
    );
    return formatter.format(dateTime);
  }

  if (preference == TimeFormatPreference.custom) {
    final pattern =
        customTimePattern ??
        settingsService?.settings.customTimePattern ??
        defaultCustomTimePattern;
    try {
      final cacheKey = '$locale\u0000$pattern';
      final formatter = _customTimeFormats.putIfAbsent(
        cacheKey,
        () => DateFormat(pattern, locale),
      );
      return formatter.format(dateTime);
    } on FormatException {
      return DateFormat(defaultCustomTimePattern, locale).format(dateTime);
    } on ArgumentError {
      return DateFormat(defaultCustomTimePattern, locale).format(dateTime);
    }
  }

  final systemLocale = localeOverride ?? _systemTimeLocale;
  if (systemLocale != null) {
    final alwaysUse24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);
    final formats = alwaysUse24HourFormat
        ? _locale24HourTimeFormats
        : _localeTimeFormats;
    final formatter = formats.putIfAbsent(
      systemLocale,
      () => alwaysUse24HourFormat
          ? DateFormat.Hm(systemLocale)
          : DateFormat.jm(systemLocale),
    );
    return formatter.format(dateTime);
  }
  return MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(dateTime),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
}

bool isValidCustomTimePattern(String pattern) {
  return _isValidCustomDateTimePattern(pattern);
}

bool isValidCustomDatePattern(String pattern) {
  return _isValidCustomDateTimePattern(pattern);
}

bool _isValidCustomDateTimePattern(String pattern) {
  final trimmed = pattern.trim();
  if (trimmed.isEmpty || trimmed.length > 64 || !_hasBalancedQuotes(trimmed)) {
    return false;
  }
  try {
    DateFormat(trimmed, 'en_US').format(DateTime(2026, 8, 20, 17, 5, 9));
    return true;
  } on FormatException {
    return false;
  } on ArgumentError {
    return false;
  }
}

bool _hasBalancedQuotes(String pattern) {
  var quoted = false;
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] != "'") continue;
    if (i + 1 < pattern.length && pattern[i + 1] == "'") {
      i++;
      continue;
    }
    quoted = !quoted;
  }
  return !quoted;
}

/// Formats a numeric month/day value in the order and punctuation of the
/// active locale.
String formatLocalizedMonthDay(
  BuildContext context,
  DateTime dateTime, {
  String? localeOverride,
  DateFormatPreference? dateFormatPreference,
  String? customDatePattern,
}) {
  return _formatLocalizedDate(
    context,
    dateTime,
    localeOverride: localeOverride,
    dateFormatPreference: dateFormatPreference,
    customDatePattern: customDatePattern,
    systemFormats: _monthDayFormats,
    systemFormatBuilder: DateFormat.Md,
  );
}

/// Formats a numeric date in the order and punctuation of the active locale.
String formatLocalizedNumericDate(
  BuildContext context,
  DateTime dateTime, {
  String? localeOverride,
  DateFormatPreference? dateFormatPreference,
  String? customDatePattern,
}) {
  return _formatLocalizedDate(
    context,
    dateTime,
    localeOverride: localeOverride,
    dateFormatPreference: dateFormatPreference,
    customDatePattern: customDatePattern,
    systemFormats: _numericDateFormats,
    systemFormatBuilder: DateFormat.yMd,
  );
}

/// Formats a full date using the OS date/time locale when it is available.
String formatLocalizedFullDate(
  BuildContext context,
  DateTime dateTime, {
  String? localeOverride,
  DateFormatPreference? dateFormatPreference,
  String? customDatePattern,
}) {
  return _formatLocalizedDate(
    context,
    dateTime,
    localeOverride: localeOverride,
    dateFormatPreference: dateFormatPreference,
    customDatePattern: customDatePattern,
    systemFormats: _fullDateFormats,
    systemFormatBuilder: DateFormat.yMMMMEEEEd,
  );
}

String _formatLocalizedDate(
  BuildContext context,
  DateTime dateTime, {
  required Map<String, DateFormat> systemFormats,
  required DateFormat Function(String locale) systemFormatBuilder,
  String? localeOverride,
  DateFormatPreference? dateFormatPreference,
  String? customDatePattern,
}) {
  final settingsService = Provider.of<AppSettingsService?>(context);
  final preference =
      dateFormatPreference ??
      settingsService?.settings.dateFormatPreference ??
      DateFormatPreference.system;
  final locale =
      localeOverride ??
      _systemTimeLocale ??
      Localizations.localeOf(context).toString();

  if (preference == DateFormatPreference.system) {
    final formatter = systemFormats.putIfAbsent(
      locale,
      () => systemFormatBuilder(locale),
    );
    return formatter.format(dateTime);
  }

  final pattern = switch (preference) {
    DateFormatPreference.dayMonthYear => 'dd/MM/yyyy',
    DateFormatPreference.monthDayYear => 'MM/dd/yyyy',
    DateFormatPreference.yearMonthDay => 'yyyy-MM-dd',
    DateFormatPreference.custom =>
      customDatePattern ??
          settingsService?.settings.customDatePattern ??
          defaultCustomDatePattern,
    DateFormatPreference.system => throw StateError('Handled above'),
  };

  try {
    final cacheKey = '$locale\u0000$pattern';
    final formatter = _customDateFormats.putIfAbsent(
      cacheKey,
      () => DateFormat(pattern, locale),
    );
    return formatter.format(dateTime);
  } on FormatException {
    return DateFormat(defaultCustomDatePattern, locale).format(dateTime);
  } on ArgumentError {
    return DateFormat(defaultCustomDatePattern, locale).format(dateTime);
  }
}
