import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/telemetry_log.dart';
import 'package:meshcore_open/models/contact.dart';
import 'package:meshcore_open/models/path_selection.dart';
import 'package:meshcore_open/services/telemetry_log_fetch_service.dart';
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
}

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
}
