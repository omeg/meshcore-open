import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';

/// Persisted resume state for one repeater's telemetry log session.
///
/// Mirrors the `.state.json` written by the reference `telem_fetch.py`: enough
/// to decide "same session, append the tail" vs "device log was reset, start a
/// new file". The assembled log bytes live in a sibling `.telemetry` file named
/// by [sessionFilename], in the firmware's raw export format so the existing
/// `telem_import.py` tooling can ingest them into a database unchanged.
class TelemetryLogSession {
  final String repeaterPubkey; // full 32-byte pubkey, lowercase hex
  final String sessionFilename; // <repeater8>-<stamp>.telemetry
  final String headerHex; // export header bytes, hex — identifies the layout
  final int? logStartTs; // first-anchor epoch s, or null if RTC was unset
  final int lastTotalSize; // total_size reported on the last pull
  final int lastPullOffset; // bytes we have stored for this session
  final int intervalSeconds;
  final int timestampStride;
  final int channelCount;
  final String updatedAt; // ISO 8601 UTC seconds, e.g. 2026-06-08T17:37:54Z

  const TelemetryLogSession({
    required this.repeaterPubkey,
    required this.sessionFilename,
    required this.headerHex,
    required this.logStartTs,
    required this.lastTotalSize,
    required this.lastPullOffset,
    required this.intervalSeconds,
    required this.timestampStride,
    required this.channelCount,
    required this.updatedAt,
  });

  // JSON keys mirror telem_fetch.py's state schema verbatim so the firmware's
  // telem_import.py reads our files without any aliasing layer.
  Map<String, dynamic> toJson() => {
    'pubkey': repeaterPubkey,
    'log_filename': sessionFilename,
    'header_hex': headerHex,
    'log_start_ts': logStartTs,
    'last_total_size': lastTotalSize,
    'last_pull_offset': lastPullOffset,
    'interval_s': intervalSeconds,
    'timestamp_stride': timestampStride,
    'channel_count': channelCount,
    'updated_at': updatedAt,
  };

  factory TelemetryLogSession.fromJson(Map<String, dynamic> json) {
    return TelemetryLogSession(
      repeaterPubkey: json['pubkey'] as String? ?? '',
      sessionFilename: json['log_filename'] as String? ?? '',
      headerHex: json['header_hex'] as String? ?? '',
      logStartTs: json['log_start_ts'] as int?,
      lastTotalSize: json['last_total_size'] as int? ?? 0,
      lastPullOffset: json['last_pull_offset'] as int? ?? 0,
      intervalSeconds: json['interval_s'] as int? ?? 0,
      timestampStride: json['timestamp_stride'] as int? ?? 0,
      channelCount: json['channel_count'] as int? ?? 0,
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }
}

/// A retained `.telemetry` file on disk.
class TelemetryLogFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  const TelemetryLogFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });
}

/// One file to export, held in memory (name + bytes + MIME type).
class TelemetryExportEntry {
  final String name;
  final Uint8List bytes;
  final String mime;

  const TelemetryExportEntry({
    required this.name,
    required this.bytes,
    required this.mime,
  });
}

/// File-backed store for fetched telemetry logs.
///
/// Logs are written under `<app documents>/telemetry_logs/` as raw export-format
/// `.telemetry` files, named like the firmware tooling
/// (`<repeater8>-<YYYYMMDDTHHMMSSZ>.telemetry`, or `…-<wallclock>-nortc.telemetry`
/// when the device RTC was unset), with a `<repeater8>.state.json` sibling for
/// resume. Filenames are keyed by the repeater's pubkey (the data is the
/// repeater's, independent of which local radio fetched it) so they stay
/// compatible with `telem_import.py`.
class TelemetryLogStore {
  static const String _dirName = 'telemetry_logs';

  String _short(String repeaterHex) =>
      repeaterHex.length >= 8 ? repeaterHex.substring(0, 8) : repeaterHex;

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _statePath(Directory dir, String repeaterHex) =>
      '${dir.path}/${_short(repeaterHex)}.state.json';

