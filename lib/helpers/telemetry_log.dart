import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';

/// Pure decoder for MeshCore telemetry logs.
///
/// Mirrors the firmware's export format (see firmware `docs/telemetry.md` and
/// the reference `telemetry/telemetry.py`). No transport or storage concerns —
/// it just turns the export-format byte stream into structured samples.
///
/// Export layout:
/// ```
/// magic[4] = "MCTL"
/// version[1]
/// channel_count[1]
/// timestamp_stride[2 LE]
/// interval_s[4 LE]
/// channels:
///   lpp_channel[1]
///   flags[2 LE]                         # subset of telemLog* type bits
///   name[telemetryLogChannelNameLen]    # NUL-padded ASCII
/// body (repeats):
///   if sample_index % timestamp_stride == 0: anchor_timestamp[4 LE]
///   for each channel, in type-bit order: per-type encoded value
/// ```
/// All multi-byte fields in the log are little-endian (note this differs from
/// CayenneLPP's big-endian on-demand payloads).

const List<int> telemetryLogMagic = [0x4D, 0x43, 0x54, 0x4C]; // "MCTL"
const int telemetryLogVersion = 3;
const int telemetryLogChannelNameLen = 16;
const int telemetryLogTimestampInvalid = 0xFFFFFFFF;

// Per-channel type bit masks (also the serialization order, low bit first).
const int telemLogVoltage = 0x01;
const int telemLogNoise = 0x02;
const int telemLogTemperature = 0x04;
const int telemLogPressure = 0x08;
const int telemLogHumidity = 0x10;
const int telemLogCurrent = 0x20;
const int telemLogLuminosity = 0x40;
const int telemLogRain = 0x80;

// Per-bit byte widths in the on-disk record, read in bit order (low bit first).
const Map<int, int> _typeByteSize = {
  telemLogVoltage: 1,
  telemLogNoise: 1,
  telemLogTemperature: 2,
  telemLogPressure: 2,
  telemLogHumidity: 1,
  telemLogCurrent: 2,
  telemLogLuminosity: 2,
  telemLogRain: 1,
};

const int _voltageBase = 250;
const int _noiseBase = -150;

// "No reading" sentinels the firmware emits when a sample is missing the type
// its channel mask declares (sensor read failed, etc.).
const int _sentinelVoltage = 0x00;
const int _sentinelNoise = 0x00;
const int _sentinelTemperature = 0x7FFF;
const int _sentinelPressure = 0xFFFF;
const int _sentinelHumidity = 0xFF;
const int _sentinelCurrent = 0x7FFF;
const int _sentinelLuminosity = 0x0000;
const int _sentinelRain = 0xFF;

class TelemetryLogProtocolError implements Exception {
  final String message;
  TelemetryLogProtocolError(this.message);
  @override
  String toString() => 'TelemetryLogProtocolError: $message';
}

class TelemetryLogHeader {
  final int version;
  final int channelCount;
  final int timestampStride;
  final int intervalSeconds;
  const TelemetryLogHeader({
    required this.version,
    required this.channelCount,
    required this.timestampStride,
    required this.intervalSeconds,
  });
}

class TelemetryChannel {
  final int lppChannel;
  final int flags; // subset of telemLog* bits
  final String name;
  const TelemetryChannel({
    required this.lppChannel,
    required this.flags,
    this.name = '',
  });
}

/// One channel's reading at a single sample tick. Any field is null when the
/// channel doesn't carry that type or the firmware wrote a sentinel.
class TelemetrySample {
  final int sampleIndex;
  final bool isAnchor;
  final int timestamp; // epoch seconds (or relative if the RTC was unset)
  final int lppChannel;
  final double? voltageV;
  final double? noiseDbm;
  final double? temperatureC;
  final double? pressureHpa;
  final double? humidityPct;
  final double? currentA;
  final double? luminosityLux;
  final int? rain;

