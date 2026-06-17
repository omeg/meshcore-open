import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import '../utils/platform_info.dart';

class StateSyncFolder {
  final String id;
  final String name;
  final String displayPath;

  const StateSyncFolder({
    required this.id,
    required this.name,
    required this.displayPath,
  });
}

class StateSyncBackend {
  final SafUtil _safUtil = SafUtil();
  final SafStream _safStream = SafStream();

  bool get isSupported => PlatformInfo.isAndroid || PlatformInfo.isDesktop;

  Future<StateSyncFolder?> pickFolder() async {
    if (PlatformInfo.isAndroid) {
      final dir = await _safUtil.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (dir == null) return null;
      return StateSyncFolder(
        id: dir.uri,
        name: dir.name,
        displayPath: _treePathFromUri(dir.uri) ?? dir.name,
      );
    }

    if (PlatformInfo.isDesktop) {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose MeshCore sync folder',
      );
      if (path == null || path.isEmpty) return null;
      return StateSyncFolder(
        id: path,
        name: path.split(Platform.pathSeparator).last,
        displayPath: path,
      );
    }

    return null;
  }

  Future<bool> folderExists(String id) async {
    if (id.isEmpty) return false;
    if (PlatformInfo.isAndroid) {
      try {
        return await _safUtil.exists(id, true);
      } catch (_) {
        return false;
      }
    }
    if (PlatformInfo.isDesktop) {
      return Directory(id).exists();
    }
    return false;
  }

  Future<Map<String, dynamic>?> readJson(String folderId, String name) async {
    if (PlatformInfo.isAndroid) {
      final doc = await _safUtil.child(folderId, [name]);
      if (doc == null) return null;
      final bytes = await _safStream.readFileBytes(doc.uri);
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    }

    if (PlatformInfo.isDesktop) {
      final file = File(_join(folderId, name));
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }

    return null;
  }

  Future<void> writeJson(
    String folderId,
    String name,
    Map<String, dynamic> json,
  ) async {
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );

    if (PlatformInfo.isAndroid) {
      await _safStream.writeFileBytes(
        folderId,
        name,
        'application/json',
        bytes,
        overwrite: true,
      );
      return;
    }

    if (PlatformInfo.isDesktop) {
      final file = File(_join(folderId, name));
      await file.writeAsBytes(bytes, flush: true);
    }
  }

  String _join(String dir, String name) {
    final sep = Platform.pathSeparator;
    return dir.endsWith(sep) ? '$dir$name' : '$dir$sep$name';
  }

  String? _treePathFromUri(String uri) {
    const marker = '/tree/';
    final idx = uri.indexOf(marker);
    if (idx < 0) return null;
    var docId = uri.substring(idx + marker.length);
    final slash = docId.indexOf('/');
    if (slash >= 0) docId = docId.substring(0, slash);
    docId = Uri.decodeComponent(docId);
    final colon = docId.indexOf(':');
    if (colon < 0) return docId.isEmpty ? null : docId;
    final volume = docId.substring(0, colon);
    final path = docId.substring(colon + 1);
    if (volume == 'primary' || volume == 'raw') {
      return path.isEmpty ? volume : path;
    }
    return path.isEmpty ? volume : '$volume:$path';
  }
}
