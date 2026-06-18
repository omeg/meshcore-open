import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meshcore_open/helpers/telemetry_log.dart';
import 'package:meshcore_open/models/app_settings.dart';
import 'package:meshcore_open/services/influxdb_telemetry_service.dart';
import 'package:meshcore_open/storage/telemetry_log_store.dart';

const _settings = InfluxDbSettings(
  url: 'http://influx.local:8086',
  token: 'secret',
  organization: 'mesh org',
  bucket: 'meshcore',
);

void main() {
  test('InfluxDB settings round-trip through AppSettings JSON', () {
    final settings = AppSettings(influxDb: _settings);
    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.influxDb.url, _settings.url);
    expect(restored.influxDb.token, _settings.token);
    expect(restored.influxDb.organization, _settings.organization);
    expect(restored.influxDb.bucket, _settings.bucket);
    expect(restored.influxDb.isConfigured, isTrue);
  });

  test('writes Python-compatible line protocol and resumes imports', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/api/v2/buckets') {
        return http.Response('{"buckets":[{"id":"bucket-id"}]}', 200);
      }
      if (request.method == 'POST' && request.url.path == '/api/v2/write') {
        return http.Response('', 204);
      }
      return http.Response('unexpected request', 500);
    });
    final store = _MemoryTelemetryStore();
    final service = InfluxDbTelemetryService(client: client, store: store);
    final dir = await Directory.systemTemp.createTemp('influx-import-');
    final file = File('${dir.path}/17732a37-session.telemetry');
    await file.writeAsBytes(_buildSampleLog());

    try {
      final first = await service.importFile(
        path: file.path,
        node:
            '17732a3700000000000000000000000000000000000000000000000000000000',
        settings: _settings,
      );
      expect(first.ticks, 3);
      expect(first.points, 5);

      final write = requests.singleWhere(
        (request) =>
            request.method == 'POST' && request.url.path == '/api/v2/write',
      );
      expect(write.headers['authorization'], 'Token secret');
      expect(write.url.queryParameters['org'], 'mesh org');
      expect(write.url.queryParameters['precision'], 's');
      final lines = write.body.split('\n');
      expect(lines, hasLength(5));
      expect(
        lines.first,
        startsWith(
          'telemetry,node=17732a3700000000000000000000000000000000000000000000000000000000,'
          'channel=0,channel_name=self voltage_v=4.1,noise_dbm=-100.0 '
          '1700000000',
        ),
      );
      expect(
        lines[1],
        contains(
          'channel=1,channel_name=env temperature_c=23.4,humidity_pct=55.0',
        ),
      );
      expect(store.state['last_imported_sample'], 3);

      final second = await service.importFile(
        path: file.path,
        node:
            '17732a3700000000000000000000000000000000000000000000000000000000',
        settings: _settings,
      );
      expect(second.alreadyUpToDate, isTrue);
      expect(second.points, 0);
      expect(
        requests
            .where(
              (request) =>
                  request.method == 'POST' &&
                  request.url.path == '/api/v2/write',
            )
            .length,
        1,
      );
    } finally {
      service.close();
      await dir.delete(recursive: true);
    }
  });

  test('creates a missing bucket with configured retention', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/api/v2/buckets') {
        return http.Response('{"buckets":[]}', 200);
      }
      if (request.method == 'GET' && request.url.path == '/api/v2/orgs') {
        return http.Response(
          '{"orgs":[{"id":"org-id","name":"mesh org"}]}',
          200,
        );
      }
      if (request.method == 'POST' && request.url.path == '/api/v2/buckets') {
        return http.Response('{"id":"bucket-id"}', 201);
      }
      return http.Response('unexpected request', 500);
    });
    final service = InfluxDbTelemetryService(client: client);

    await service.testConnection(
      const InfluxDbSettings(
        url: 'http://influx.local:8086',
        token: 'secret',
        organization: 'mesh org',
        bucket: 'meshcore',
        retentionSeconds: 86400,
      ),
    );

    final create = requests.last;
    final body = jsonDecode(create.body) as Map<String, dynamic>;
    expect(body['name'], 'meshcore');
    expect(body['orgID'], 'org-id');
    expect((body['retentionRules'] as List).single, {
      'type': 'expire',
      'everySeconds': 86400,
    });
  });
}

class _MemoryTelemetryStore extends TelemetryLogStore {
  Map<String, dynamic> state = {};

  @override
  Future<Map<String, dynamic>> loadStateData(String repeaterHex) async =>
      Map<String, dynamic>.from(state);

  @override
  Future<void> updateStateData(
    String repeaterHex,
    Map<String, dynamic> updates,
  ) async {
    state = {...state, ...updates};
  }
}

Uint8List _buildSampleLog() {
  final b = BytesBuilder();
  b.add(telemetryLogMagic);
  b.addByte(telemetryLogVersion);
  b.addByte(2);
  _u16(b, 2);
  _u32(b, 60);
  b.addByte(0);
  _u16(b, telemLogVoltage | telemLogNoise);
  b.add(_name('self'));
  b.addByte(1);
  _u16(b, telemLogTemperature | telemLogHumidity);
  b.add(_name('env'));

  _u32(b, 1700000000);
  b.addByte(160);
  b.addByte(50);
  _i16(b, 234);
  b.addByte(110);

  b.addByte(0);
  b.addByte(60);
  _i16(b, 0x7FFF);
  b.addByte(0xFF);

  _u32(b, 1700000200);
  b.addByte(170);
  b.addByte(40);
  _i16(b, 200);
  b.addByte(100);
  return b.toBytes();
}

Uint8List _name(String value) {
  final bytes = Uint8List(telemetryLogChannelNameLen);
  for (var i = 0; i < value.length; i++) {
    bytes[i] = value.codeUnitAt(i);
  }
  return bytes;
}

void _u16(BytesBuilder builder, int value) {
  final bytes = Uint8List(2);
  ByteData.sublistView(bytes).setUint16(0, value, Endian.little);
  builder.add(bytes);
}

void _u32(BytesBuilder builder, int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.little);
  builder.add(bytes);
}

void _i16(BytesBuilder builder, int value) {
  final bytes = Uint8List(2);
  ByteData.sublistView(bytes).setInt16(0, value, Endian.little);
  builder.add(bytes);
}