  const TelemetrySample({
    required this.sampleIndex,
    required this.isAnchor,
    required this.timestamp,
    required this.lppChannel,
    this.voltageV,
    this.noiseDbm,
    this.temperatureC,
    this.pressureHpa,
    this.humidityPct,
    this.currentA,
    this.luminosityLux,
    this.rain,
  });
}

/// Number of body bytes a record contributes for a given flag mask.
int telemetryFlagBytes(int flags) {
  var total = 0;
  _typeByteSize.forEach((bit, size) {
    if (flags & bit != 0) total += size;
  });
  return total;
}

/// Byte length of the export header for a log with [channelCount] channels:
/// 12 fixed bytes + per-channel (1 lpp + 2 flags + name).
int telemetryHeaderSize(int channelCount) =>
    12 + (3 + telemetryLogChannelNameLen) * channelCount;

double? _decodeVoltage(int b) =>
    b == _sentinelVoltage ? null : (b + _voltageBase) / 100.0;
double? _decodeNoise(int b) =>
    b == _sentinelNoise ? null : (b + _noiseBase).toDouble();
double? _decodeTemperature(int rawI16) =>
    rawI16 == _sentinelTemperature ? null : rawI16 / 10.0;
double? _decodePressure(int rawU16) =>
    rawU16 == _sentinelPressure ? null : rawU16 / 10.0;
double? _decodeHumidity(int b) => b == _sentinelHumidity ? null : b / 2.0;
double? _decodeCurrent(int rawI16) =>
    rawI16 == _sentinelCurrent ? null : rawI16 / 1000.0;

// Normalized 16-bit pseudo-float: bits 15..11 = biased exponent,
// bits 10..0 = mantissa fraction with implicit leading 1.
// value (lux) = (1 + m/2048) * 2^(e - 10). Mirrors encodeLuminosityFP().
double? _decodeLuminosityFp(int rawU16) {
  if (rawU16 == _sentinelLuminosity) return null;
  final e = (rawU16 >> 11) & 0x1F;
  final m = rawU16 & 0x7FF;
  return (1.0 + m / 2048.0) * _pow2(e - 10);
}

double _pow2(int exp) {
  // Avoid dart:math import for a single use; exponents here are small.
  if (exp >= 0) return (1 << exp).toDouble();
  return 1.0 / (1 << -exp);
}

/// Parse the fixed header + channel table from [reader], leaving it positioned
/// at the start of the body.
({TelemetryLogHeader header, List<TelemetryChannel> channels})
parseTelemetryLogHeader(BufferReader reader) {
  if (reader.remaining < 12) {
    throw TelemetryLogProtocolError('data too short for telemetry log header');
  }
  final magic = reader.readBytes(4);
  for (var i = 0; i < 4; i++) {
    if (magic[i] != telemetryLogMagic[i]) {
      throw TelemetryLogProtocolError('bad magic');
    }
  }
  final version = reader.readByte();
  if (version != telemetryLogVersion) {
    throw TelemetryLogProtocolError('unsupported log version: $version');
  }
  final channelCount = reader.readByte();
  final timestampStride = reader.readUInt16LE();
  if (timestampStride == 0) {
    throw TelemetryLogProtocolError('timestamp stride must be non-zero');
  }
  if (channelCount == 0) {
    throw TelemetryLogProtocolError('channel count must be non-zero');
  }
  final intervalSeconds = reader.readUInt32LE();

  final entrySize = 3 + telemetryLogChannelNameLen;
  if (reader.remaining < entrySize * channelCount) {
    throw TelemetryLogProtocolError('truncated channel table');
  }
  final channels = <TelemetryChannel>[];
  for (var i = 0; i < channelCount; i++) {
    final lpp = reader.readByte();
    final flags = reader.readUInt16LE();
    final rawName = reader.readBytes(telemetryLogChannelNameLen);
    channels.add(
      TelemetryChannel(lppChannel: lpp, flags: flags, name: _cName(rawName)),
    );
  }
  return (
    header: TelemetryLogHeader(
      version: version,
      channelCount: channelCount,
      timestampStride: timestampStride,
      intervalSeconds: intervalSeconds,
    ),
    channels: channels,
  );
}

