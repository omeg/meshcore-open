import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/telemetry_log.dart';
import '../models/app_settings.dart';
import '../models/contact.dart';
import '../models/path_selection.dart';
import '../storage/telemetry_log_store.dart';
import '../utils/app_logger.dart';
import '../utils/platform_info.dart';
import 'influxdb_telemetry_service.dart';
import 'notification_service.dart';
import 'telemetry_saf_export.dart';

enum TelemetryLogFetchStatus { idle, fetching, done, error }

enum TelemetryInfluxImportStatus { notAttempted, imported, upToDate, failed }

/// Pulls a repeater's telemetry log over the mesh via `CMD_SEND_BINARY_REQ`
/// (`REQ_TYPE_GET_TELEMETRY_LOG`) and assembles the chunked response.
///
/// A port of the reference `telem_fetch.py` fetch loop, adapted to this app's
/// frame I/O: each chunk is one `respCodeSent` -> `pushCodeBinaryResponse`
/// round trip, matched by the 4-byte tag the companion returns. Resume state is
/// kept per repeater in [TelemetryLogStore] so repeated pulls only fetch the
/// tail the device has added.
///
/// Logging access is admin-only on the firmware; the caller is expected to have
/// logged in already (the repeater persists the client pubkey in its ACL, so no
/// password is needed per fetch).
class TelemetryLogFetchService extends ChangeNotifier {
  final MeshCoreConnector _connector;
  final TelemetryLogStore _store;
  final TelemetrySafExport? _safExport;
  final bool Function() _supportsMobileExportFolder;
  final InfluxDbSettings Function()? _influxSettings;
  final InfluxDbTelemetryService Function(TelemetryLogStore store)
  _influxServiceFactory;
  final Random _random = Random();

  TelemetryLogFetchService(
    this._connector, {
    TelemetryLogStore? store,
    TelemetrySafExport? safExport,
    bool Function()? supportsMobileExportFolder,
    InfluxDbSettings Function()? influxSettings,
    InfluxDbTelemetryService Function(TelemetryLogStore store)?
    influxServiceFactory,
  }) : _store = store ?? TelemetryLogStore(),
       _safExport = safExport ?? TelemetrySafExport(),
       _supportsMobileExportFolder =
           supportsMobileExportFolder ?? (() => PlatformInfo.isAndroid),
       _influxSettings = influxSettings,
       _influxServiceFactory =
           influxServiceFactory ??
           ((store) => InfluxDbTelemetryService(store: store));

  // Cross-device resume reads/writes the synced export folder, which only
  // exists on Android (SAF). Null elsewhere.
  TelemetrySafExport? get _sharedStore =>
      _supportsMobileExportFolder() ? _safExport : null;

  static const int _chunkAttempts = 10;
  static const Duration _retryDelay = Duration(seconds: 3);
  // Flat per-request timeout. The connector's dynamic estimate can balloon for
  // flood/large-frame paths and leave the fetch hanging; ~20s is plenty for a
  // single chunk round trip and bounds each retry.
  static const Duration _requestTimeout = Duration(seconds: 20);

  TelemetryLogFetchStatus _status = TelemetryLogFetchStatus.idle;
  int _bytesFetched = 0;
  int _totalSize = 0;
  bool _loggingActive = false;
  bool _resumed = false;
  bool _noResponse = false;
  String? _errorMessage;
  int? _lastStatusCode;
  TelemetryLog? _log;
  String? _savedFilePath;
  Contact? _target;
  TelemetryInfluxImportStatus _influxImportStatus =
      TelemetryInfluxImportStatus.notAttempted;
  int _influxImportTicks = 0;
  int _influxImportPoints = 0;
  String? _influxImportError;
  int _influxImportGeneration = 0;

  /// The repeater the current/last fetch targets. The screen uses this to tell
  /// whether the global service's state belongs to the repeater it's showing.
  Contact? get target => _target;
  String? get targetKey => _target?.publicKeyHex;

