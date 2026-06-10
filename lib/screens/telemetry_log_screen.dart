import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/telemetry_log.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../services/telemetry_log_fetch_service.dart';
import '../services/telemetry_saf_export.dart';
import '../storage/prefs_manager.dart';
import '../storage/telemetry_log_store.dart';
import '../utils/app_logger.dart';
import '../utils/platform_info.dart';

class TelemetryLogScreen extends StatefulWidget {
  final Contact repeater;

  const TelemetryLogScreen({super.key, required this.repeater});

  @override
  State<TelemetryLogScreen> createState() => _TelemetryLogScreenState();
}

class _TelemetryLogScreenState extends State<TelemetryLogScreen> {
  // App-scoped: owned by the provider, not this screen, so a fetch keeps running
  // after the user navigates away.
  late final TelemetryLogFetchService _service;
  final TelemetryLogStore _store = TelemetryLogStore();
  final TelemetrySafExport _saf = TelemetrySafExport();

  /// Whether the global service's current/last fetch is for this repeater.
  bool get _isMyFetch =>
      _service.targetKey == widget.repeater.publicKeyHex;

  // Cached decode of the current log so we don't re-iterate on every rebuild.
  TelemetryLog? _cachedLog;
  List<List<TelemetrySample>> _ticks = const [];

  // All retained .telemetry files for this repeater (the export archive).
  List<TelemetryLogFile> _savedLogs = const [];

  // Desktop: absolute path of the directory the .telemetry files live in.
  String? _storageDir;

