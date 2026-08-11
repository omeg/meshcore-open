import 'dart:typed_data';

import '../connector/meshcore_protocol.dart';
import '../utils/app_logger.dart';

/// Parsed `RESP_CODE_STATS` + `STATS_TYPE_CORE` (11 bytes total).
class CompanionCoreStats {
  final int batteryMillivolts;
  final int uptimeSecs;
  final int errorFlags;
  final int queueLength;
  final DateTime receivedAt;

  const CompanionCoreStats({
    required this.batteryMillivolts,
    required this.uptimeSecs,
    required this.errorFlags,
    required this.queueLength,
    required this.receivedAt,
  });

  static CompanionCoreStats? tryParse(Uint8List frame) {
    if (frame.length < 11) return null;
    if (frame[0] != respCodeStats || frame[1] != statsTypeCore) return null;
    try {
      final reader = BufferReader(frame);
      reader.skipBytes(2);
      return CompanionCoreStats(
        batteryMillivolts: reader.readUInt16LE(),
        uptimeSecs: reader.readUInt32LE(),
        errorFlags: reader.readUInt16LE(),
        queueLength: reader.readUInt8(),
        receivedAt: DateTime.now(),
      );
    } catch (e) {
      appLogger.warn('CompanionCoreStats parse error: $e');
      return null;
    }
  }
}