  TelemetryLogFetchStatus get status => _status;
  int get bytesFetched => _bytesFetched;
  int get totalSize => _totalSize;
  bool get loggingActive => _loggingActive;
  bool get resumed => _resumed;
  String? get errorMessage => _errorMessage;
  int? get lastStatusCode => _lastStatusCode;

  /// The repeater never answered the initial request: it may be offline/out of
  /// range, or its firmware may not support telemetry logging at all.
  bool get noResponse => _noResponse;
  TelemetryLog? get log => _log;

  /// Full path of the `.telemetry` file written by the last successful fetch.
  String? get savedFilePath => _savedFilePath;
  TelemetryInfluxImportStatus get influxImportStatus => _influxImportStatus;
  int get influxImportTicks => _influxImportTicks;
  int get influxImportPoints => _influxImportPoints;
  String? get influxImportError => _influxImportError;
  int get influxImportGeneration => _influxImportGeneration;
  double get progress =>
      _totalSize == 0 ? 0 : (_bytesFetched / _totalSize).clamp(0.0, 1.0);

  bool _cancelled = false;
  Completer<void>? _cancelSignal;
  bool _disposed = false;

  void cancel() {
    _cancelled = true;
    final signal = _cancelSignal;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelled = true;
    super.dispose();
  }

  // The fetch loop keeps running after the screen is torn down (so the partial
  // is flushed), but notifying a disposed ChangeNotifier throws — guard it.
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Fetch (or resume) [repeater]'s telemetry log. Set [forceRestart] to ignore
  /// stored resume state and pull from byte 0. [chunkSize] caps the bytes
  /// requested per round trip (clamped to 1..[telemLogMaxChunkLen]); lower it on
  /// flaky links.
  Future<void> fetch(
    Contact repeater, {
    bool forceRestart = false,
    int? chunkSize,
  }) async {
    if (_status == TelemetryLogFetchStatus.fetching) return;
    _cancelled = false;
    _cancelSignal = Completer<void>();
    _target = repeater;
    _status = TelemetryLogFetchStatus.fetching;
    _errorMessage = null;
    _lastStatusCode = null;
    _resumed = false;
    _noResponse = false;
    _savedFilePath = null;
    _influxImportStatus = TelemetryInfluxImportStatus.notAttempted;
    _influxImportTicks = 0;
    _influxImportPoints = 0;
    _influxImportError = null;
    _log = null;
    _bytesFetched = 0;
    _totalSize = 0;
    _loggingActive = false;
    _safeNotify();

    try {
      final selection = await _cancelable(
        _connector.preparePathForContactSend(repeater),
      );
      final buffer = await _runFetch(
        repeater,
        selection,
        forceRestart,
        chunkSize,
      );
      if (_cancelled) {
        _status = TelemetryLogFetchStatus.idle;
        _safeNotify();
        return; // user cancelled — no notification
      }
      if (buffer != null && buffer.length > _headerOnlyGuard) {
        try {
          _log = TelemetryLog(buffer);
        } on TelemetryLogProtocolError catch (e) {
          // Keep partial bytes persisted but surface the decode problem.
          appLogger.warn('Telemetry log decode failed: $e', tag: 'TelemLog');
        }
      }
      await _autoExportIfConfigured(repeater);
      await _autoImportToInfluxIfConfigured(repeater);
      _status = TelemetryLogFetchStatus.done;
      _notifyResult(success: true, repeater: repeater);
    } on _TelemetryLogFetchCancelled {
      _status = TelemetryLogFetchStatus.idle;
    } catch (e) {
      _errorMessage = e.toString();
      _status = TelemetryLogFetchStatus.error;
      appLogger.warn('Telemetry log fetch failed: $e', tag: 'TelemLog');
      _notifyResult(success: false, repeater: repeater);
    } finally {
      _cancelSignal = null;
    }
    _safeNotify();
  }

  Future<void> _autoExportIfConfigured(Contact repeater) async {
    final saf = _sharedStore;
    if (saf == null) return;
    final telemetryPath =
        _savedFilePath ?? await _store.currentFilePath(repeater.publicKeyHex);
    if (telemetryPath == null) return;
    final treeUri = await saf.configuredDirectoryUri();
    if (treeUri == null) return;
    final entries = await _store.exportPayload(
      telemetryPath,
      repeater.publicKeyHex,
    );
    if (entries.isEmpty) return;
    try {
      await saf.writeEntries(treeUri, entries);
    } catch (e) {
      appLogger.warn('Telemetry auto-export failed: $e', tag: 'TelemLog');
    }
  }