String _cName(Uint8List raw) {
  var end = raw.indexOf(0);
  if (end < 0) end = raw.length;
  return String.fromCharCodes(raw.sublist(0, end)).trim();
}

/// Timestamp of the first anchor (sample 0), or null if the RTC was unset when
/// the log was started. Sample 0 is always an anchor, so the 4 bytes right after
/// the header are its u32 LE epoch timestamp.
int? telemetryFirstAnchorTs(Uint8List data, int headerSize) {
  if (data.length < headerSize + 4) {
    throw TelemetryLogProtocolError('data too short for first anchor timestamp');
  }
  final ts = ByteData.sublistView(
    data,
    headerSize,
    headerSize + 4,
  ).getUint32(0, Endian.little);
  return ts == telemetryLogTimestampInvalid ? null : ts;
}

/// Number of [receivedBytes] covering whole samples, so truncating to this
/// length never leaves a half-record for the iterator. Anchor-vs-record-only
/// depends on the sample index, so we walk.
int telemetryAlignedByteCount(
  int receivedBytes,
  int startSampleIndex,
  int timestampStride,
  int recordSize,
) {
  var pos = 0;
  var n = 0;
  while (pos < receivedBytes) {
    final cur = startSampleIndex + n;
    final need = (cur % timestampStride == 0 ? 4 : 0) + recordSize;
    if (pos + need > receivedBytes) break;
    pos += need;
    n += 1;
  }
  return pos;
}

/// High-level view of a complete telemetry log in export format.
class TelemetryLog {
  final Uint8List data;
  final TelemetryLogHeader header;
  final List<TelemetryChannel> channels;
  final int bodyOffset;
  final int recordSize;

  TelemetryLog._(
    this.data,
    this.header,
    this.channels,
    this.bodyOffset,
    this.recordSize,
  );

  factory TelemetryLog(Uint8List data) {
    final reader = BufferReader(data);
    final parsed = parseTelemetryLogHeader(reader);
    final bodyOffset = data.length - reader.remaining;
    final recordSize = parsed.channels.fold<int>(
      0,
      (sum, c) => sum + telemetryFlagBytes(c.flags),
    );
    if (recordSize == 0) {
      throw TelemetryLogProtocolError(
        'record size is zero (no enabled flags on any channel)',
      );
    }
    return TelemetryLog._(
      data,
      parsed.header,
      parsed.channels,
      bodyOffset,
      recordSize,
    );
  }

