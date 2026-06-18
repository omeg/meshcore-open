import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../helpers/telemetry_log.dart';
import '../models/app_settings.dart';
import '../storage/telemetry_log_store.dart';

class InfluxDbImportResult {
  final int ticks;
  final int points;
  final bool alreadyUpToDate;

  const InfluxDbImportResult({
    required this.ticks,
    required this.points,
    this.alreadyUpToDate = false,
  });
}

class InfluxDbException implements Exception {
  final String message;
  const InfluxDbException(this.message);

  @override
  String toString() => message;
}

/// Imports MeshCore `.telemetry` logs into InfluxDB v2 using the same schema
/// and importer state fields as firmware/telemetry/telem_import.py.
class InfluxDbTelemetryService {
  static const String measurement = 'telemetry';
  static const int _batchSize = 5000;
  static const Duration _requestTimeout = Duration(seconds: 20);

  final http.Client _client;
  final bool _ownsClient;
  final TelemetryLogStore _store;

  InfluxDbTelemetryService({http.Client? client, TelemetryLogStore? store})
    : _client = client ?? http.Client(),
      _ownsClient = client == null,
      _store = store ?? TelemetryLogStore();

  void close() {
    if (_ownsClient) _client.close();
  }

  Future<void> testConnection(InfluxDbSettings settings) async {
    _validateSettings(settings);
    await _ensureBucket(settings);
  }

  Future<InfluxDbImportResult> importFile({
    required String path,
    required String node,
    required InfluxDbSettings settings,
  }) async {
    _validateSettings(settings);
    final bytes = await File(path).readAsBytes();
    final log = TelemetryLog(bytes);
    final filename = File(path).uri.pathSegments.last;
    final state = await _store.loadStateData(node);

    final storedFilename = state['last_imported_log_filename'] as String? ?? '';
    final storedOffset = (state['last_imported_offset'] as num?)?.toInt() ?? 0;
    final storedSample = (state['last_imported_sample'] as num?)?.toInt() ?? 0;
    final alignedBody = telemetryAlignedByteCount(
      bytes.length - log.bodyOffset,
      0,
      log.header.timestampStride,
      log.recordSize,
    );
    final alignedLength = log.bodyOffset + alignedBody;
    final sameSession =
        storedFilename == filename &&
        storedOffset >= log.bodyOffset &&
        storedOffset <= alignedLength &&
        storedSample > 0;

    if (sameSession && storedOffset == alignedLength) {
      return const InfluxDbImportResult(
        ticks: 0,
        points: 0,
        alreadyUpToDate: true,
      );
    }

    final startSample = sameSession ? storedSample : 0;
    final allTicks = log.iterSamples().toList();
    final ticks = allTicks
        .where(
          (tick) => tick.isNotEmpty && tick.first.sampleIndex >= startSample,
        )
        .toList();
    if (ticks.isEmpty) {
      return const InfluxDbImportResult(ticks: 0, points: 0);
    }

    await _ensureBucket(settings);
    final lines = buildLineProtocol(
      node: node.trim().toLowerCase(),
      channels: log.channels,
      ticks: ticks,
    );
    for (var start = 0; start < lines.length; start += _batchSize) {
      final end = min(start + _batchSize, lines.length);
      await _writeLines(settings, lines.sublist(start, end));
    }

    var lastAnchorTs = 0;
    var lastAnchorIndex = 0;
    for (final tick in allTicks) {
      if (tick.isNotEmpty && tick.first.isAnchor) {
        lastAnchorTs = tick.first.timestamp;
        lastAnchorIndex = tick.first.sampleIndex;
      }
    }
    await _store.updateStateData(node, {
      'last_imported_log_filename': filename,
      'last_imported_offset': alignedLength,
      'last_imported_sample': allTicks.last.first.sampleIndex + 1,
      'last_imported_anchor_ts': lastAnchorTs,
      'last_imported_anchor_index': lastAnchorIndex,
      'import_updated_at': _utcSeconds(DateTime.now()),
    });

    return InfluxDbImportResult(ticks: ticks.length, points: lines.length);
  }

  static List<String> buildLineProtocol({
    required String node,
    required List<TelemetryChannel> channels,
    required List<List<TelemetrySample>> ticks,
  }) {
    final names = {
      for (final channel in channels) channel.lppChannel: channel.name,
    };
    final lines = <String>[];
    for (final tick in ticks) {
      for (final sample in tick) {
        final fields = <String, num?>{
          'voltage_v': sample.voltageV,
          'noise_dbm': sample.noiseDbm,
          'temperature_c': sample.temperatureC,
          'pressure_hpa': sample.pressureHpa,
          'humidity_pct': sample.humidityPct,
          'current_a': sample.currentA,
          'luminosity_lux': sample.luminosityLux,
          'rain': sample.rain,
        };
        fields.removeWhere((_, value) => value == null);
        if (fields.isEmpty) continue;

        final tags = StringBuffer()
          ..write('$measurement,node=${_escapeTag(node)}')
          ..write(',channel=${_escapeTag(sample.lppChannel.toString())}');
        final channelName = names[sample.lppChannel] ?? '';
        if (channelName.isNotEmpty) {
          tags.write(',channel_name=${_escapeTag(channelName)}');
        }
        final fieldSet = fields.entries
            .map((entry) => '${entry.key}=${entry.value!.toDouble()}')
            .join(',');
        lines.add('$tags $fieldSet ${sample.timestamp}');
      }
    }
    return lines;
  }