  Future<void> _autoImportToInfluxIfConfigured(Contact repeater) async {
    final settings = _influxSettings?.call();
    if (settings == null || !settings.isConfigured) return;
    final telemetryPath =
        _savedFilePath ?? await _store.currentFilePath(repeater.publicKeyHex);
    if (telemetryPath == null) return;

    final importer = _influxServiceFactory(_store);
    try {
      final result = await importer.importFile(
        path: telemetryPath,
        node: repeater.publicKeyHex,
        settings: settings,
      );
      _influxImportStatus = result.alreadyUpToDate
          ? TelemetryInfluxImportStatus.upToDate
          : TelemetryInfluxImportStatus.imported;
      _influxImportTicks = result.ticks;
      _influxImportPoints = result.points;
      _influxImportGeneration++;
      appLogger.info(
        result.alreadyUpToDate
            ? 'InfluxDB telemetry import already up to date'
            : 'Auto-imported ${result.points} telemetry point(s) '
                  'from ${result.ticks} tick(s) to InfluxDB',
        tag: 'TelemLog',
      );
    } catch (e) {
      _influxImportStatus = TelemetryInfluxImportStatus.failed;
      _influxImportError = e.toString();
      _influxImportGeneration++;
      appLogger.warn(
        'Telemetry InfluxDB auto-import failed: $e',
        tag: 'TelemLog',
      );
    } finally {
      importer.close();
    }
  }

  Future<T> _cancelable<T>(Future<T> operation) {
    if (_cancelled) {
      throw const _TelemetryLogFetchCancelled();
    }
    final signal = _cancelSignal;
    if (signal == null) return operation;
    return Future.any<T>([
      operation,
      signal.future.then<T>((_) => throw const _TelemetryLogFetchCancelled()),
    ]);
  }

  /// Post a system notification with the outcome, but only when no screen is
  /// observing the service — i.e. the user navigated away while it ran. (The
  /// telemetry-log screen is the only listener, so `hasListeners` is a reliable
  /// "is the screen open" proxy.)
  void _notifyResult({required bool success, required Contact repeater}) {
    if (hasListeners) return;
    unawaited(
      NotificationService().showTelemetryLogNotification(
        repeaterName: repeater.name,
        success: success,
        hasData: _totalSize > 0,
      ),
    );
    if (_influxImportStatus != TelemetryInfluxImportStatus.notAttempted) {
      unawaited(
        NotificationService().showTelemetryInfluxImportNotification(
          repeaterName: repeater.name,
          success: _influxImportStatus != TelemetryInfluxImportStatus.failed,
          alreadyUpToDate:
              _influxImportStatus == TelemetryInfluxImportStatus.upToDate,
          ticks: _influxImportTicks,
          points: _influxImportPoints,
          error: _influxImportError,
        ),
      );
    }
  }

  // A log with a header but zero samples isn't worth decoding.
  static const int _headerOnlyGuard = 16;

