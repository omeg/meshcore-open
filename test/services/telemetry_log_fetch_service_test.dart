import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/telemetry_log.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/influxdb_telemetry_service.dart';
import 'package:meshcore_open/services/telemetry_log_fetch_service.dart';
import 'package:meshcore_open/services/telemetry_saf_export.dart';
import 'package:meshcore_open/storage/telemetry_log_store.dart';

void main() {
  test(
    'refresh resumes a completed telemetry log and fetches appended tail',
    () async {
      final repeater = _repeater();
      final connector = _FakeTelemetryConnector();
      final store = _MemoryTelemetryLogStore();
      final service = TelemetryLogFetchService(connector, store: store);
      service.addListener(() {});

      connector.logBytes = _sampleLog(sampleCount: 2);
      await service.fetch(repeater, chunkSize: 35);

      expect(service.status, TelemetryLogFetchStatus.done);
      expect(service.log!.iterSamples().length, 2);
      expect(store.savedBytes!.length, connector.logBytes.length);

      final firstSavedLength = store.savedBytes!.length;
      connector.requestedOffsets.clear();
      connector.logBytes = _sampleLog(sampleCount: 3);

      await service.fetch(repeater, chunkSize: 35);

      expect(service.status, TelemetryLogFetchStatus.done);
      expect(service.resumed, isTrue);
      expect(service.log!.iterSamples().length, 3);
      expect(store.savedBytes!.length, greaterThan(firstSavedLength));
      expect(connector.requestedOffsets, contains(firstSavedLength));
    },
  );

  test('cancel interrupts an in-flight telemetry chunk wait', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()..respondToRequests = false;
    final store = _MemoryTelemetryLogStore();
    final service = TelemetryLogFetchService(connector, store: store);
    service.addListener(() {});

    final fetchFuture = service.fetch(repeater, chunkSize: 35);
    for (var i = 0; i < 20 && connector.requestedOffsets.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(connector.requestedOffsets, isNotEmpty);

    service.cancel();

    await fetchFuture.timeout(const Duration(milliseconds: 500));
    expect(service.status, TelemetryLogFetchStatus.idle);
    expect(service.errorMessage, isNull);
  });

  test('successful fetch auto-exports to configured mobile folder', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()
      ..logBytes = _sampleLog(sampleCount: 2);
    final store = _MemoryTelemetryLogStore();
    final safExport = _MemoryTelemetrySafExport();
    final service = TelemetryLogFetchService(
      connector,
      store: store,
      safExport: safExport,
      supportsMobileExportFolder: () => true,
    );
    service.addListener(() {});

    await service.fetch(repeater, chunkSize: 35);

    expect(service.status, TelemetryLogFetchStatus.done);
    expect(safExport.writes, hasLength(1));
    expect(safExport.writes.single.map((e) => e.name), [
      store.session!.sessionFilename,
      '${repeater.publicKeyHex.substring(0, 8)}.state.json',
    ]);
    expect(safExport.writes.single.first.bytes, connector.logBytes);
  });

  test('successful fetch auto-imports to configured InfluxDB', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()
      ..logBytes = _sampleLog(sampleCount: 2);
    final store = _MemoryTelemetryLogStore();
    final influx = _FakeInfluxDbTelemetryService(store: store);
    final service = TelemetryLogFetchService(
      connector,
      store: store,
      influxSettings: () => _influxSettings,
      influxServiceFactory: (_) => influx,
    );
    service.addListener(() {});

    await service.fetch(repeater, chunkSize: 35);

    expect(service.status, TelemetryLogFetchStatus.done);
    expect(influx.importedPaths, ['/memory/${store.session!.sessionFilename}']);
    expect(influx.importedNodes, [repeater.publicKeyHex]);
    expect(influx.importedSettings, [_influxSettings]);
    expect(influx.closed, isTrue);
    expect(service.influxImportStatus, TelemetryInfluxImportStatus.imported);
    expect(service.influxImportTicks, 2);
    expect(service.influxImportPoints, 2);
    expect(service.influxImportGeneration, 1);
  });

  test('successful fetch skips InfluxDB when it is not configured', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()
      ..logBytes = _sampleLog(sampleCount: 2);
    final store = _MemoryTelemetryLogStore();
    final influx = _FakeInfluxDbTelemetryService(store: store);
    final service = TelemetryLogFetchService(
      connector,
      store: store,
      influxSettings: () => const InfluxDbSettings(),
      influxServiceFactory: (_) => influx,
    );
    service.addListener(() {});

    await service.fetch(repeater, chunkSize: 35);

    expect(service.status, TelemetryLogFetchStatus.done);
    expect(influx.importedPaths, isEmpty);
    expect(influx.closed, isFalse);
    expect(
      service.influxImportStatus,
      TelemetryInfluxImportStatus.notAttempted,
    );
    expect(service.influxImportGeneration, 0);
  });

  test('successful fetch reports InfluxDB already up to date', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()
      ..logBytes = _sampleLog(sampleCount: 2);
    final store = _MemoryTelemetryLogStore();
    final influx = _FakeInfluxDbTelemetryService(store: store)
      ..result = const InfluxDbImportResult(
        ticks: 0,
        points: 0,
        alreadyUpToDate: true,
      );
    final service = TelemetryLogFetchService(
      connector,
      store: store,
      influxSettings: () => _influxSettings,
      influxServiceFactory: (_) => influx,
    );
    service.addListener(() {});

    await service.fetch(repeater, chunkSize: 35);

    expect(service.status, TelemetryLogFetchStatus.done);
    expect(service.influxImportStatus, TelemetryInfluxImportStatus.upToDate);
    expect(service.influxImportGeneration, 1);
  });

  test('InfluxDB auto-import failure does not fail the fetch', () async {
    final repeater = _repeater();
    final connector = _FakeTelemetryConnector()
      ..logBytes = _sampleLog(sampleCount: 2);
    final store = _MemoryTelemetryLogStore();
    final influx = _FakeInfluxDbTelemetryService(store: store)
      ..error = const InfluxDbException('offline');
    final service = TelemetryLogFetchService(
      connector,
      store: store,
      influxSettings: () => _influxSettings,
      influxServiceFactory: (_) => influx,
    );
    service.addListener(() {});

    await service.fetch(repeater, chunkSize: 35);

    expect(service.status, TelemetryLogFetchStatus.done);
    expect(service.errorMessage, isNull);
    expect(influx.importedPaths, hasLength(1));
    expect(influx.closed, isTrue);
    expect(service.influxImportStatus, TelemetryInfluxImportStatus.failed);
    expect(service.influxImportError, 'offline');
    expect(service.influxImportGeneration, 1);
  });
}

