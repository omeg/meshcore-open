class StartupOptions {
  final String? bleAddress;

  const StartupOptions({this.bleAddress});

  static StartupOptions parse(List<String> args) {
    String? bleAddress;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String? value;
      if (arg == '--ble-address' || arg == '--ble-addr') {
        if (i + 1 >= args.length) {
          throw const FormatException('--ble-address requires a value');
        }
        value = args[++i];
      } else if (arg.startsWith('--ble-address=')) {
        value = arg.substring('--ble-address='.length);
      } else if (arg.startsWith('--ble-addr=')) {
        value = arg.substring('--ble-addr='.length);
      }

      if (value != null) {
        bleAddress = normalizeBleAddress(value);
      }
    }
    return StartupOptions(bleAddress: bleAddress);
  }

  static String normalizeBleAddress(String value) {
    final trimmed = value.trim();
    final pattern = RegExp(r'^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$');
    if (!pattern.hasMatch(trimmed)) {
      throw FormatException('invalid BLE address: $value');
    }
    return trimmed.toUpperCase();
  }
}
