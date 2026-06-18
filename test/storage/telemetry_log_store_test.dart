import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/storage/telemetry_log_store.dart';

void main() {
  group('TelemetryLogStore desktop export', () {
    late Directory sourceDir;
    late Directory destinationDir;
    late File telemetry;
    late File state;
    late _TestTelemetryLogStore store;

    setUp(() async {
      sourceDir = await Directory.systemTemp.createTemp('telemetry-source-');
      destinationDir = await Directory.systemTemp.createTemp(
        'telemetry-destination-',
      );
      telemetry = File('${sourceDir.path}/17732a37-session.telemetry');
      state = File('${sourceDir.path}/17732a37.state.json');
      await telemetry.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
      await state.writeAsString('{"pubkey":"17732a37"}');
      store = _TestTelemetryLogStore(state.path);
    });

    tearDown(() async {
      if (sourceDir.existsSync()) await sourceDir.delete(recursive: true);
      if (destinationDir.existsSync()) {
        await destinationDir.delete(recursive: true);
      }
    });

    test(
      'does not truncate files when exporting to their own folder',
      () async {
        final telemetryBefore = await telemetry.readAsBytes();
        final stateBefore = await state.readAsBytes();

        final exported = await store.exportSessionTo(
          '${sourceDir.path}/.',
          telemetry.path,
          '17732a37',
        );

        expect(exported, ['17732a37-session.telemetry', '17732a37.state.json']);
        expect(await telemetry.readAsBytes(), telemetryBefore);
        expect(await state.readAsBytes(), stateBefore);
      },
    );

    test('copies both files to a different folder', () async {
      final exported = await store.exportSessionTo(
        destinationDir.path,
        telemetry.path,
        '17732a37',
      );

      expect(exported, ['17732a37-session.telemetry', '17732a37.state.json']);
      expect(
        await File(
          '${destinationDir.path}/17732a37-session.telemetry',
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(
        await File('${destinationDir.path}/17732a37.state.json').readAsString(),
        '{"pubkey":"17732a37"}',
      );
    });
  });
}

class _TestTelemetryLogStore extends TelemetryLogStore {
  final String statePath;

  _TestTelemetryLogStore(this.statePath);

  @override
  Future<String?> stateFilePath(String repeaterHex) async => statePath;
}
