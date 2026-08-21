class MeshCoreUuids {
  static const String service = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
  static const String rxCharacteristic = "6e400002-b5a3-f393-e0a9-e50e24dcca9e";
  static const String txCharacteristic = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";

  /// Known advertised-name prefixes used by MeshCore firmware builds.
  static const List<String> deviceNamePrefixes = [
    "MeshCore-",
    "Whisper-",
    "WisCore-",
    "Seeed",
    "Lilygo",
    "HT-",
    "LowMesh_MC_",
    "NRF52",
  ];

  static bool isKnownDeviceName(String name) {
    return deviceNamePrefixes.any(name.startsWith);
  }

  /// A desktop BLE backend may populate either name (and can leave the other
  /// empty), so accept a device when either source identifies it as MeshCore.
  static bool matchesDeviceNames({
    required String platformName,
    required String advertisedName,
  }) {
    return isKnownDeviceName(platformName) || isKnownDeviceName(advertisedName);
  }
}
