import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/helpers/telemetry_log.dart';

/// Builds a 16-byte NUL-padded ASCII channel name.
Uint8List _name(String s) {
  final out = Uint8List(telemetryLogChannelNameLen);
  for (var i = 0; i < s.length && i < out.length; i++) {
    out[i] = s.codeUnitAt(i);
  }
  return out;
}

void _u16(BytesBuilder b, int v) {
  final d = Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
  b.add(d);
}

void _u32(BytesBuilder b, int v) {
  final d = Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
  b.add(d);
}

void _i16(BytesBuilder b, int v) {
  final d = Uint8List(2)..buffer.asByteData().setInt16(0, v, Endian.little);
  b.add(d);
}

/// A 2-channel export log:
///   ch0 (self): voltage + noise
///   ch1 (env):  temperature + humidity
/// stride 2, interval 60s, 3 sample ticks (indices 0,1,2).
Uint8List _buildSampleLog() {
  final b = BytesBuilder();
  // Header
  b.add(Uint8List.fromList(telemetryLogMagic)); // "MCTL"
  b.addByte(telemetryLogVersion); // 3
  b.addByte(2); // channel_count
  _u16(b, 2); // timestamp_stride
  _u32(b, 60); // interval_s
  // Channel table
  b.addByte(0); // lpp_channel
  _u16(b, telemLogVoltage | telemLogNoise); // 0x03
  b.add(_name('self'));
  b.addByte(1); // lpp_channel
  _u16(b, telemLogTemperature | telemLogHumidity); // 0x14
  b.add(_name('env'));

  // Body — tick 0 (anchor)
  _u32(b, 1700000000);
  b.addByte(160); // voltage -> (160+250)/100 = 4.10 V
  b.addByte(50); //  noise   -> 50 - 150 = -100 dBm
  _i16(b, 234); //  temp    -> 23.4 C
  b.addByte(110); // humidity -> 55.0 %

  // tick 1 (no anchor) — sentinels for voltage/temp/humidity
  b.addByte(0x00); // voltage sentinel -> null
  b.addByte(60); //  noise -> -90 dBm
  _i16(b, 0x7FFF); // temp sentinel -> null
  b.addByte(0xFF); // humidity sentinel -> null

  // tick 2 (anchor, with a time jump)
  _u32(b, 1700000200);
  b.addByte(170); // 4.20 V
  b.addByte(40); //  -110 dBm
  _i16(b, 200); //  20.0 C
  b.addByte(100); // 50.0 %

  return b.toBytes();
}