  // Bytes requested per round trip (1..telemLogMaxChunkLen). Persisted so a
  // value that works on a given link is remembered.
  static const String _chunkPrefsKey = 'telemetry_log_chunk_size';
  int _chunkSize = telemLogMaxChunkLen;
  final TextEditingController _chunkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _service = Provider.of<TelemetryLogFetchService>(context, listen: false)
      ..addListener(_onChange);
    // Pick up state from a fetch that's already running/finished for this
    // repeater (e.g. the user left and came back).
    if (_isMyFetch) _cacheLogFromService();
    _chunkSize = (PrefsManager.instance.getInt(_chunkPrefsKey) ??
            telemLogMaxChunkLen)
        .clamp(1, telemLogMaxChunkLen);
    _chunkController.text = _chunkSize.toString();
    // Don't auto-pull: a fetch is a deliberate, admin-only mesh operation, so
    // wait for the user to tap Fetch. Just surface any already-saved logs.
    _reloadSavedLogs();
    if (PlatformInfo.isDesktop) {
      _store.storageDirectoryPath().then((dir) {
        if (mounted) setState(() => _storageDir = dir);
      });
    }
  }

  @override
  void dispose() {
    // The service is app-scoped — only detach our listener; never cancel or
    // dispose it, so an in-flight fetch survives leaving the screen.
    _service.removeListener(_onChange);
    _chunkController.dispose();
    super.dispose();
  }

  void _cacheLogFromService() {
    final log = _isMyFetch ? _service.log : null;
    if (!identical(log, _cachedLog)) {
      _cachedLog = log;
      _ticks = log == null ? const [] : log.iterSamples().toList();
    }
  }

  void _onChange() {
    if (!mounted) return;
    _cacheLogFromService();
    setState(() {});
  }

  Future<void> _reloadSavedLogs() async {
    final logs = await _store.listLogFiles(widget.repeater.publicKeyHex);
    if (!mounted) return;
    setState(() => _savedLogs = logs);
  }

  Future<void> _startFetch({bool forceRestart = false}) async {
    _applyChunkSize();
    await _service.fetch(
      widget.repeater,
      forceRestart: forceRestart,
      chunkSize: _chunkSize,
    );
    await _reloadSavedLogs();
  }

  /// Normalize the chunk-size field to a clamped value, persist it, and reflect
  /// it back in the field.
  void _applyChunkSize() {
    final parsed = int.tryParse(_chunkController.text) ?? _chunkSize;
    _chunkSize = parsed.clamp(1, telemLogMaxChunkLen);
    final text = _chunkSize.toString();
    if (_chunkController.text != text) _chunkController.text = text;
    PrefsManager.instance.setInt(_chunkPrefsKey, _chunkSize);
  }

  Widget _chunkSizeField(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(child: Text(l10n.telemetryLog_chunkSize)),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _chunkController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            decoration: const InputDecoration(isDense: true),
            onEditingComplete: () {
              setState(_applyChunkSize);
              FocusScope.of(context).unfocus();
            },
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '/ $telemLogMaxChunkLen',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
      ],
    );
  }

  IconData get _shareIcon =>
      PlatformInfo.isDesktop ? Icons.folder_open : Icons.ios_share;
  String _shareTooltip(BuildContext context) => PlatformInfo.isDesktop
      ? context.l10n.telemetryLog_reveal
      : context.l10n.telemetryLog_share;

  Future<void> _sharePath(String path) async {
    // Desktop has no share sheet (share_plus doesn't implement file sharing on
    // Linux/Windows/macOS) and the file is already on local disk — reveal it
    // instead: copy the path and open the containing folder.
    if (PlatformInfo.isDesktop) {
      await _revealOnDesktop(path);
      return;
    }
    // Share the .telemetry file together with the <repeater8>.state.json resume
    // file, so the pair lands in one place ready for telem_import.py.
    final files = [XFile(path)];
    final statePath = await _store.stateFilePath(widget.repeater.publicKeyHex);
    if (statePath != null) files.add(XFile(statePath));
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject: '${widget.repeater.name} telemetry log',
      ),
    );
  }

  Future<void> _exportLog(String telemetryPath) async {
    final l10n = context.l10n;
    final repeaterHex = widget.repeater.publicKeyHex;
    if (PlatformInfo.isDesktop) {
      // Desktop: pick a real directory and copy the raw files in, ready for
      // telem_import.py. Fall back to revealing the source folder if the native
      // directory picker is unavailable.
      String? dir;
      try {
        dir = await FilePicker.getDirectoryPath(
          dialogTitle: l10n.telemetryLog_exportTitle,
        );
      } catch (_) {
        dir = null;
      }
      if (dir == null) {
        await _revealOnDesktop(telemetryPath);
        return;
      }
      final written = await _store.exportSessionTo(dir, telemetryPath, repeaterHex);
      if (!mounted) return;
      _snack(
        written.isEmpty
            ? l10n.telemetryLog_exportFailed
            : l10n.telemetryLog_exported(dir),
      );
      return;
    }

    // iOS has no SAF persisted-tree equivalent — fall back to the share sheet
    // (which already bundles both files).
    if (!PlatformInfo.isAndroid) {
      await _sharePath(telemetryPath);
      return;
    }

    // Android: write the loose files into a SAF folder the user picks once (and
    // that's remembered after) — e.g. a folder synced to a PC.
    final entries = await _store.exportPayload(telemetryPath, repeaterHex);
    if (entries.isEmpty) {
      if (mounted) _snack(l10n.telemetryLog_exportFailed);
      return;
    }
    final treeUri = await _saf.resolveDirectory();
    if (treeUri == null) return; // cancelled
    try {
      await _saf.writeEntries(treeUri, entries);
    } catch (e) {
      appLogger.warn('Telemetry export failed: $e', tag: 'TelemLog');
      if (mounted) _snack(l10n.telemetryLog_exportFailed);
      return;
    }
    if (!mounted) return;
    setState(() {}); // a first export may have just set the folder
    _snack(l10n.telemetryLog_exported(_saf.rememberedFolderPath ?? 'folder'));
  }

  Future<void> _changeExportFolder() async {
    final picked = await _saf.pickDirectory();
    if (!mounted || picked == null) return;
    setState(() {});
    _snack(context.l10n.telemetryLog_exportFolderSet(_saf.rememberedFolderPath ?? ''));
  }

  Widget _exportFolderCard(BuildContext context) {
    final l10n = context.l10n;
    final folder = _saf.rememberedFolderPath;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(l10n.telemetryLog_exportFolder),
        subtitle: Text(folder ?? l10n.telemetryLog_exportFolderNotSet),
        trailing: TextButton(
          onPressed: _changeExportFolder,
          child: Text(
            folder == null ? l10n.telemetryLog_choose : l10n.telemetryLog_change,
          ),
        ),
      ),
    );
  }

  Widget _storageFolderCard(BuildContext context) {
    final l10n = context.l10n;
    final dir = _storageDir!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(l10n.telemetryLog_storageFolder),
        subtitle: Text(dir, style: const TextStyle(fontSize: 12)),
        trailing: TextButton(
          onPressed: () => _openDir(dir),
          child: Text(l10n.telemetryLog_open),
        ),
      ),
    );
  }

  Future<void> _openDir(String dir) async {
    await Clipboard.setData(ClipboardData(text: dir));
    try {
      await launchUrl(Uri.file(dir));
    } catch (_) {
      // Best effort: the path is on the clipboard regardless.
    }
    if (!mounted) return;
    _snack(context.l10n.telemetryLog_pathCopied(dir));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _revealOnDesktop(String path) async {
    final dir = path.contains('/')
        ? path.substring(0, path.lastIndexOf('/'))
        : path;
    await Clipboard.setData(ClipboardData(text: path));
    try {
      await launchUrl(Uri.file(dir));
    } catch (_) {
      // Best effort: the path is on the clipboard regardless.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.telemetryLog_pathCopied(path))),
    );
  }

  Future<void> _deleteLog(TelemetryLogFile file) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.telemetryLog_deleteTitle),
        content: Text(l10n.telemetryLog_deleteConfirm(file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.telemetryLog_delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.deleteLogFile(file.path);
    await _reloadSavedLogs();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _service.status == TelemetryLogFetchStatus.fetching;
    // savedFilePath belongs to the global service's last fetch — only expose
    // share/export when that fetch was for the repeater we're showing.
    final myFile = _isMyFetch ? _service.savedFilePath : null;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          children: [
            Text(l10n.telemetryLog_title),
            Text(
              widget.repeater.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          if (myFile != null)
            IconButton(
              tooltip: _shareTooltip(context),
              icon: Icon(_shareIcon),
              onPressed: busy ? null : () => _sharePath(myFile),
            ),
          IconButton(
            tooltip: l10n.telemetryLog_refresh,
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : () => _startFetch(),
          ),
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (v) {
              if (v == 'restart') _startFetch(forceRestart: true);
              if (v == 'export' && myFile != null) _exportLog(myFile);
            },
            itemBuilder: (context) => [
              if (myFile != null)
                PopupMenuItem(
                  value: 'export',
                  child: Text(l10n.telemetryLog_export),
                ),
              PopupMenuItem(
                value: 'restart',
                child: Text(l10n.telemetryLog_restart),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _statusCard(context),
          ..._buildContent(context),
          if (PlatformInfo.isAndroid) _exportFolderCard(context),
          if (PlatformInfo.isDesktop && _storageDir != null)
            _storageFolderCard(context),
          if (_savedLogs.isNotEmpty) _savedLogsCard(context),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final l10n = context.l10n;
    final s = _service;

    // The single fetch slot is busy with a different repeater.
    if (s.status == TelemetryLogFetchStatus.fetching && !_isMyFetch) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.telemetryLog_busyElsewhere(s.target?.name ?? ''),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final status = _isMyFetch ? s.status : TelemetryLogFetchStatus.idle;
    Widget child;
    switch (status) {
      case TelemetryLogFetchStatus.fetching:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.telemetryLog_fetching),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: s.totalSize > 0 ? s.progress : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(l10n.telemetryLog_bytes(s.bytesFetched, s.totalSize)),
                ),
                TextButton.icon(
                  onPressed: () => _service.cancel(),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(l10n.common_cancel),
                ),
              ],
            ),
            Text(
              l10n.telemetryLog_backgroundHint,
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ],
        );
        break;
      case TelemetryLogFetchStatus.error:
        final String message;
        if (s.noResponse) {
          message = l10n.telemetryLog_noResponse;
        } else if (s.lastStatusCode == respTelemLogUnauth) {
          message = l10n.telemetryLog_unauthorized;
        } else {
          message = l10n.telemetryLog_error(s.errorMessage ?? '');
        }
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            const SizedBox(height: 12),
            _chunkSizeField(context),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _startFetch(),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.telemetryLog_retry),
              ),
            ),
          ],
        );
        break;
      case TelemetryLogFetchStatus.done:
        if (s.totalSize == 0) {
          child = Text(l10n.telemetryLog_noLog);
        } else if (_ticks.isEmpty) {
          child = Text(l10n.telemetryLog_noSamples);
        } else {
          child = _summary(context);
        }
        break;
      case TelemetryLogFetchStatus.idle:
        child = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.telemetryLog_idleHint),
            const SizedBox(height: 8),
            _chunkSizeField(context),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _startFetch(),
                icon: const Icon(Icons.download),
                label: Text(l10n.telemetryLog_fetch),
              ),
            ),
          ],
        );
        break;
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _summary(BuildContext context) {
    final l10n = context.l10n;
    final log = _cachedLog!;
    final firstTs = _ticks.first.first.timestamp;
    final lastTs = _ticks.last.first.timestamp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.telemetryLog_samples(_ticks.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (_service.loggingActive)
              Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.fiber_manual_record,
                    size: 12, color: Colors.green),
                label: Text(l10n.telemetryLog_loggingActive),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(l10n.telemetryLog_interval(log.header.intervalSeconds)),
        Text('${_fmtTime(firstTs)} → ${_fmtTime(lastTs)}'),
        if (_service.resumed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.telemetryLog_resumed,
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
          ),
        if (_service.savedFilePath != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.telemetryLog_savedTo(_fileName(_service.savedFilePath!)),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ),
      ],
    );
  }

  String _fileName(String path) =>
      path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;

  List<Widget> _buildContent(BuildContext context) {
    if (_service.status != TelemetryLogFetchStatus.done ||
        _cachedLog == null ||
        _ticks.isEmpty) {
      return const [];
    }
    final widgets = <Widget>[];
    for (var ci = 0; ci < _cachedLog!.channels.length; ci++) {
      widgets.add(_channelCard(context, ci));
    }
    widgets.add(_samplesTable(context));
    return widgets;
  }

  Widget _channelCard(BuildContext context, int channelIndex) {
    final l10n = context.l10n;
    final channel = _cachedLog!.channels[channelIndex];
    final title = channel.name.isNotEmpty
        ? channel.name
        : l10n.telemetryLog_channel(channel.lppChannel);

    // Latest non-null reading per type, scanning from the most recent tick back.
    final latest = <_TypeReading, String>{};
    for (var i = _ticks.length - 1; i >= 0 && latest.length < _allTypes.length; i--) {
      final sample = _ticks[i][channelIndex];
      for (final type in _allTypes) {
        if (latest.containsKey(type)) continue;
        if (channel.flags & type.bit == 0) continue;
        final value = type.read(sample);
        if (value != null) latest[type] = value;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              l10n.telemetryLog_channel(channel.lppChannel),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
            const Divider(),
            for (final type in _allTypes)
              if (channel.flags & type.bit != 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(type.label),
                      Text(
                        latest[type] ?? '—',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _samplesTable(BuildContext context) {
    final l10n = context.l10n;
    // Build columns: Time + one per (channel, enabled type).
    final columns = <DataColumn>[DataColumn(label: Text(l10n.telemetryLog_time))];
    final accessors = <String Function(List<TelemetrySample>)>[];
    final channels = _cachedLog!.channels;
    for (var ci = 0; ci < channels.length; ci++) {
      final channel = channels[ci];
      for (final type in _allTypes) {
        if (channel.flags & type.bit == 0) continue;
        final chLabel = channel.name.isNotEmpty
            ? channel.name
            : 'ch${channel.lppChannel}';
        columns.add(DataColumn(label: Text('$chLabel\n${type.label}')));
        accessors.add((tick) => type.read(tick[ci]) ?? '—');
      }
    }

    // Show the most recent samples (newest first), capped for performance.
    const maxRows = 100;
    final start = _ticks.length > maxRows ? _ticks.length - maxRows : 0;
    final rows = <DataRow>[];
    for (var i = _ticks.length - 1; i >= start; i--) {
      final tick = _ticks[i];
      rows.add(
        DataRow(
          cells: [
            DataCell(Text(_fmtTime(tick.first.timestamp))),
            for (final accessor in accessors) DataCell(Text(accessor(tick))),
          ],
        ),
      );
    }

    return Card(
      child: ExpansionTile(
        title: Text(l10n.telemetryLog_recentSamples),
        childrenPadding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 20,
              headingRowHeight: 48,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: columns,
              rows: rows,
            ),
          ),
        ],
      ),
    );
  }

  Widget _savedLogsCard(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: ExpansionTile(
        title: Text(l10n.telemetryLog_savedLogs(_savedLogs.length)),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          for (final file in _savedLogs)
            ListTile(
              dense: true,
              leading: const Icon(Icons.description_outlined),
              title: Text(file.name, style: const TextStyle(fontSize: 13)),
              subtitle: Text(_fmtFileMeta(file)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _shareTooltip(context),
                    icon: Icon(_shareIcon, size: 20),
                    onPressed: () => _sharePath(file.path),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'export') _exportLog(file.path);
                      if (v == 'delete') _deleteLog(file);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'export',
                        child: Text(l10n.telemetryLog_export),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l10n.telemetryLog_delete),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _fmtFileMeta(TelemetryLogFile file) {
    final kb = (file.sizeBytes / 1024).toStringAsFixed(1);
    final m = file.modified.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    final when =
        '${m.year}-${two(m.month)}-${two(m.day)} ${two(m.hour)}:${two(m.minute)}';
    return '$kb KB · $when';
  }

  String _fmtTime(int epochSeconds) {
    // Anchors with a valid RTC carry real epoch seconds; an unset RTC yields a
    // relative count starting at 0. Distinguish by plausibility.
    if (epochSeconds < 1000000000) {
      return '+${epochSeconds}s';
    }
    final dt = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    ).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _TypeReading {
  final int bit;
  final String label;
  final String? Function(TelemetrySample) _read;
  const _TypeReading(this.bit, this.label, this._read);
  String? read(TelemetrySample s) => _read(s);
}

String? _fmt(double? v, String unit, {int decimals = 1}) =>
    v == null ? null : '${v.toStringAsFixed(decimals)}$unit';

final List<_TypeReading> _allTypes = [
  _TypeReading(telemLogVoltage, 'Voltage', (s) => _fmt(s.voltageV, ' V', decimals: 2)),
  _TypeReading(telemLogNoise, 'Noise', (s) => _fmt(s.noiseDbm, ' dBm', decimals: 0)),
  _TypeReading(telemLogTemperature, 'Temp', (s) => _fmt(s.temperatureC, ' °C')),
  _TypeReading(telemLogPressure, 'Pressure', (s) => _fmt(s.pressureHpa, ' hPa')),
  _TypeReading(telemLogHumidity, 'Humidity', (s) => _fmt(s.humidityPct, ' %')),
  _TypeReading(telemLogCurrent, 'Current', (s) => _fmt(s.currentA, ' A', decimals: 3)),
  _TypeReading(telemLogLuminosity, 'Lux', (s) => _fmt(s.luminosityLux, ' lx', decimals: 0)),
  _TypeReading(telemLogRain, 'Rain', (s) => s.rain == null ? null : (s.rain == 1 ? 'yes' : 'no')),
];