  /// Iterate every sample tick. Each yielded list holds one [TelemetrySample]
  /// per channel for that tick.
  Iterable<List<TelemetrySample>> iterSamples() sync* {
    final aligned = telemetryAlignedByteCount(
      data.length - bodyOffset,
      0,
      header.timestampStride,
      recordSize,
    );
    final body = BufferReader(
      Uint8List.sublistView(data, bodyOffset, bodyOffset + aligned),
    );

    var sampleIndex = 0;
    var anchorTs = 0;
    var anchorIdx = 0;
    var hasAnchor = false;

    while (body.remaining > 0) {
      final isAnchor = sampleIndex % header.timestampStride == 0;
      if (isAnchor) {
        if (body.remaining < 4) return;
        final rawTs = body.readUInt32LE();
        if (rawTs == telemetryLogTimestampInvalid) {
          if (!hasAnchor) {
            anchorTs = 0;
            anchorIdx = sampleIndex;
            hasAnchor = true;
          }
        } else {
          anchorTs = rawTs;
          anchorIdx = sampleIndex;
          hasAnchor = true;
        }
      }

      if (body.remaining < recordSize) return;
      final record = BufferReader(body.readBytes(recordSize));
      final timestamp =
          anchorTs + (sampleIndex - anchorIdx) * header.intervalSeconds;

      final perChannel = <TelemetrySample>[];
      for (final ch in channels) {
        double? voltage, noise, temperature, pressure, humidity, current, lux;
        int? rain;
        if (ch.flags & telemLogVoltage != 0) {
          voltage = _decodeVoltage(record.readByte());
        }
        if (ch.flags & telemLogNoise != 0) {
          noise = _decodeNoise(record.readByte());
        }
        if (ch.flags & telemLogTemperature != 0) {
          temperature = _decodeTemperature(record.readInt16LE());
        }
        if (ch.flags & telemLogPressure != 0) {
          pressure = _decodePressure(record.readUInt16LE());
        }
        if (ch.flags & telemLogHumidity != 0) {
          humidity = _decodeHumidity(record.readByte());
        }
        if (ch.flags & telemLogCurrent != 0) {
          current = _decodeCurrent(record.readInt16LE());
        }
        if (ch.flags & telemLogLuminosity != 0) {
          lux = _decodeLuminosityFp(record.readUInt16LE());
        }
        if (ch.flags & telemLogRain != 0) {
          final b = record.readByte();
          rain = b == _sentinelRain ? null : (b != 0 ? 1 : 0);
        }
        perChannel.add(
          TelemetrySample(
            sampleIndex: sampleIndex,
            isAnchor: isAnchor,
            timestamp: timestamp,
            lppChannel: ch.lppChannel,
            voltageV: voltage,
            noiseDbm: noise,
            temperatureC: temperature,
            pressureHpa: pressure,
            humidityPct: humidity,
            currentA: current,
            luminosityLux: lux,
            rain: rain,
          ),
        );
      }
      yield perChannel;
      sampleIndex += 1;
    }
  }
}

/// One decoded `REQ_TYPE_GET_TELEMETRY_LOG` chunk response.
///
/// Built from the body the app sees *after* the companion strips
/// `[0x8C][reserved][tag x4]` — the firmware lifts the 4-byte sender timestamp
/// out into the tag, so what remains is a 15-byte header plus chunk data:
/// `[status][version][chunkLen][total LE32][offset LE32][remaining LE32][chunk…]`.
class TelemetryLogChunk {
  final int status; // low 7 bits
  final bool loggingActive;
  final int version;
  final int chunkLen;
  final int totalSize;
  final int offset;
  final int remaining;
  final Uint8List data;

  const TelemetryLogChunk({
    required this.status,
    required this.loggingActive,
    required this.version,
    required this.chunkLen,
    required this.totalSize,
    required this.offset,
    required this.remaining,
    required this.data,
  });

  bool get isOk => status == respTelemLogOk;
}

/// Parse a telemetry-log chunk from the binary-response [body] (tag already
/// stripped). Returns null if the body is too short to hold the 15-byte header.
TelemetryLogChunk? parseTelemetryLogChunk(Uint8List body) {
  if (body.length < 15) return null;
  final reader = BufferReader(body);
  final statusByte = reader.readByte();
  final version = reader.readByte();
  final chunkLen = reader.readByte();
  final totalSize = reader.readUInt32LE();
  final offset = reader.readUInt32LE();
  final remaining = reader.readUInt32LE();
  final data = (chunkLen > 0 && reader.remaining >= chunkLen)
      ? reader.readBytes(chunkLen)
      : Uint8List(0);
  return TelemetryLogChunk(
    status: statusByte & 0x7F,
    loggingActive: statusByte & telemLogActiveFlag != 0,
    version: version,
    chunkLen: chunkLen,
    totalSize: totalSize,
    offset: offset,
    remaining: remaining,
    data: data,
  );
}

String telemetryLogStatusLabel(int status) {
  switch (status) {
    case respTelemLogOk:
      return 'ok';
    case respTelemLogNoFile:
      return 'no log present';
    case respTelemLogBadReq:
      return 'bad request';
    case respTelemLogReadFail:
      return 'storage read failed';
    case respTelemLogUnauth:
      return 'unauthorized (admin login required)';
    default:
      return 'unknown ($status)';
  }
}