const _influxSettings = InfluxDbSettings(
  url: 'http://influx.local:8086',
  token: 'secret',
  organization: 'mesh',
  bucket: 'telemetry',
);

Contact _repeater() {
  return Contact(
    publicKey: Uint8List.fromList(List<int>.generate(pubKeySize, (i) => i + 1)),
    name: 'Repeater',
    type: advTypeRepeater,
    pathLength: 0,
    path: Uint8List(0),
    lastSeen: DateTime.utc(2026, 1, 1),
  );
}

Uint8List _sampleLog({required int sampleCount}) {
  final writer = BufferWriter();
  writer.writeBytes(Uint8List.fromList(telemetryLogMagic));
  writer.writeByte(telemetryLogVersion);
  writer.writeByte(1); // channel count
  writer.writeUInt16LE(2); // timestamp stride
  writer.writeUInt32LE(60); // interval seconds
  writer.writeByte(1); // LPP channel
  writer.writeUInt16LE(telemLogVoltage);
  final name = Uint8List(telemetryLogChannelNameLen);
  name.setRange(0, 3, 'bat'.codeUnits);
  writer.writeBytes(name);

  for (var i = 0; i < sampleCount; i++) {
    if (i % 2 == 0) {
      writer.writeUInt32LE(1700000000 + i * 60);
    }
    writer.writeByte(100 + i);
  }
  return writer.toBytes();
}

class _FakeTelemetryConnector extends MeshCoreConnector {
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();
  final List<int> requestedOffsets = [];
  Uint8List logBytes = Uint8List(0);
  bool respondToRequests = true;
  int _tag = 0xAABB0000;

  @override
  bool get isConnected => true;

  @override
  Stream<Uint8List> get receivedFrames => _frames.stream;

  @override
  Future<PathSelection> preparePathForContactSend(Contact contact) async {
    return const PathSelection(pathBytes: [], hopCount: 0, useFlood: false);
  }