void main() {
  group('telemetry log header', () {
    test('header size and flag bytes', () {
      expect(telemetryHeaderSize(2), 12 + 19 * 2);
      expect(telemetryFlagBytes(telemLogVoltage | telemLogNoise), 2);
      expect(telemetryFlagBytes(telemLogTemperature | telemLogHumidity), 3);
      expect(telemetryFlagBytes(telemLogAllBitsForTest()), 12);
    });

    test('parses header and channels', () {
      final log = TelemetryLog(_buildSampleLog());
      expect(log.header.version, telemetryLogVersion);
      expect(log.header.channelCount, 2);
      expect(log.header.timestampStride, 2);
      expect(log.header.intervalSeconds, 60);
      expect(log.channels[0].lppChannel, 0);
      expect(log.channels[0].name, 'self');
      expect(log.channels[1].name, 'env');
      expect(log.recordSize, 5);
    });

    test('first anchor timestamp', () {
      final data = _buildSampleLog();
      expect(telemetryFirstAnchorTs(data, telemetryHeaderSize(2)), 1700000000);
    });
  });

  group('telemetry log samples', () {
    test('decodes values, sentinels and timestamps', () {
      final log = TelemetryLog(_buildSampleLog());
      final ticks = log.iterSamples().toList();
      expect(ticks.length, 3);

      // tick 0
      final t0 = ticks[0];
      expect(t0[0].isAnchor, isTrue);
      expect(t0[0].timestamp, 1700000000);
      expect(t0[0].lppChannel, 0);
      expect(t0[0].voltageV, closeTo(4.10, 1e-9));
      expect(t0[0].noiseDbm, closeTo(-100, 1e-9));
      expect(t0[1].temperatureC, closeTo(23.4, 1e-9));
      expect(t0[1].humidityPct, closeTo(55.0, 1e-9));

      // tick 1 — derived timestamp + sentinels -> null
      final t1 = ticks[1];
      expect(t1[0].isAnchor, isFalse);
      expect(t1[0].timestamp, 1700000060);
      expect(t1[0].voltageV, isNull);
      expect(t1[0].noiseDbm, closeTo(-90, 1e-9));
      expect(t1[1].temperatureC, isNull);
      expect(t1[1].humidityPct, isNull);

      // tick 2 — second anchor's own timestamp
      final t2 = ticks[2];
      expect(t2[0].isAnchor, isTrue);
      expect(t2[0].timestamp, 1700000200);
      expect(t2[0].voltageV, closeTo(4.20, 1e-9));
    });
  });

  group('record-aligned persistence', () {
    // Body layout for the sample log (stride 2, recordSize 5):
    //   sample0: 4 (anchor) + 5 = 9   -> cumulative 9
    //   sample1: 5 (no anchor)        -> cumulative 14
    //   sample2: 4 (anchor) + 5 = 9   -> cumulative 23
    // Truncating a partial pull to telemetryAlignedByteCount() must never cut a
    // record in half — it lands only on whole-sample boundaries.
    test('truncates body to whole telemetry records', () {
      int aligned(int received) => telemetryAlignedByteCount(received, 0, 2, 5);
      expect(aligned(0), 0);
      expect(aligned(5), 0); // first sample needs its 4-byte anchor too
      expect(aligned(8), 0); // one byte short of sample 0
      expect(aligned(9), 9); // sample 0 complete
      expect(aligned(13), 9); // sample 1 half-received -> drop it
      expect(aligned(14), 14); // samples 0 and 1
      expect(aligned(18), 14); // sample 2 half-received -> drop it
      expect(aligned(23), 23); // all three
    });
  });

  group('telemetry log chunk response', () {
    test('parses a chunk body with active flag', () {
      // [status][version][chunkLen][total LE32][offset LE32][remaining LE32][data]
      final b = BytesBuilder();
      b.addByte(respTelemLogOk | telemLogActiveFlag);
      b.addByte(telemLogRespVersion);
      b.addByte(3);
      _u32(b, 500); // total
      _u32(b, 12); // offset
      _u32(b, 485); // remaining
      b.add(Uint8List.fromList([0xAA, 0xBB, 0xCC]));

      final chunk = parseTelemetryLogChunk(b.toBytes())!;
      expect(chunk.isOk, isTrue);
      expect(chunk.loggingActive, isTrue);
      expect(chunk.totalSize, 500);
      expect(chunk.offset, 12);
      expect(chunk.remaining, 485);
      expect(chunk.data, [0xAA, 0xBB, 0xCC]);
    });

    test('returns null for a too-short body', () {
      expect(parseTelemetryLogChunk(Uint8List(10)), isNull);
    });

    test('unauthorized status surfaces a label', () {
      expect(telemetryLogStatusLabel(respTelemLogUnauth), contains('admin'));
    });

    test('restart statuses surface labels', () {
      expect(telemetryLogStatusLabel(respTelemLogNotActive), 'not active');
      expect(
        telemetryLogStatusLabel(respTelemLogRestartFail),
        'restart failed',
      );
    });
  });
}

// All eight type bits set; sum of widths = 1+1+2+2+1+2+2+1 = 12... but noise and
// voltage share channel-0-only semantics. For width math all bits count.
int telemLogAllBitsForTest() =>
    telemLogVoltage |
    telemLogNoise |
    telemLogTemperature |
    telemLogPressure |
    telemLogHumidity |
    telemLogCurrent |
    telemLogLuminosity |
    telemLogRain;