  Future<Uint8List?> _runFetch(
    Contact repeater,
    PathSelection selection,
    bool forceRestart,
    int? requestedChunkSize,
  ) async {
    final chunkSize = (requestedChunkSize ?? telemLogMaxChunkLen).clamp(
      1,
      telemLogMaxChunkLen,
    );

    // 1. Pull enough leading bytes to read the export header + first anchor.
    final accumulated = BytesBuilder();
    final TelemetryLogChunk first;
    try {
      first = await _requestChunkWithRetries(repeater, selection, 0, chunkSize);
    } on TimeoutException {
      // No reply at all: repeater offline/out of range, or a firmware without
      // telemetry-log support (it silently ignores the request type).
      _noResponse = true;
      rethrow;
    }

    // "No log present" is a normal state, not an error — surface it as such.
    if (first.status == respTelemLogNoFile || first.totalSize == 0) {
      _totalSize = 0;
      _loggingActive = first.loggingActive;
      _safeNotify();
      return null;
    }
    _requireOk(first);
    _totalSize = first.totalSize;
    _loggingActive = first.loggingActive;
    _safeNotify();
    accumulated.add(first.data);

    if (accumulated.length < 6) {
      throw TelemetryLogProtocolError(
        'first chunk too small to read channel count',
      );
    }
    final channelCount = accumulated.toBytes()[5];
    final needed =
        telemetryHeaderSize(channelCount) + 4; // header + first anchor
    while (accumulated.length < needed &&
        accumulated.length < first.totalSize &&
        !_cancelled) {
      final extra = await _requestChunkWithRetries(
        repeater,
        selection,
        accumulated.length,
        chunkSize,
      );
      _requireOk(extra);
      if (extra.offset != accumulated.length) {
        throw TelemetryLogProtocolError(
          'unexpected chunk offset while reading header: '
          'got ${extra.offset}, expected ${accumulated.length}',
        );
      }
      if (extra.chunkLen == 0) {
        throw TelemetryLogProtocolError('empty chunk while reading log header');
      }
      accumulated.add(extra.data);
      _loggingActive = extra.loggingActive;
    }
    if (_cancelled) return accumulated.toBytes();

    final headerBytes = accumulated.toBytes();
    final headerReader = BufferReader(headerBytes);
    final parsed = parseTelemetryLogHeader(headerReader);
    final headerLen = headerBytes.length - headerReader.remaining;
    final headerHex = _hex(headerBytes.sublist(0, headerLen));
    if (headerBytes.length < headerLen + 4) {
      return headerBytes; // header present but no samples logged yet
    }
    final logStartTs = telemetryFirstAnchorTs(headerBytes, headerLen);
    final recordSize = parsed.channels.fold<int>(
      0,
      (sum, c) => sum + telemetryFlagBytes(c.flags),
    );

    // 2. Decide resume vs fresh. Consider both the local private store and the
    //    synced folder (shared across devices) and resume from whichever has the
    //    most progress for this exact session — so the last device to pull wins.
    final buffer = BytesBuilder();
    int fetchOffset;
    final candidate = forceRestart
        ? null
        : await _bestResumeCandidate(
            repeater.publicKeyHex,
            headerHex,
            logStartTs,
            first.totalSize,
          );

    final String sessionFilename;
    if (candidate != null) {
      _resumed = true;
      sessionFilename = candidate.sessionFilename;
      buffer.add(candidate.bytes.sublist(0, candidate.offset));
      if (headerBytes.length > candidate.offset) {
        buffer.add(headerBytes.sublist(candidate.offset));
        fetchOffset = headerBytes.length;
      } else {
        fetchOffset = candidate.offset;
      }
    } else {
      sessionFilename = _store.sessionFilename(
        repeater.publicKeyHex,
        logStartTs,
      );
      buffer.add(headerBytes);
      fetchOffset = headerBytes.length;
    }
    _bytesFetched = buffer.length;
    _safeNotify();

    // Persist only the prefix that ends on a whole telemetry record, so a
    // partial pull (back-out, or a chunk timing out on a spotty link) always
    // leaves a cleanly importable file and a resumable offset — never a
    // half-written trailing record. Throttled to limit flash churn, but always
    // flushed when the loop exits (break, cancel, or exception) via `finally`.
    var lastPersistedLen = candidate?.offset ?? 0;
    var lastPersistAt = DateTime.fromMillisecondsSinceEpoch(0);

    int recordAlignedLength(int bufferLen) {
      if (recordSize <= 0 || bufferLen <= headerLen) return headerLen;
      final alignedBody = telemetryAlignedByteCount(
        bufferLen - headerLen,
        0,
        parsed.header.timestampStride,
        recordSize,
      );
      return headerLen + alignedBody;
    }

    TelemetryLogSession sessionFor(int offset) => TelemetryLogSession(
      repeaterPubkey: repeater.publicKeyHex.toLowerCase(),
      sessionFilename: sessionFilename,
      headerHex: headerHex,
      logStartTs: logStartTs,
      lastTotalSize: first.totalSize,
      lastPullOffset: offset,
      intervalSeconds: parsed.header.intervalSeconds,
      timestampStride: parsed.header.timestampStride,
      channelCount: parsed.header.channelCount,
      updatedAt: _isoSecondsUtc(DateTime.now()),
    );

    Future<void> persist({bool force = false}) async {
      final bytes = buffer.toBytes();
      final aligned = recordAlignedLength(bytes.length);
      // When a refresh finds no new whole sample, still rewrite the tiny state
      // file on the final flush so updated_at/last_total_size reflect the
      // latest probe. This makes a completed session a real refresh target
      // instead of a stale "done forever" marker.
      if (aligned <= lastPersistedLen && !force) return;
      if (aligned <= lastPersistedLen && force) {
        final existingPath = await _store.currentFilePath(
          repeater.publicKeyHex,
        );
        if (existingPath != null && lastPersistedLen > 0) {
          _savedFilePath = await _store.saveSession(
            repeater.publicKeyHex,
            sessionFor(lastPersistedLen),
            Uint8List.sublistView(bytes, 0, lastPersistedLen),
          );
        }
        return;
      }
      if (!force &&
          DateTime.now().difference(lastPersistAt) <
              const Duration(seconds: 2)) {
        return;
      }
      lastPersistAt = DateTime.now();
      lastPersistedLen = aligned;
      final prefix = aligned == bytes.length
          ? bytes
          : Uint8List.sublistView(bytes, 0, aligned);
      _savedFilePath = await _store.saveSession(
        repeater.publicKeyHex,
        sessionFor(aligned),
        prefix,
      );
    }

    // 3. Pull the remaining tail.
    try {
      while (fetchOffset < first.totalSize && !_cancelled) {
        final chunk = await _requestChunkWithRetries(
          repeater,
          selection,
          fetchOffset,
          chunkSize,
        );
        _requireOk(chunk);
        if (chunk.offset != fetchOffset) {
          throw TelemetryLogProtocolError(
            'unexpected chunk offset: got ${chunk.offset}, expected $fetchOffset',
          );
        }
        if (chunk.data.isNotEmpty) buffer.add(chunk.data);
        fetchOffset += chunk.chunkLen;
        _bytesFetched = buffer.length;
        _loggingActive = chunk.loggingActive;
        _safeNotify();
        await persist();
        if (chunk.remaining == 0) break;
        if (chunk.chunkLen == 0) {
          throw TelemetryLogProtocolError(
            'repeater reported remaining bytes but returned an empty chunk',
          );
        }
      }
    } finally {
      await persist(force: true);
      // Mirror the record-aligned prefix + resume state to the synced folder so
      // the next device resumes from this offset. Best-effort; never fails the
      // fetch. (Auto-syncs on every pull once an export folder is remembered.)
      final shared = _sharedStore;
      if (shared != null) {
        final bytes = buffer.toBytes();
        final aligned = recordAlignedLength(bytes.length);
        if (aligned > headerLen) {
          final prefix = aligned == bytes.length
              ? bytes
              : Uint8List.sublistView(bytes, 0, aligned);
          await shared.writeShared(
            repeater.publicKeyHex,
            sessionFor(aligned),
            prefix,
          );
        }
      }
      // Even when nothing new was fetched (e.g. an already-complete resume),
      // surface the existing file so it can be shared/exported.
      _savedFilePath ??= await _store.currentFilePath(repeater.publicKeyHex);
    }
    return buffer.toBytes();
  }