  String _stamp(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}T'
        '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  /// Filename for a session. Uses the first anchor's UTC timestamp when the
  /// device RTC was set; otherwise a wall-clock stamp tagged `-nortc`.
  String sessionFilename(String repeaterHex, int? logStartTs) {
    final short = _short(repeaterHex);
    if (logStartTs == null) {
      return '$short-${_stamp(DateTime.now())}-nortc.telemetry';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(logStartTs * 1000, isUtc: true);
    return '$short-${_stamp(dt)}.telemetry';
  }

  /// Absolute path of the directory where `.telemetry` files are stored.
  Future<String> storageDirectoryPath() async => (await _dir()).path;

  Future<TelemetryLogSession?> loadSession(String repeaterHex) async {
    try {
      final dir = await _dir();
      final file = File(_statePath(dir, repeaterHex));
      if (!file.existsSync()) return null;
      return TelemetryLogSession.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (e) {
      appLogger.warn('Corrupt telemetry log state ignored: $e', tag: 'TelemLog');
      return null;
    }
  }

  Future<Uint8List?> loadBytes(String filename) async {
    if (filename.isEmpty) return null;
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$filename');
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e) {
      appLogger.warn('Failed reading telemetry log file: $e', tag: 'TelemLog');
      return null;
    }
  }

  /// Write the assembled [bytes] and resume [session]. Returns the full path of
  /// the `.telemetry` file, or null on failure.
  Future<String?> saveSession(
    String repeaterHex,
    TelemetryLogSession session,
    Uint8List bytes,
  ) async {
    try {
      final dir = await _dir();
      final logPath = '${dir.path}/${session.sessionFilename}';
      await _atomicWrite(logPath, bytes);
      await _atomicWriteString(
        _statePath(dir, repeaterHex),
        jsonEncode(session.toJson()),
      );
      return logPath;
    } catch (e) {
      appLogger.warn('Failed writing telemetry log file: $e', tag: 'TelemLog');
      return null;
    }
  }

  /// All retained `.telemetry` files for [repeaterHex], newest first. Historical
  /// sessions accumulate here (a device-side log reset writes a new file rather
  /// than overwriting the old one), so this is the archive available for export.
  Future<List<TelemetryLogFile>> listLogFiles(String repeaterHex) async {
    try {
      final dir = await _dir();
      final prefix = '${_short(repeaterHex)}-';
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.uri.pathSegments.last;
            return name.startsWith(prefix) && name.endsWith('.telemetry');
          })
          .map((f) {
            final stat = f.statSync();
            return TelemetryLogFile(
              path: f.path,
              name: f.uri.pathSegments.last,
              sizeBytes: stat.size,
              modified: stat.modified,
            );
          })
          .toList();
      files.sort((a, b) => b.modified.compareTo(a.modified));
      return files;
    } catch (e) {
      appLogger.warn('Failed listing telemetry log files: $e', tag: 'TelemLog');
      return const [];
    }
  }

  Future<void> deleteLogFile(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      appLogger.warn('Failed deleting telemetry log file: $e', tag: 'TelemLog');
    }
  }

  /// Full path of the `<repeater8>.state.json` resume file, if it exists. It is
  /// the same file `telem_import.py` reads, so exporting it next to the
  /// `.telemetry` files lets the importer resume in place.
  Future<String?> stateFilePath(String repeaterHex) async {
    final dir = await _dir();
    final path = _statePath(dir, repeaterHex);
    return File(path).existsSync() ? path : null;
  }

  /// Copy [telemetryPath] and the repeater's `.state.json` into [destDir]
  /// (an ordinary filesystem directory the user picked). Returns the basenames
  /// written. Used on desktop, where the export target is a real directory.
  Future<List<String>> exportSessionTo(
    String destDir,
    String telemetryPath,
    String repeaterHex,
  ) async {
    final written = <String>[];
    final telemetry = File(telemetryPath);
    if (telemetry.existsSync()) {
      final name = telemetry.uri.pathSegments.last;
      await telemetry.copy('$destDir/$name');
      written.add(name);
    }
    final statePath = await stateFilePath(repeaterHex);
    if (statePath != null) {
      final name = File(statePath).uri.pathSegments.last;
      await File(statePath).copy('$destDir/$name');
      written.add(name);
    }
    return written;
  }

  /// The `.telemetry` + `.state.json` pair as in-memory bytes, for writing into
  /// a destination this process can't reach with `dart:io` (e.g. an Android SAF
  /// directory). Empty if the telemetry file is missing.
  Future<List<TelemetryExportEntry>> exportPayload(
    String telemetryPath,
    String repeaterHex,
  ) async {
    final entries = <TelemetryExportEntry>[];
    final telemetry = File(telemetryPath);
    if (!telemetry.existsSync()) return entries;
    entries.add(
      TelemetryExportEntry(
        name: telemetry.uri.pathSegments.last,
        bytes: await telemetry.readAsBytes(),
        mime: 'application/octet-stream',
      ),
    );
    final statePath = await stateFilePath(repeaterHex);
    if (statePath != null) {
      entries.add(
        TelemetryExportEntry(
          name: File(statePath).uri.pathSegments.last,
          bytes: await File(statePath).readAsBytes(),
          mime: 'application/json',
        ),
      );
    }
    return entries;
  }

  /// Full path of the current session's `.telemetry` file, if it exists.
  Future<String?> currentFilePath(String repeaterHex) async {
    final session = await loadSession(repeaterHex);
    if (session == null || session.sessionFilename.isEmpty) return null;
    final dir = await _dir();
    final path = '${dir.path}/${session.sessionFilename}';
    return File(path).existsSync() ? path : null;
  }

  Future<void> clear(String repeaterHex) async {
    try {
      final dir = await _dir();
      final session = await loadSession(repeaterHex);
      if (session != null && session.sessionFilename.isNotEmpty) {
        final logFile = File('${dir.path}/${session.sessionFilename}');
        if (logFile.existsSync()) await logFile.delete();
      }
      final stateFile = File(_statePath(dir, repeaterHex));
      if (stateFile.existsSync()) await stateFile.delete();
    } catch (e) {
      appLogger.warn('Failed clearing telemetry log files: $e', tag: 'TelemLog');
    }
  }

  Future<void> _atomicWrite(String path, Uint8List bytes) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  Future<void> _atomicWriteString(String path, String contents) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(path);
  }
}
