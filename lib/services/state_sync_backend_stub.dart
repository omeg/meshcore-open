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
  bool get isSupported => false;

  Future<StateSyncFolder?> pickFolder() async => null;

  Future<bool> folderExists(String id) async => false;

  Future<Map<String, dynamic>?> readJson(String folderId, String name) async {
    return null;
  }

  Future<void> writeJson(
    String folderId,
    String name,
    Map<String, dynamic> json,
  ) async {}
}