  /// Best resume point for this session across the local store and the synced
  /// folder: whichever has the most progress (highest aligned offset) and still
  /// matches the device's current header + first anchor.
  Future<_ResumeCandidate?> _bestResumeCandidate(
    String repeaterHex,
    String headerHex,
    int? logStartTs,
    int totalSize,
  ) async {
    _ResumeCandidate? best;
    void consider(TelemetryLogSession? session, Uint8List? bytes) {
      if (session == null || bytes == null) return;
      if (session.headerHex != headerHex || session.logStartTs != logStartTs) {
        return;
      }
      if (session.lastPullOffset <= 0) return;
      if (totalSize < session.lastTotalSize) return; // log shrank -> reset
      if (bytes.length < session.lastPullOffset) return;
      if (best == null || session.lastPullOffset > best!.offset) {
        best = _ResumeCandidate(
          session.sessionFilename,
          bytes,
          session.lastPullOffset,
        );
      }
    }

    final priv = await _store.loadSession(repeaterHex);
    consider(
      priv,
      priv == null ? null : await _store.loadBytes(priv.sessionFilename),
    );

    final shared = _sharedStore;
    if (shared != null) {
      final s = await shared.readSharedSession(repeaterHex);
      consider(
        s,
        s == null ? null : await shared.readSharedBytes(s.sessionFilename),
      );
    }
    return best;
  }