  Future<void> _ensureBucket(InfluxDbSettings settings) async {
    final bucketsUri = _apiUri(settings, '/api/v2/buckets', {
      'name': settings.bucket.trim(),
    });
    final bucketsResponse = await _client
        .get(bucketsUri, headers: _headers(settings))
        .timeout(_requestTimeout);
    _requireSuccess(bucketsResponse, 'check InfluxDB bucket');
    final bucketsJson =
        jsonDecode(bucketsResponse.body) as Map<String, dynamic>;
    final buckets = bucketsJson['buckets'] as List<dynamic>? ?? const [];
    if (buckets.isNotEmpty) return;

    final orgsResponse = await _client
        .get(
          _apiUri(settings, '/api/v2/orgs', {
            'org': settings.organization.trim(),
          }),
          headers: _headers(settings),
        )
        .timeout(_requestTimeout);
    _requireSuccess(orgsResponse, 'find InfluxDB organization');
    final orgsJson = jsonDecode(orgsResponse.body) as Map<String, dynamic>;
    final orgs = orgsJson['orgs'] as List<dynamic>? ?? const [];
    if (orgs.isEmpty) {
      throw InfluxDbException(
        'InfluxDB organization not found: ${settings.organization}',
      );
    }
    final orgId = (orgs.first as Map<String, dynamic>)['id'] as String?;
    if (orgId == null || orgId.isEmpty) {
      throw const InfluxDbException('InfluxDB organization has no ID');
    }

    final retentionRules = settings.retentionSeconds > 0
        ? [
            {'type': 'expire', 'everySeconds': settings.retentionSeconds},
          ]
        : const <Map<String, dynamic>>[];
    final createResponse = await _client
        .post(
          _apiUri(settings, '/api/v2/buckets'),
          headers: {
            ..._headers(settings),
            HttpHeaders.contentTypeHeader: 'application/json',
          },
          body: jsonEncode({
            'name': settings.bucket.trim(),
            'orgID': orgId,
            'retentionRules': retentionRules,
          }),
        )
        .timeout(_requestTimeout);
    _requireSuccess(createResponse, 'create InfluxDB bucket');
  }

  Future<void> _writeLines(
    InfluxDbSettings settings,
    List<String> lines,
  ) async {
    if (lines.isEmpty) return;
    final response = await _client
        .post(
          _apiUri(settings, '/api/v2/write', {
            'org': settings.organization.trim(),
            'bucket': settings.bucket.trim(),
            'precision': 's',
          }),
          headers: {
            ..._headers(settings),
            HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8',
          },
          body: lines.join('\n'),
        )
        .timeout(_requestTimeout);
    _requireSuccess(response, 'write telemetry to InfluxDB');
  }

  Map<String, String> _headers(InfluxDbSettings settings) => {
    HttpHeaders.authorizationHeader: 'Token ${settings.token.trim()}',
    HttpHeaders.acceptHeader: 'application/json',
  };

  Uri _apiUri(
    InfluxDbSettings settings,
    String path, [
    Map<String, String>? query,
  ]) {
    final base = Uri.parse(settings.url.trim());
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path', queryParameters: query);
  }

  void _validateSettings(InfluxDbSettings settings) {
    if (!settings.isConfigured) {
      throw const InfluxDbException(
        'InfluxDB URL, token, organization, and bucket are required',
      );
    }
    final uri = Uri.tryParse(settings.url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw const InfluxDbException('InfluxDB URL must be a valid HTTP(S) URL');
    }
    if (settings.retentionSeconds < 0) {
      throw const InfluxDbException('Retention cannot be negative');
    }
  }

  void _requireSuccess(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var detail = response.body.trim();
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      detail = json['message']?.toString() ?? detail;
    } catch (_) {
      // Keep the raw response body.
    }
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    throw InfluxDbException(
      'Failed to $action (${response.statusCode})'
      '${detail.isEmpty ? '' : ': $detail'}',
    );
  }

  static String _escapeTag(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll(',', r'\,')
      .replaceAll(' ', r'\ ')
      .replaceAll('=', r'\=');

  static String _utcSeconds(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
    ).toIso8601String();
  }
}