  @override
  Future<void> sendFrame(
    Uint8List data, {
    String? channelSendQueueId,
    bool expectsGenericAck = false,
    bool waitForGenericAck = false,
  }) async {
    final reader = BufferReader(data);
    expect(reader.readByte(), cmdSendBinaryReq);
    reader.skipBytes(pubKeySize);
    expect(reader.readByte(), reqTypeGetTelemetryLog);
    expect(reader.readByte(), telemLogReqVersion);
    final requestedLen = reader.readByte();
    reader.skipBytes(1); // reserved
    final offset = reader.readUInt32LE();
    reader.skipBytes(4); // nonce
    requestedOffsets.add(offset);

    final tag = _tag++;
    _frames.add(_sentFrame(tag));
    if (respondToRequests) {
      _frames.add(_telemetryResponse(tag, offset, requestedLen));
    }
  }

  Uint8List _sentFrame(int tag) {
    final writer = BufferWriter()
      ..writeByte(respCodeSent)
      ..writeByte(0)
      ..writeUInt32LE(tag);
    return writer.toBytes();
  }

  Uint8List _telemetryResponse(int tag, int offset, int requestedLen) {
    final available = offset >= logBytes.length
        ? 0
        : (logBytes.length - offset).clamp(0, requestedLen);
    final writer = BufferWriter()
      ..writeByte(pushCodeBinaryResponse)
      ..writeByte(0)
      ..writeUInt32LE(tag)
      ..writeByte(respTelemLogOk | telemLogActiveFlag)
      ..writeByte(telemLogRespVersion)
      ..writeByte(available)
      ..writeUInt32LE(logBytes.length)
      ..writeUInt32LE(offset)
      ..writeUInt32LE(logBytes.length - offset - available);
    if (available > 0) {
      writer.writeBytes(
        Uint8List.sublistView(logBytes, offset, offset + available),
      );
    }
    return writer.toBytes();
  }
}

class _MemoryTelemetryLogStore extends TelemetryLogStore {
  TelemetryLogSession? session;
  Uint8List? savedBytes;

  @override
  Future<TelemetryLogSession?> loadSession(String repeaterHex) async => session;

  @override
  Future<Uint8List?> loadBytes(String filename) async {
    if (filename != session?.sessionFilename) return null;
    return savedBytes;
  }

  @override
  Future<String?> saveSession(
    String repeaterHex,
    TelemetryLogSession session,
    Uint8List bytes,
  ) async {
    this.session = session;
    savedBytes = Uint8List.fromList(bytes);
    return '/memory/${session.sessionFilename}';
  }

  @override
  Future<String?> currentFilePath(String repeaterHex) async {
    final filename = session?.sessionFilename;
    return filename == null ? null : '/memory/$filename';
  }

  @override
  Future<List<TelemetryExportEntry>> exportPayload(
    String telemetryPath,
    String repeaterHex,
  ) async {
    final currentSession = session;
    final currentBytes = savedBytes;
    if (currentSession == null || currentBytes == null) return const [];
    return [
      TelemetryExportEntry(
        name: currentSession.sessionFilename,
        bytes: Uint8List.fromList(currentBytes),
        mime: 'application/octet-stream',
      ),
      TelemetryExportEntry(
        name: '${repeaterHex.substring(0, 8)}.state.json',
        bytes: Uint8List.fromList(
          utf8.encode(jsonEncode(currentSession.toJson())),
        ),
        mime: 'application/json',
      ),
    ];
  }
}

class _MemoryTelemetrySafExport extends TelemetrySafExport {
  final List<List<TelemetryExportEntry>> writes = [];

  @override
  Future<String?> configuredDirectoryUri() async => 'content://memory/tree';

  @override
  Future<void> writeEntries(
    String treeUri,
    List<TelemetryExportEntry> entries,
  ) async {
    writes.add(entries);
  }

  @override
  Future<TelemetryLogSession?> readSharedSession(String repeaterHex) async {
    return null;
  }

  @override
  Future<Uint8List?> readSharedBytes(String sessionFilename) async {
    return null;
  }

  @override
  Future<void> writeShared(
    String repeaterHex,
    TelemetryLogSession session,
    Uint8List bytes,
  ) async {}
}

class _FakeInfluxDbTelemetryService extends InfluxDbTelemetryService {
  _FakeInfluxDbTelemetryService({required super.store});

  final List<String> importedPaths = [];
  final List<String> importedNodes = [];
  final List<InfluxDbSettings> importedSettings = [];
  InfluxDbImportResult result = const InfluxDbImportResult(ticks: 2, points: 2);
  Object? error;
  bool closed = false;

  @override
  Future<InfluxDbImportResult> importFile({
    required String path,
    required String node,
    required InfluxDbSettings settings,
  }) async {
    importedPaths.add(path);
    importedNodes.add(node);
    importedSettings.add(settings);
    if (error != null) throw error!;
    return result;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}