  void _requireOk(TelemetryLogChunk chunk) {
    if (!chunk.isOk) {
      _lastStatusCode = chunk.status;
      throw TelemetryLogProtocolError(
        'request failed: ${telemetryLogStatusLabel(chunk.status)}',
      );
    }
  }

  Future<TelemetryLogChunk> _requestChunkWithRetries(
    Contact repeater,
    PathSelection selection,
    int offset,
    int chunkSize,
  ) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _chunkAttempts; attempt++) {
      if (_cancelled) {
        throw const _TelemetryLogFetchCancelled();
      }
      try {
        return await _requestChunk(repeater, selection, offset, chunkSize);
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt < _chunkAttempts) {
          appLogger.info(
            'telemetry chunk @$offset attempt $attempt timed out; retrying',
            tag: 'TelemLog',
          );
          await _cancelable(Future<void>.delayed(_retryDelay));
        }
      }
    }
    throw TimeoutException(
      'no response for telemetry chunk @$offset: $lastError',
    );
  }

  Future<TelemetryLogChunk> _requestChunk(
    Contact repeater,
    PathSelection selection,
    int offset,
    int chunkSize,
  ) async {
    final nonce = _random.nextInt(0xFFFFFFFF);
    final payload = buildTelemetryLogReqPayload(
      chunkLen: chunkSize,
      offset: offset,
      nonce: nonce,
    );
    final frame = buildSendBinaryReq(repeater.publicKey, payload: payload);

    final completer = Completer<TelemetryLogChunk>();
    int? tag;
    late StreamSubscription<Uint8List> sub;
    sub = _connector.receivedFrames.listen((incoming) {
      if (incoming.isEmpty) return;
      try {
        final reader = BufferReader(incoming);
        final code = reader.readByte();
        if (code == respCodeSent) {
          reader.skipBytes(1); // reserved
          tag = reader.readUInt32LE();
          return;
        }
        if (code == pushCodeBinaryResponse) {
          reader.skipBytes(1); // reserved
          final respTag = reader.readUInt32LE();
          if (tag == null || respTag != tag) return;
          final chunk = parseTelemetryLogChunk(reader.readRemainingBytes());
          if (chunk == null) return;
          if (!completer.isCompleted) completer.complete(chunk);
        }
      } catch (_) {
        // Ignore malformed frames; the timeout will retry if needed.
      }
    });

    try {
      await _cancelable(_connector.sendFrame(frame));
      return await _cancelable(completer.future.timeout(_requestTimeout));
    } finally {
      await sub.cancel();
    }
  }

  String _hex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  // Matches telem_fetch.py's "%Y-%m-%dT%H:%M:%SZ" — no fractional seconds.
  String _isoSecondsUtc(DateTime dt) {
    final u = dt.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T'
        '${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
  }
}

class _TelemetryLogFetchCancelled implements Exception {
  const _TelemetryLogFetchCancelled();
}

/// A resume seed: the assembled bytes for a session and the record-aligned
/// offset to continue fetching from.
class _ResumeCandidate {
  final String sessionFilename;
  final Uint8List bytes;
  final int offset;
  const _ResumeCandidate(this.sessionFilename, this.bytes, this.offset);
}
