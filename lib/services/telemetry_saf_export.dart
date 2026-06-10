import 'dart:convert';
import 'dart:typed_data';

import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../storage/prefs_manager.dart';
import '../storage/telemetry_log_store.dart';
import '../utils/app_logger.dart';

/// Android Storage Access Framework target for "Export to folder".
///
/// Writes loose `.telemetry` / `.state.json` files into a user-chosen directory
/// (e.g. a folder synced to a PC). The directory's tree URI is persisted with a
/// write permission, so the folder is picked once and reused on later exports —
/// the field workflow of pulling a log and dropping it straight into the synced
/// folder.
class TelemetrySafExport {
  static const String _uriKey = 'telemetry_export_tree_uri';
  static const String _nameKey = 'telemetry_export_tree_name';

  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  /// Display name of the remembered folder (last path segment only), or null.
  String? get rememberedFolderName {
    final name = PrefsManager.instance.getString(_nameKey);
    return (name == null || name.isEmpty) ? null : name;
  }

  /// Human-readable path of the remembered folder, derived from the SAF tree
  /// URI's document id (e.g. `Documents/telemetry_logs`). Falls back to the
  /// folder name if the URI can't be decoded.
  String? get rememberedFolderPath {
    final uri = PrefsManager.instance.getString(_uriKey);
    if (uri == null || uri.isEmpty) return rememberedFolderName;
    return _treePathFromUri(uri) ?? rememberedFolderName;
  }

  /// Decode a SAF tree URI like
  /// `content://…/tree/primary%3ADocuments%2Ftelemetry_logs` into
  /// `Documents/telemetry_logs`. Returns null if it isn't a recognizable tree.
  String? _treePathFromUri(String uri) {
    const marker = '/tree/';
    final idx = uri.indexOf(marker);
    if (idx < 0) return null;
    var docId = uri.substring(idx + marker.length);
    // A document id may be followed by `/document/…`; the id itself URL-encodes
    // its own slashes, so a literal '/' marks the boundary.
    final slash = docId.indexOf('/');
    if (slash >= 0) docId = docId.substring(0, slash);
    docId = Uri.decodeComponent(docId); // e.g. "primary:Documents/telemetry_logs"
    final colon = docId.indexOf(':');
    if (colon < 0) return docId.isEmpty ? null : docId;
    final volume = docId.substring(0, colon);
    final path = docId.substring(colon + 1);
    // "primary"/"raw" are the internal-storage roots — drop the noise prefix.
    if (volume == 'primary' || volume == 'raw') {
      return path.isEmpty ? volume : path;
    }
    return path.isEmpty ? volume : '$volume:$path';
  }

  Future<String?> _validSavedUri() async {
    final uri = PrefsManager.instance.getString(_uriKey);
    if (uri == null || uri.isEmpty) return null;
    try {
      if (await _safUtil.exists(uri, true)) return uri;
    } catch (_) {
      // Permission revoked or folder gone — fall through to re-pick.
    }
    return null;
  }

  /// Prompt for a directory and persist it. Returns its tree URI, or null if
  /// the user cancelled.
  Future<String?> pickDirectory() async {
    final dir = await _safUtil.pickDirectory(
      writePermission: true,
      persistablePermission: true,
    );
    if (dir == null) return null;
    await PrefsManager.instance.setString(_uriKey, dir.uri);
    await PrefsManager.instance.setString(_nameKey, dir.name);
    return dir.uri;
  }

  /// The remembered directory if still accessible, otherwise prompt for one.
  Future<String?> resolveDirectory() async {
    return await _validSavedUri() ?? await pickDirectory();
  }

  /// Write each entry into [treeUri], overwriting same-named files so a resumed
  /// pull updates the existing file rather than creating duplicates.
  Future<void> writeEntries(
    String treeUri,
    List<TelemetryExportEntry> entries,
  ) async {
    for (final entry in entries) {
      await _safStream.writeFileBytes(
        treeUri,
        entry.name,
        entry.mime,
        entry.bytes,
        overwrite: true,
      );
      appLogger.info('Exported ${entry.name} to SAF folder', tag: 'TelemLog');
    }
  }

  // --- Shared resume state (cross-device) ---------------------------------
  //
  // When the export folder is synced between devices, the `.state.json` and
  // `.telemetry` files there form a shared source of truth: whichever device
  // pulled last leaves its offset, so the next device resumes from there. These
  // read/write the synced copies directly via SAF.

  String _short(String repeaterHex) =>
      repeaterHex.length >= 8 ? repeaterHex.substring(0, 8) : repeaterHex;

  /// Parse the synced `<repeater8>.state.json`, or null if there's no remembered
  /// folder / no state file / it can't be read.
  Future<TelemetryLogSession?> readSharedSession(String repeaterHex) async {
    final treeUri = await _validSavedUri();
    if (treeUri == null) return null;
    try {
      final doc = await _safUtil.child(treeUri, ['${_short(repeaterHex)}.state.json']);
      if (doc == null) return null;
      final bytes = await _safStream.readFileBytes(doc.uri);
      return TelemetryLogSession.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (e) {
      appLogger.warn('Failed reading shared telemetry state: $e', tag: 'TelemLog');
      return null;
    }
  }

  /// Read the synced `.telemetry` bytes for [sessionFilename], or null.
  Future<Uint8List?> readSharedBytes(String sessionFilename) async {
    final treeUri = await _validSavedUri();
    if (treeUri == null) return null;
    try {
      final doc = await _safUtil.child(treeUri, [sessionFilename]);
      if (doc == null) return null;
      return await _safStream.readFileBytes(doc.uri);
    } catch (e) {
      appLogger.warn('Failed reading shared telemetry bytes: $e', tag: 'TelemLog');
      return null;
    }
  }

  /// Write the resume [session] + assembled [bytes] back to the synced folder so
  /// the next device sees the advanced offset. No-op if no folder is remembered.
  Future<void> writeShared(
    String repeaterHex,
    TelemetryLogSession session,
    Uint8List bytes,
  ) async {
    final treeUri = await _validSavedUri();
    if (treeUri == null) return;
    try {
      await _safStream.writeFileBytes(
        treeUri,
        session.sessionFilename,
        'application/octet-stream',
        bytes,
        overwrite: true,
      );
      await _safStream.writeFileBytes(
        treeUri,
        '${_short(repeaterHex)}.state.json',
        'application/json',
        Uint8List.fromList(utf8.encode(jsonEncode(session.toJson()))),
        overwrite: true,
      );
    } catch (e) {
      appLogger.warn('Failed writing shared telemetry state: $e', tag: 'TelemLog');
    }
  }
}
