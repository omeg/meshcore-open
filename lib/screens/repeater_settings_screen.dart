import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../models/repeater_settings_session_snapshot.dart';
import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../services/repeater_command_service.dart';
import '../services/storage_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/routing_sheet.dart';
import '../helpers/snack_bar_builder.dart';

class RepeaterSettingsScreen extends StatefulWidget {
  final Contact repeater;
  final String password;

  const RepeaterSettingsScreen({
    super.key,
    required this.repeater,
    required this.password,
  });

  @override
  State<RepeaterSettingsScreen> createState() => _RepeaterSettingsScreenState();
}

enum _SettingField {
  name,
  radio,
  txPower,
  rxGain,
  lat,
  lon,
  repeat,
  allowReadOnly,
  multiAcks,
  loopDetect,
  dutyCycle,
  ownerInfo,
  floodMax,
  advertInterval,
  floodAdvertInterval,
  pathHashMode,
  txDelay,
  directTxDelay,
  intThresh,
  channelActivityDetection,
  agcResetInterval,
}

enum _SaveOutcome { ok, rebootNeeded, error }

// Firmware reply taxonomy for `set ...` / `password ...` commands
// (see MeshCore CommonCLI.cpp): success replies always start with "OK"
// (any case) or "password now:"; reboot-required successes contain the word
// "reboot" (e.g. "OK - reboot to apply", "OK, reboot to apply! New pubkey:...");
// some replies are parenthesized like "(OK - stats reset)". Anything else
// (Error/ERR/ERROR/unknown/can't/...) is a failure.
_SaveOutcome _classifySaveResponse(String response) {
  var s = response.trim();
  if (s.isEmpty) return _SaveOutcome.error;
  if (s.startsWith('(')) s = s.substring(1);
  final lower = s.toLowerCase();
  if (lower.startsWith('ok') || lower.startsWith('password now')) {
    return lower.contains('reboot')
        ? _SaveOutcome.rebootNeeded
        : _SaveOutcome.ok;
  }
  return _SaveOutcome.error;
}

String _shortCommandLabel(String command) {
  final firstSpace = command.indexOf(' ');
  if (firstSpace == -1) return command;
  if (command.startsWith('set ')) {
    final rest = command.substring(4);
    final nextSpace = rest.indexOf(' ');
    return nextSpace == -1 ? rest : rest.substring(0, nextSpace);
  }
  return command.substring(0, firstSpace);
}

class _RepeaterSettingsScreenState extends State<RepeaterSettingsScreen> {
  final StorageService _storage = StorageService();
  late final MeshCoreConnector _sessionConnector;

  bool _isLoading = false;
  bool _hasChanges = false;
  final Set<_SettingField> _dirtyFields = {};
  final Set<_SettingField> _knownFields = {};
  bool _refreshingBasic = false;
  bool _refreshingRadio = false;
  bool _refreshingTxPower = false;
  bool _refreshingRxGain = false;
  bool _refreshingRepeat = false;
  bool _refreshingAllowReadOnly = false;
  bool _refreshingMultiAcks = false;
  bool _refreshingOwnerInfo = false;
  bool _refreshingLat = false;
  bool _refreshingLon = false;
  bool _refreshingLoopDetect = false;
  bool _refreshingDutyCycle = false;
  bool _refreshingAdvertInterval = false;
  bool _refreshingFloodAdvertInterval = false;
  bool _refreshingFloodMax = false;
  bool _refreshingPathHashMode = false;
  bool _refreshingTxDelay = false;
  bool _refreshingDirectTxDelay = false;
  bool _refreshingIntThresh = false;
  bool _refreshingChannelActivityDetection = false;
  bool _refreshingAgcResetInterval = false;
  bool _runningAction = false;
  StreamSubscription<Uint8List>? _frameSubscription;
  RepeaterCommandService? _commandService;

  // Basic settings
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _guestPasswordController =
      TextEditingController();

  // Radio settings
  final TextEditingController _freqController = TextEditingController();
  final TextEditingController _txPowerController = TextEditingController();
  int? _bandwidth;
  int? _spreadingFactor;
  int? _codingRate;

  // Location settings
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lonController = TextEditingController();
  bool _latInvalid = false;
  bool _lonInvalid = false;

  // Feature toggles
  bool? _repeatEnabled;
  bool? _allowReadOnly;
  bool? _multiAcks;
  bool? _rxGainBoosted;
  bool _autoClockSyncAfterLogin = false;

  // Advertisement settings
  int? _advertInterval; // 0 disables advertisements
  int? _floodAdvertInterval; // 0 disables flood advertisements
  int? _floodMax; // 0-64 hops

  // Network health
  String? _loopDetect; // off|minimal|moderate|strict
  int? _dutyCycle; // 1-100

  // Operator info
  final TextEditingController _ownerInfoController = TextEditingController();

  // Advanced
  int? _pathHashMode; // 0-2
  final TextEditingController _txDelayController = TextEditingController();
  final TextEditingController _directTxDelayController =
      TextEditingController();
  final TextEditingController _intThreshController = TextEditingController();
  bool? _channelActivityDetectionEnabled;
  int? _agcResetInterval; // seconds, multiple of 4, 0 disabled

  static const List<String> _loopDetectOptions = [
    'off',
    'minimal',
    'moderate',
    'strict',
  ];

  final List<int> _bandwidthOptions = [
    7800,
    10400,
    15600,
    20800,
    31250,
    41700,
    62500,
    125000,
    250000,
    500000,
  ];
  final List<int> _spreadingFactorOptions = [5, 6, 7, 8, 9, 10, 11, 12];
  final List<int> _codingRateOptions = [5, 6, 7, 8];

  @override
  void initState() {
    super.initState();
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    _sessionConnector = connector;
    _commandService = RepeaterCommandService(connector);
    _restoreSettingsSessionSnapshot();
    _setupMessageListener();
    _loadSettings();
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _commandService?.dispose();
    _nameController.dispose();
    _passwordController.dispose();
    _guestPasswordController.dispose();
    _freqController.dispose();
    _txPowerController.dispose();
    _latController.dispose();
    _lonController.dispose();
    _ownerInfoController.dispose();
    _txDelayController.dispose();
    _directTxDelayController.dispose();
    _intThreshController.dispose();
    super.dispose();
  }

  void _setupMessageListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);

    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;

      // Check if it's a text message response
      if (frame[0] == respCodeContactMsgRecv ||
          frame[0] == respCodeContactMsgRecvV3) {
        _handleTextMessageResponse(frame);
      }
    });
  }

  void _handleTextMessageResponse(Uint8List frame) {
    final parsed = parseContactMessageText(frame);
    if (parsed == null) return;
    if (!_matchesRepeaterPrefix(parsed.senderPrefix)) return;

    // Notify command service of response (for retry handling)
    _commandService?.handleResponse(widget.repeater, parsed.text);
  }

  int _resolveRepeaterIndex = -1;

  Contact _resolveRepeater(MeshCoreConnector connector) {
    if (_resolveRepeaterIndex >= 0 &&
        _resolveRepeaterIndex < connector.contacts.length &&
        connector.contacts[_resolveRepeaterIndex].publicKeyHex ==
            widget.repeater.publicKeyHex) {
      return connector.contacts[_resolveRepeaterIndex];
    }
    _resolveRepeaterIndex = connector.contacts.indexWhere(
      (c) => c.publicKeyHex == widget.repeater.publicKeyHex,
    );
    if (_resolveRepeaterIndex == -1) {
      return widget.repeater;
    }
    return connector.contacts[_resolveRepeaterIndex];
  }

  bool _matchesRepeaterPrefix(Uint8List prefix) {
    final target = widget.repeater.publicKey;
    if (target.length < 6 || prefix.length < 6) return false;
    for (int i = 0; i < 6; i++) {
      if (prefix[i] != target[i]) return false;
    }
    return true;
  }

  static _SettingField? _fieldForGetKey(String key) {
    return switch (key) {
      'name' => _SettingField.name,
      'radio' => _SettingField.radio,
      'tx' => _SettingField.txPower,
      'lat' => _SettingField.lat,
      'lon' => _SettingField.lon,
      'repeat' => _SettingField.repeat,
      'allow.read.only' => _SettingField.allowReadOnly,
      'advert.interval' => _SettingField.advertInterval,
      'flood.advert.interval' => _SettingField.floodAdvertInterval,
      'radio.rxgain' => _SettingField.rxGain,
      'multi.acks' => _SettingField.multiAcks,
      'loop.detect' => _SettingField.loopDetect,
      'dutycycle' => _SettingField.dutyCycle,
      'owner.info' => _SettingField.ownerInfo,
      'flood.max' => _SettingField.floodMax,
      'path.hash.mode' => _SettingField.pathHashMode,
      'txdelay' => _SettingField.txDelay,
      'direct.txdelay' => _SettingField.directTxDelay,
      'int.thresh' => _SettingField.intThresh,
      'cad' => _SettingField.channelActivityDetection,
      'agc.reset.interval' => _SettingField.agcResetInterval,
      _ => null,
    };
  }

  static String _getKeyForField(_SettingField field) {
    return switch (field) {
      _SettingField.name => 'name',
      _SettingField.radio => 'radio',
      _SettingField.txPower => 'tx',
      _SettingField.lat => 'lat',
      _SettingField.lon => 'lon',
      _SettingField.repeat => 'repeat',
      _SettingField.allowReadOnly => 'allow.read.only',
      _SettingField.advertInterval => 'advert.interval',
      _SettingField.floodAdvertInterval => 'flood.advert.interval',
      _SettingField.rxGain => 'radio.rxgain',
      _SettingField.multiAcks => 'multi.acks',
      _SettingField.loopDetect => 'loop.detect',
      _SettingField.dutyCycle => 'dutycycle',
      _SettingField.ownerInfo => 'owner.info',
      _SettingField.floodMax => 'flood.max',
      _SettingField.pathHashMode => 'path.hash.mode',
      _SettingField.txDelay => 'txdelay',
      _SettingField.directTxDelay => 'direct.txdelay',
      _SettingField.intThresh => 'int.thresh',
      _SettingField.channelActivityDetection => 'cad',
      _SettingField.agcResetInterval => 'agc.reset.interval',
    };
  }

  void _restoreSettingsSessionSnapshot() {
    final snapshot = _sessionConnector.repeaterSettingsSessionSnapshot(
      widget.repeater,
    );
    if (snapshot == null) return;

    for (final entry in snapshot.valuesByKey.entries) {
      final field = _fieldForGetKey(entry.key);
      if (field == null || !_applyGetValue(entry.key, entry.value)) continue;
      _knownFields.add(field);
      if (snapshot.dirtyKeys.contains(entry.key)) {
        _dirtyFields.add(field);
      }
    }
    _hasChanges = _dirtyFields.isNotEmpty;
  }

  String? _currentValueForField(_SettingField field) {
    switch (field) {
      case _SettingField.name:
        return _nameController.text;
      case _SettingField.radio:
        final frequency = _freqController.text.trim();
        if (double.tryParse(frequency) == null ||
            _bandwidth == null ||
            _spreadingFactor == null ||
            _codingRate == null) {
          return null;
        }
        return '$frequency,${_bandwidth! / 1000},$_spreadingFactor,$_codingRate';
      case _SettingField.txPower:
        final value = int.tryParse(_txPowerController.text.trim());
        return value == null || value < 1 || value > 30
            ? null
            : value.toString();
      case _SettingField.lat:
        final value = _latController.text.trim();
        return value.isNotEmpty && _isValidCoordinate(value, 90) ? value : null;
      case _SettingField.lon:
        final value = _lonController.text.trim();
        return value.isNotEmpty && _isValidCoordinate(value, 180)
            ? value
            : null;
      case _SettingField.repeat:
        return _repeatEnabled == null ? null : (_repeatEnabled! ? 'on' : 'off');
      case _SettingField.allowReadOnly:
        return _allowReadOnly == null ? null : (_allowReadOnly! ? 'on' : 'off');
      case _SettingField.multiAcks:
        return _multiAcks == null ? null : (_multiAcks! ? '1' : '0');
      case _SettingField.rxGain:
        return _rxGainBoosted == null ? null : (_rxGainBoosted! ? 'on' : 'off');
      case _SettingField.advertInterval:
        return _advertInterval?.toString();
      case _SettingField.floodAdvertInterval:
        return _floodAdvertInterval?.toString();
      case _SettingField.floodMax:
        return _floodMax?.toString();
      case _SettingField.loopDetect:
        return _loopDetect;
      case _SettingField.dutyCycle:
        return _dutyCycle?.toString();
      case _SettingField.ownerInfo:
        return _ownerInfoController.text.replaceAll('\n', '|');
      case _SettingField.pathHashMode:
        return _pathHashMode?.toString();
      case _SettingField.txDelay:
        final value = _txDelayController.text.trim();
        return double.tryParse(value) == null ? null : value;
      case _SettingField.directTxDelay:
        final value = _directTxDelayController.text.trim();
        return double.tryParse(value) == null ? null : value;
      case _SettingField.intThresh:
        final value = _intThreshController.text.trim();
        return int.tryParse(value) == null ? null : value;
      case _SettingField.channelActivityDetection:
        return _channelActivityDetectionEnabled == null
            ? null
            : (_channelActivityDetectionEnabled! ? 'on' : 'off');
      case _SettingField.agcResetInterval:
        return _agcResetInterval?.toString();
    }
  }

  void _rememberSettingsSessionSnapshot() {
    final valuesByKey = <String, String>{};
    final dirtyKeys = <String>{};
    for (final field in _knownFields) {
      final value = _currentValueForField(field);
      if (value == null) continue;
      final key = _getKeyForField(field);
      valuesByKey[key] = value;
      if (_dirtyFields.contains(field)) dirtyKeys.add(key);
    }
    _sessionConnector.rememberRepeaterSettingsSessionSnapshot(
      widget.repeater,
      RepeaterSettingsSessionSnapshot(
        valuesByKey: valuesByKey,
        dirtyKeys: dirtyKeys,
      ),
    );
  }

  /// Apply a single `get <key>` response value to the relevant UI state.
  /// Caller is responsible for invoking this inside setState.
  /// Returns false for malformed or unsupported values so they remain unknown.
  bool _applyGetValue(String key, String value) {
    switch (key) {
      case 'name':
        _nameController.text = value;
        return true;
      case 'radio':
        return _applyRadioValue(value);
      case 'tx':
        final dbm = int.tryParse(value.replaceAll(RegExp(r'[^0-9-]'), ''));
        if (dbm != null && dbm >= 1 && dbm <= 30) {
          _txPowerController.text = dbm.toString();
          return true;
        }
        return false;
      case 'lat':
        if (!_isValidCoordinate(value, 90) || value.trim().isEmpty) {
          return false;
        }
        _latController.text = value.trim();
        return true;
      case 'lon':
        if (!_isValidCoordinate(value, 180) || value.trim().isEmpty) {
          return false;
        }
        _lonController.text = value.trim();
        return true;
      case 'repeat':
        _repeatEnabled = _tryParseOnOff(value);
        return _repeatEnabled != null;
      case 'allow.read.only':
        _allowReadOnly = _tryParseOnOff(value);
        return _allowReadOnly != null;
      case 'advert.interval':
        final v = int.tryParse(value.trim());
        if (v != null && (v == 0 || (v >= 60 && v <= 240))) {
          _advertInterval = v;
          return true;
        }
        return false;
      case 'flood.advert.interval':
        final v = int.tryParse(value.trim());
        if (v != null && (v == 0 || (v >= 3 && v <= 168))) {
          _floodAdvertInterval = v;
          return true;
        }
        return false;
      case 'radio.rxgain':
        _rxGainBoosted = _tryParseOnOff(value);
        return _rxGainBoosted != null;
      case 'multi.acks':
        // Firmware reply is "0" or "1".
        _multiAcks = _tryParseOnOff(value);
        return _multiAcks != null;
      case 'loop.detect':
        final lower = value.trim().toLowerCase();
        if (!_loopDetectOptions.contains(lower)) return false;
        _loopDetect = lower;
        return true;
      case 'dutycycle':
        // Reply is "<int>.<int>%" e.g. "50.0%".
        final pct = double.tryParse(value.replaceAll('%', '').trim());
        if (pct == null || pct < 1 || pct > 100) return false;
        _dutyCycle = pct.toInt();
        return true;
      case 'owner.info':
        // Firmware translates internal newlines back to '|' on the wire.
        _ownerInfoController.text = value.replaceAll('|', '\n');
        return true;
      case 'flood.max':
        final v = int.tryParse(value.trim());
        if (v == null || v < 0 || v > 64) return false;
        _floodMax = v;
        return true;
      case 'path.hash.mode':
        final v = int.tryParse(value.trim());
        if (v == null || v < 0 || v > 2) return false;
        _pathHashMode = v;
        return true;
      case 'txdelay':
        if (double.tryParse(value.trim()) == null) return false;
        _txDelayController.text = value.trim();
        return true;
      case 'direct.txdelay':
        if (double.tryParse(value.trim()) == null) return false;
        _directTxDelayController.text = value.trim();
        return true;
      case 'int.thresh':
        if (int.tryParse(value.trim()) == null) return false;
        _intThreshController.text = value.trim();
        return true;
      case 'cad':
        _channelActivityDetectionEnabled = _tryParseOnOff(value);
        return _channelActivityDetectionEnabled != null;
      case 'agc.reset.interval':
        final v = int.tryParse(value.trim());
        if (v == null || v < 0 || v > 240 || v % 4 != 0) return false;
        _agcResetInterval = v;
        return true;
      default:
        return false;
    }
  }

  /// Parse the firmware "freq,bw,sf,cr" radio reply (e.g. "908.205017,62.5,10,7").
  bool _applyRadioValue(String radioStr) {
    final parts = radioStr.split(',');
    if (parts.length != 4) return false;
    final freqText = parts[0].trim();
    final frequency = double.tryParse(freqText);
    final bandwidthKHz = double.tryParse(parts[1].trim());
    final spreadingFactor = int.tryParse(parts[2].trim());
    final codingRate = int.tryParse(parts[3].trim());
    if (frequency == null ||
        frequency < 300 ||
        frequency > 2500 ||
        bandwidthKHz == null ||
        bandwidthKHz <= 0 ||
        spreadingFactor == null ||
        !_spreadingFactorOptions.contains(spreadingFactor) ||
        codingRate == null ||
        !_codingRateOptions.contains(codingRate)) {
      return false;
    }

    final bandwidth = (bandwidthKHz * 1000).round();
    _freqController.text = freqText;
    _bandwidth = bandwidth;
    _spreadingFactor = spreadingFactor;
    _codingRate = codingRate;
    if (!_bandwidthOptions.contains(bandwidth)) {
      _bandwidthOptions.add(bandwidth);
      _bandwidthOptions.sort();
    }
    return true;
  }

  bool? _tryParseOnOff(String value) {
    final lower = value.trim().toLowerCase();
    if (lower == 'on' ||
        lower == 'true' ||
        lower == '1' ||
        lower == 'enabled') {
      return true;
    }
    if (lower == 'off' ||
        lower == 'false' ||
        lower == '0' ||
        lower == 'disabled') {
      return false;
    }
    return null;
  }

  String _formatBandwidthLabel(int bandwidthHz) {
    final bandwidthKHz = bandwidthHz / 1000;
    var text = bandwidthKHz.toStringAsFixed(2);
    text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    return '$text kHz';
  }

  /// Decode a `get <key>` response and apply it to local state.
  /// Returns true if a value was applied.
  ///
  /// Response/command pairing is guaranteed by the prefix-matching layer in
  /// RepeaterCommandService (firmware echoes the `XX|` token from MyMesh.cpp),
  /// so no shape-based validation is needed here — `tryParse` handles any
  /// malformed value by leaving state untouched.
  bool _handleGetResponse(String command, String response) {
    final normalized = command.trim().toLowerCase();
    if (!normalized.startsWith('get ')) return false;
    final key = normalized.substring(4).trim();
    final value = _extractGetValue(response);
    if (value == null) return false;
    final field = _fieldForGetKey(key);
    if (field == null) return false;
    var applied = false;
    setState(() {
      applied = _applyGetValue(key, value);
      if (applied) _knownFields.add(field);
    });
    if (applied) _rememberSettingsSessionSnapshot();
    return applied;
  }

  /// Firmware GET replies are always `> <value>` (CommonCLI.cpp `sprintf(reply, "> %s", ...)`).
  /// Returns the first such value, trimmed; null if none found.
  String? _extractGetValue(String response) {
    for (final line in response.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('>')) {
        return trimmed.substring(1).trim();
      }
    }
    return null;
  }

  Future<void> _refreshSection({
    required String label,
    required List<String> commands,
    required ValueSetter<bool> setRefreshing,
  }) async {
    if (_commandService == null) return;
    final l10n = context.l10n;

    setState(() => setRefreshing(true));

    var successCount = 0;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);
    for (final command in commands) {
      try {
        final response = await _commandService!.sendCommand(
          repeater,
          command,
          retries: 1,
        );
        if (_handleGetResponse(command, response)) successCount += 1;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('Error fetching $command: $e');
      }
    }

    if (mounted) {
      showDismissibleSnackBar(
        context,
        content: Text(
          successCount > 0
              ? l10n.repeater_refreshed(label)
              : l10n.repeater_errorRefreshing(label),
        ),
        backgroundColor: successCount > 0
            ? null
            : Theme.of(context).colorScheme.error,
      );
      setState(() => setRefreshing(false));
    }
  }

  Future<void> _refreshBasicSettings() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_basicSettings,
      commands: const ['get name'],
      setRefreshing: (value) => _refreshingBasic = value,
    );
  }

  Future<void> _refreshRadioSettings() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_radioSettings,
      commands: const ['get radio'],
      setRefreshing: (value) => _refreshingRadio = value,
    );
  }

  Future<void> _refreshTxPower() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_txPower,
      commands: const ['get tx'],
      setRefreshing: (value) => _refreshingTxPower = value,
    );
  }

  Future<void> _refreshRepeat() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_packetForwarding,
      commands: const ['get repeat'],
      setRefreshing: (value) => _refreshingRepeat = value,
    );
  }

  Future<void> _refreshAllowReadOnly() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_guestAccess,
      commands: const ['get allow.read.only'],
      setRefreshing: (value) => _refreshingAllowReadOnly = value,
    );
  }

  Future<void> _refreshRxGain() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_rxGain,
      commands: const ['get radio.rxgain'],
      setRefreshing: (value) => _refreshingRxGain = value,
    );
  }

  Future<void> _refreshMultiAcks() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_multiAcks,
      commands: const ['get multi.acks'],
      setRefreshing: (value) => _refreshingMultiAcks = value,
    );
  }

  Future<void> _refreshOwnerInfo() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_ownerInfo,
      commands: const ['get owner.info'],
      setRefreshing: (value) => _refreshingOwnerInfo = value,
    );
  }

  Future<void> _refreshLat() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_latitude,
      commands: const ['get lat'],
      setRefreshing: (value) => _refreshingLat = value,
    );
  }

  Future<void> _refreshLon() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_longitude,
      commands: const ['get lon'],
      setRefreshing: (value) => _refreshingLon = value,
    );
  }

  Future<void> _refreshLoopDetect() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_loopDetect,
      commands: const ['get loop.detect'],
      setRefreshing: (value) => _refreshingLoopDetect = value,
    );
  }

  Future<void> _refreshDutyCycle() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_dutyCycle,
      commands: const ['get dutycycle'],
      setRefreshing: (value) => _refreshingDutyCycle = value,
    );
  }

  Future<void> _refreshAdvertInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_localAdvertInterval,
      commands: const ['get advert.interval'],
      setRefreshing: (value) => _refreshingAdvertInterval = value,
    );
  }

  Future<void> _refreshFloodAdvertInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_floodAdvertInterval,
      commands: const ['get flood.advert.interval'],
      setRefreshing: (value) => _refreshingFloodAdvertInterval = value,
    );
  }

  Future<void> _refreshFloodMax() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_floodMax,
      commands: const ['get flood.max'],
      setRefreshing: (value) => _refreshingFloodMax = value,
    );
  }

  Future<void> _refreshPathHashMode() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_pathHashMode,
      commands: const ['get path.hash.mode'],
      setRefreshing: (value) => _refreshingPathHashMode = value,
    );
  }

  Future<void> _refreshTxDelay() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_txDelay,
      commands: const ['get txdelay'],
      setRefreshing: (value) => _refreshingTxDelay = value,
    );
  }

  Future<void> _refreshDirectTxDelay() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_directTxDelay,
      commands: const ['get direct.txdelay'],
      setRefreshing: (value) => _refreshingDirectTxDelay = value,
    );
  }

  Future<void> _refreshIntThresh() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_intThresh,
      commands: const ['get int.thresh'],
      setRefreshing: (value) => _refreshingIntThresh = value,
    );
  }

  Future<void> _refreshChannelActivityDetection() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_channelActivityDetection,
      commands: const ['get cad'],
      setRefreshing: (value) => _refreshingChannelActivityDetection = value,
    );
  }

  Future<void> _refreshAgcResetInterval() async {
    final l10n = context.l10n;
    await _refreshSection(
      label: l10n.repeater_agcResetInterval,
      commands: const ['get agc.reset.interval'],
      setRefreshing: (value) => _refreshingAgcResetInterval = value,
    );
  }

  /// Send a one-shot CLI action (advert / clock sync / etc.) and surface the
  /// firmware's reply via snackbar. Not part of the dirty-field save flow.
  Future<void> _runAction(String command, String label) async {
    if (_commandService == null) return;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);
    final l10n = context.l10n;
    setState(() => _runningAction = true);
    try {
      final response = await _commandService!.sendCommand(
        repeater,
        command,
        retries: 1,
      );
      if (!mounted) return;
      final outcome = _classifySaveResponse(response);
      showDismissibleSnackBar(
        context,
        content: Text(
          outcome == _SaveOutcome.error
              ? l10n.repeater_actionFailed(label, response.trim())
              : l10n.repeater_actionSucceeded(label),
        ),
        backgroundColor: outcome == _SaveOutcome.error
            ? Theme.of(context).colorScheme.error
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(l10n.repeater_actionFailed(label, e.toString())),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) setState(() => _runningAction = false);
    }
  }

  Future<void> _loadSettings() async {
    // Node-backed settings deliberately remain unknown until a successful
    // `get` response arrives. This local preference is the only initial value.
    final autoClockSync = await _storage
        .getRepeaterAutoClockSyncAfterLoginEnabled(
          widget.repeater.publicKeyHex,
        );
    if (!mounted) return;
    setState(() {
      _autoClockSyncAfterLogin = autoClockSync;
    });
  }

  Future<void> _saveSettings() async {
    if (_commandService == null) return;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);

    setState(() {
      _isLoading = true;
    });

    try {
      // Each pending command remembers the dirty-field it came from (null for
      // password commands, which always re-send when text is present). On
      // failure we keep that field in `_dirtyFields` so the Save button stays
      // available and the user can retry.
      final pending = <({_SettingField? field, String command})>[];

      if (_shouldSave(_SettingField.name) && _nameController.text.isNotEmpty) {
        pending.add((
          field: _SettingField.name,
          command: 'set name ${_nameController.text}',
        ));
      }

      // Passwords are write-only; send whenever a value was typed.
      if (_passwordController.text.isNotEmpty) {
        pending.add((
          field: null,
          command: 'password ${_passwordController.text}',
        ));
      }
      if (_guestPasswordController.text.isNotEmpty) {
        pending.add((
          field: null,
          command: 'set guest.password ${_guestPasswordController.text}',
        ));
      }

      // Radio parameters are bundled in a single command.
      if (_shouldSave(_SettingField.radio) &&
          _freqController.text.isNotEmpty &&
          _bandwidth != null &&
          _spreadingFactor != null &&
          _codingRate != null) {
        final freqText = _freqController.text.trim();
        if (double.tryParse(freqText) != null) {
          final bwKHz = _bandwidth! / 1000;
          pending.add((
            field: _SettingField.radio,
            command:
                'set radio $freqText,$bwKHz,$_spreadingFactor,$_codingRate',
          ));
        }
      }

      if (_shouldSave(_SettingField.txPower) &&
          _txPowerController.text.isNotEmpty) {
        final dbm = int.tryParse(_txPowerController.text.trim());
        if (dbm != null) {
          pending.add((field: _SettingField.txPower, command: 'set tx $dbm'));
        }
      }

      if (_shouldSave(_SettingField.lat) &&
          _latController.text.isNotEmpty &&
          _isValidCoordinate(_latController.text, 90)) {
        pending.add((
          field: _SettingField.lat,
          command: 'set lat ${_latController.text}',
        ));
      }
      if (_shouldSave(_SettingField.lon) &&
          _lonController.text.isNotEmpty &&
          _isValidCoordinate(_lonController.text, 180)) {
        pending.add((
          field: _SettingField.lon,
          command: 'set lon ${_lonController.text}',
        ));
      }

      if (_shouldSave(_SettingField.repeat)) {
        pending.add((
          field: _SettingField.repeat,
          command: 'set repeat ${_repeatEnabled! ? "on" : "off"}',
        ));
      }
      if (_shouldSave(_SettingField.allowReadOnly)) {
        pending.add((
          field: _SettingField.allowReadOnly,
          command: 'set allow.read.only ${_allowReadOnly! ? "on" : "off"}',
        ));
      }

      if (_shouldSave(_SettingField.advertInterval)) {
        pending.add((
          field: _SettingField.advertInterval,
          command: 'set advert.interval ${_advertInterval!}',
        ));
      }
      if (_shouldSave(_SettingField.floodAdvertInterval)) {
        pending.add((
          field: _SettingField.floodAdvertInterval,
          command: 'set flood.advert.interval ${_floodAdvertInterval!}',
        ));
      }
      if (_shouldSave(_SettingField.floodMax)) {
        pending.add((
          field: _SettingField.floodMax,
          command: 'set flood.max ${_floodMax!}',
        ));
      }

      if (_shouldSave(_SettingField.rxGain)) {
        pending.add((
          field: _SettingField.rxGain,
          command: 'set radio.rxgain ${_rxGainBoosted! ? "on" : "off"}',
        ));
      }
      if (_shouldSave(_SettingField.multiAcks)) {
        pending.add((
          field: _SettingField.multiAcks,
          command: 'set multi.acks ${_multiAcks! ? 1 : 0}',
        ));
      }
      if (_shouldSave(_SettingField.loopDetect)) {
        pending.add((
          field: _SettingField.loopDetect,
          command: 'set loop.detect ${_loopDetect!}',
        ));
      }
      if (_shouldSave(_SettingField.dutyCycle)) {
        pending.add((
          field: _SettingField.dutyCycle,
          command: 'set dutycycle ${_dutyCycle!}',
        ));
      }
      if (_shouldSave(_SettingField.ownerInfo)) {
        // Firmware splits on '|', treating it as newline.
        final encoded = _ownerInfoController.text.replaceAll('\n', '|');
        pending.add((
          field: _SettingField.ownerInfo,
          command: 'set owner.info $encoded',
        ));
      }
      if (_shouldSave(_SettingField.pathHashMode)) {
        pending.add((
          field: _SettingField.pathHashMode,
          command: 'set path.hash.mode ${_pathHashMode!}',
        ));
      }
      if (_shouldSave(_SettingField.txDelay) &&
          _txDelayController.text.isNotEmpty) {
        final v = double.tryParse(_txDelayController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.txDelay,
            command: 'set txdelay $v',
          ));
        }
      }
      if (_shouldSave(_SettingField.directTxDelay) &&
          _directTxDelayController.text.isNotEmpty) {
        final v = double.tryParse(_directTxDelayController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.directTxDelay,
            command: 'set direct.txdelay $v',
          ));
        }
      }
      if (_shouldSave(_SettingField.intThresh) &&
          _intThreshController.text.isNotEmpty) {
        final v = int.tryParse(_intThreshController.text.trim());
        if (v != null) {
          pending.add((
            field: _SettingField.intThresh,
            command: 'set int.thresh $v',
          ));
        }
      }
      if (_shouldSave(_SettingField.channelActivityDetection)) {
        pending.add((
          field: _SettingField.channelActivityDetection,
          command:
              'set cad ${_channelActivityDetectionEnabled! ? "on" : "off"}',
        ));
      }
      if (_shouldSave(_SettingField.agcResetInterval)) {
        pending.add((
          field: _SettingField.agcResetInterval,
          command: 'set agc.reset.interval ${_agcResetInterval!}',
        ));
      }

      final failures = <String>[];
      final retainDirty = <_SettingField>{};
      var passwordsFailed = false;
      var rebootNeeded = false;
      for (final entry in pending) {
        var failed = false;
        try {
          final response = await _commandService!.sendCommand(
            repeater,
            entry.command,
            retries: 1,
          );
          final outcome = _classifySaveResponse(response);
          if (outcome == _SaveOutcome.error) {
            failures.add(
              '${_shortCommandLabel(entry.command)}: ${response.trim()}',
            );
            failed = true;
          } else if (outcome == _SaveOutcome.rebootNeeded) {
            rebootNeeded = true;
          }
        } catch (e) {
          failures.add('${_shortCommandLabel(entry.command)}: ${e.toString()}');
          failed = true;
        }
        if (failed) {
          if (entry.field != null) {
            retainDirty.add(entry.field!);
          } else {
            passwordsFailed = true;
          }
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      // Only clear password fields if every password command succeeded —
      // otherwise the user keeps their typed value to retry.
      if (!passwordsFailed) {
        _passwordController.clear();
        _guestPasswordController.clear();
      }
      setState(() {
        _isLoading = false;
        _dirtyFields
          ..clear()
          ..addAll(retainDirty);
        _hasChanges = _dirtyFields.isNotEmpty || passwordsFailed;
      });
      _rememberSettingsSessionSnapshot();

      if (mounted) {
        final l10n = context.l10n;
        if (failures.isEmpty && rebootNeeded) {
          showDismissibleSnackBar(
            context,
            content: Text(l10n.repeater_settingsSavedRebootNeeded),
            backgroundColor: Theme.of(context).colorScheme.tertiary,
          );
        } else if (failures.isEmpty) {
          showDismissibleSnackBar(
            context,
            content: Text(l10n.repeater_settingsSaved),
          );
        } else {
          showDismissibleSnackBar(
            context,
            content: Text(
              l10n.repeater_settingsPartialFailure(failures.join('; ')),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          );
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(
            context.l10n.repeater_errorSavingSettings(e.toString()),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  bool _shouldSave(_SettingField field) {
    return _knownFields.contains(field) && _dirtyFields.contains(field);
  }

  void _markChanged(_SettingField field) {
    final wasKnown = _knownFields.contains(field);
    final wasDirty = _dirtyFields.contains(field);
    _knownFields.add(field);
    _dirtyFields.add(field);
    final needsRebuild = !wasKnown || !wasDirty || !_hasChanges;
    _hasChanges = true;
    _rememberSettingsSessionSnapshot();
    if (needsRebuild) setState(() {});
  }

  static bool _isValidCoordinate(String text, double max) {
    if (text.trim().isEmpty) return true;
    final value = double.tryParse(text.trim());
    return value != null && value >= -max && value <= max;
  }

  void _flagHasChanges() {
    if (!_hasChanges) {
      setState(() {
        _hasChanges = true;
      });
    }
  }

  TextStyle _unknownStyle() {
    return TextStyle(
      color: Theme.of(context).colorScheme.tertiary,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
    );
  }

  Widget _unknownValue(_SettingField field, {String suffix = ''}) {
    return Text(
      context.l10n.repeater_valueUnknown,
      key: ValueKey('unknown-${field.name}$suffix'),
      style: _unknownStyle(),
    );
  }

  Widget _unknownBooleanPicker({
    required _SettingField field,
    required ValueChanged<bool> onSelected,
  }) {
    final l10n = context.l10n;
    return PopupMenuButton<bool>(
      tooltip: l10n.repeater_valueUnknown,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: false,
          child: Row(
            children: [
              const Icon(Icons.toggle_off_outlined),
              const SizedBox(width: 8),
              Text(l10n.common_disable),
            ],
          ),
        ),
        PopupMenuItem(
          value: true,
          child: Row(
            children: [
              const Icon(Icons.toggle_on_outlined),
              const SizedBox(width: 8),
              Text(l10n.common_enable),
            ],
          ),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _unknownValue(field, suffix: '-picker'),
          Icon(
            Icons.arrow_drop_down,
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ],
      ),
    );
  }

  InputDecoration _settingDecoration({
    required _SettingField field,
    required String labelText,
    String? helperText,
    int? helperMaxLines,
    String? suffixText,
    String? errorText,
  }) {
    final isUnknown = !_knownFields.contains(field);
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      helperMaxLines: helperMaxLines,
      suffixText: suffixText,
      errorText: errorText,
      hintText: isUnknown ? context.l10n.repeater_valueUnknown : null,
      hintStyle: isUnknown ? _unknownStyle() : null,
      filled: isUnknown,
      fillColor: isUnknown
          ? Theme.of(
              context,
            ).colorScheme.tertiaryContainer.withValues(alpha: .14)
          : null,
    );
  }

  Widget _buildInlineRefreshButton({
    required bool isRefreshing,
    required VoidCallback onRefresh,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: IconButton(
        icon: isRefreshing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 20),
        onPressed: isRefreshing ? null : onRefresh,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    final repeater = _resolveRepeater(connector);
    final isFloodMode = repeater.pathOverride == -1;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.repeater_settingsTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(isFloodMode ? Icons.waves : Icons.route),
            tooltip: l10n.repeater_routingMode,
            onPressed: () =>
                ContactRoutingSheet.show(context, contact: repeater),
          ),
          if (_hasChanges)
            TextButton.icon(
              onPressed: _isLoading ? null : _saveSettings,
              icon: const Icon(Icons.save),
              label: Text(l10n.common_save),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _buildBasicSettingsCard(),
            _buildRadioSettingsCard(),
            _buildLocationSettingsCard(),
            _buildFeatureTogglesCard(),
            _buildNetworkHealthCard(),
            _buildAdvertisementSettingsCard(),
            _buildOwnerInfoCard(),
            _buildActionsCard(),
            _buildAdvancedCard(),
            const SizedBox(height: 16),
            _buildDangerZoneCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSettingsCard() {
    final l10n = context.l10n;
    final refreshButton = _refreshingBasic
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _refreshBasicSettings,
            tooltip: l10n.repeater_refreshBasicSettings,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_basicSettings, trailing: refreshButton),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: _settingDecoration(
                  field: _SettingField.name,
                  labelText: l10n.repeater_repeaterName,
                  helperText: l10n.repeater_repeaterNameHelper,
                ),
                onChanged: (_) => _markChanged(_SettingField.name),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: l10n.repeater_adminPassword,
                  helperText: l10n.repeater_adminPasswordHelper,
                ),
                obscureText: true,
                onChanged: (_) => _flagHasChanges(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _guestPasswordController,
                decoration: InputDecoration(
                  labelText: l10n.repeater_guestPassword,
                  helperText: l10n.repeater_guestPasswordHelper,
                ),
                obscureText: true,
                onChanged: (_) => _flagHasChanges(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRadioSettingsCard() {
    final l10n = context.l10n;
    final refreshButton = _refreshingRadio
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _refreshRadioSettings,
            tooltip: l10n.repeater_refreshRadioSettings,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_radioSettings, trailing: refreshButton),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _freqController,
                decoration: _settingDecoration(
                  field: _SettingField.radio,
                  labelText: l10n.repeater_frequencyMhz,
                  helperText: l10n.repeater_frequencyHelper,
                  suffixText: 'MHz',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => _markChanged(_SettingField.radio),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _txPowerController,
                      decoration: _settingDecoration(
                        field: _SettingField.txPower,
                        labelText: l10n.repeater_txPower,
                        helperText: l10n.repeater_txPowerHelper,
                        suffixText: 'dBm',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => _markChanged(_SettingField.txPower),
                    ),
                  ),
                  _buildInlineRefreshButton(
                    isRefreshing: _refreshingTxPower,
                    onRefresh: _refreshTxPower,
                    tooltip: l10n.repeater_refreshTxPower,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('bandwidth-${_bandwidth ?? 'unknown'}'),
                initialValue: _bandwidth,
                decoration: _settingDecoration(
                  field: _SettingField.radio,
                  labelText: l10n.repeater_bandwidth,
                ),
                hint: _unknownValue(_SettingField.radio, suffix: '-bandwidth'),
                items: _bandwidthOptions.map((bw) {
                  return DropdownMenuItem(
                    value: bw,
                    child: Text(_formatBandwidthLabel(bw)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _bandwidth = value;
                    });
                    _markChanged(_SettingField.radio);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'spreading-factor-${_spreadingFactor ?? 'unknown'}',
                ),
                initialValue: _spreadingFactor,
                decoration: _settingDecoration(
                  field: _SettingField.radio,
                  labelText: l10n.repeater_spreadingFactor,
                ),
                hint: _unknownValue(
                  _SettingField.radio,
                  suffix: '-spreading-factor',
                ),
                items: _spreadingFactorOptions.map((sf) {
                  return DropdownMenuItem(value: sf, child: Text('SF$sf'));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _spreadingFactor = value;
                    });
                    _markChanged(_SettingField.radio);
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey('coding-rate-${_codingRate ?? 'unknown'}'),
                initialValue: _codingRate,
                decoration: _settingDecoration(
                  field: _SettingField.radio,
                  labelText: l10n.repeater_codingRate,
                ),
                hint: _unknownValue(
                  _SettingField.radio,
                  suffix: '-coding-rate',
                ),
                items: _codingRateOptions.map((cr) {
                  return DropdownMenuItem(value: cr, child: Text('4/$cr'));
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _codingRate = value;
                    });
                    _markChanged(_SettingField.radio);
                  }
                },
              ),
              const SizedBox(height: 4),
              _buildFeatureToggleRow(
                field: _SettingField.rxGain,
                title: l10n.repeater_rxGain,
                subtitle: l10n.repeater_rxGainHelper,
                value: _rxGainBoosted,
                isRefreshing: _refreshingRxGain,
                onChanged: (v) {
                  setState(() => _rxGainBoosted = v);
                  _markChanged(_SettingField.rxGain);
                },
                onRefresh: _refreshRxGain,
                refreshTooltip: l10n.repeater_refreshRxGain,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationSettingsCard() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_locationSettings),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      decoration: _settingDecoration(
                        field: _SettingField.lat,
                        labelText: l10n.repeater_latitude,
                        helperText: l10n.repeater_latitudeHelper,
                        errorText: _latInvalid
                            ? l10n.settings_locationInvalid
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      onChanged: (value) {
                        _markChanged(_SettingField.lat);
                        final invalid = !_isValidCoordinate(value, 90);
                        if (invalid != _latInvalid) {
                          setState(() => _latInvalid = invalid);
                        }
                      },
                    ),
                  ),
                  _buildInlineRefreshButton(
                    isRefreshing: _refreshingLat,
                    onRefresh: _refreshLat,
                    tooltip: l10n.repeater_latitude,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lonController,
                      decoration: _settingDecoration(
                        field: _SettingField.lon,
                        labelText: l10n.repeater_longitude,
                        helperText: l10n.repeater_longitudeHelper,
                        errorText: _lonInvalid
                            ? l10n.settings_locationInvalid
                            : null,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      onChanged: (value) {
                        _markChanged(_SettingField.lon);
                        final invalid = !_isValidCoordinate(value, 180);
                        if (invalid != _lonInvalid) {
                          setState(() => _lonInvalid = invalid);
                        }
                      },
                    ),
                  ),
                  _buildInlineRefreshButton(
                    isRefreshing: _refreshingLon,
                    onRefresh: _refreshLon,
                    tooltip: l10n.repeater_longitude,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTogglesCard() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_features),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeatureToggleRow(
                field: _SettingField.repeat,
                title: l10n.repeater_packetForwarding,
                subtitle: l10n.repeater_packetForwardingSubtitle,
                value: _repeatEnabled,
                isRefreshing: _refreshingRepeat,
                onChanged: (value) {
                  setState(() {
                    _repeatEnabled = value;
                  });
                  _markChanged(_SettingField.repeat);
                },
                onRefresh: _refreshRepeat,
                refreshTooltip: l10n.repeater_refreshPacketForwarding,
              ),
              _buildFeatureToggleRow(
                field: _SettingField.allowReadOnly,
                title: l10n.repeater_guestAccess,
                subtitle: l10n.repeater_guestAccessSubtitle,
                value: _allowReadOnly,
                isRefreshing: _refreshingAllowReadOnly,
                onChanged: (value) {
                  setState(() {
                    _allowReadOnly = value;
                  });
                  _markChanged(_SettingField.allowReadOnly);
                },
                onRefresh: _refreshAllowReadOnly,
                refreshTooltip: l10n.repeater_refreshGuestAccess,
              ),
              _buildFeatureToggleRow(
                field: _SettingField.multiAcks,
                title: l10n.repeater_multiAcks,
                subtitle: l10n.repeater_multiAcksSubtitle,
                value: _multiAcks,
                isRefreshing: _refreshingMultiAcks,
                onChanged: (v) {
                  setState(() => _multiAcks = v);
                  _markChanged(_SettingField.multiAcks);
                },
                onRefresh: _refreshMultiAcks,
                refreshTooltip: l10n.repeater_refreshMultiAcks,
              ),
              SwitchListTile(
                title: Text(l10n.repeater_clockSyncAfterLogin),
                subtitle: Text(l10n.repeater_clockSyncAfterLoginSubtitle),
                value: _autoClockSyncAfterLogin,
                onChanged: (value) async {
                  setState(() {
                    _autoClockSyncAfterLogin = value;
                  });
                  await _storage.setRepeaterAutoClockSyncAfterLoginEnabled(
                    widget.repeater.publicKeyHex,
                    value,
                  );
                },
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureToggleRow({
    required _SettingField field,
    required String title,
    required String subtitle,
    required bool? value,
    required bool isRefreshing,
    required ValueChanged<bool> onChanged,
    required VoidCallback onRefresh,
    required String refreshTooltip,
  }) {
    return Row(
      children: [
        Expanded(
          child: value == null
              ? ListTile(
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: _unknownBooleanPicker(
                    field: field,
                    onSelected: onChanged,
                  ),
                  contentPadding: EdgeInsets.zero,
                )
              : SwitchListTile(
                  title: Text(title),
                  subtitle: Text(subtitle),
                  value: value,
                  onChanged: onChanged,
                  contentPadding: EdgeInsets.zero,
                ),
        ),
        IconButton(
          icon: isRefreshing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 20),
          onPressed: isRefreshing ? null : onRefresh,
          tooltip: refreshTooltip,
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildAdvertisementSettingsCard() {
    final l10n = context.l10n;
    final advertInterval = _advertInterval;
    final floodAdvertInterval = _floodAdvertInterval;
    final floodMax = _floodMax;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_advertisementSettings),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(l10n.repeater_localAdvertInterval),
                      subtitle: advertInterval == null
                          ? _unknownValue(_SettingField.advertInterval)
                          : Text(
                              l10n.repeater_localAdvertIntervalMinutes(
                                advertInterval,
                              ),
                            ),
                      trailing: advertInterval == null
                          ? _unknownBooleanPicker(
                              field: _SettingField.advertInterval,
                              onSelected: (enabled) {
                                setState(() {
                                  _advertInterval = enabled ? 60 : 0;
                                });
                                _markChanged(_SettingField.advertInterval);
                              },
                            )
                          : Switch(
                              value: advertInterval > 0,
                              onChanged: (value) {
                                setState(() {
                                  _advertInterval = value ? 60 : 0;
                                });
                                _markChanged(_SettingField.advertInterval);
                              },
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(
                    icon: _refreshingAdvertInterval
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                    onPressed: _refreshingAdvertInterval
                        ? null
                        : _refreshAdvertInterval,
                    tooltip: l10n.repeater_localAdvertInterval,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Slider(
                value: advertInterval == null || advertInterval == 0
                    ? 60.toDouble()
                    : advertInterval.toDouble(),
                min: 60,
                max: 240,
                divisions: 18,
                label: advertInterval == null
                    ? l10n.repeater_valueUnknown
                    : l10n.repeater_localAdvertIntervalMinutes(advertInterval),
                activeColor: advertInterval == null
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
                inactiveColor: advertInterval == null
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : null,
                onChanged: advertInterval == null || advertInterval > 0
                    ? (value) {
                        setState(() {
                          _advertInterval = value.toInt();
                        });
                        _markChanged(_SettingField.advertInterval);
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(l10n.repeater_floodAdvertInterval),
                      subtitle: floodAdvertInterval == null
                          ? _unknownValue(_SettingField.floodAdvertInterval)
                          : Text(
                              l10n.repeater_floodAdvertIntervalHours(
                                floodAdvertInterval,
                              ),
                            ),
                      trailing: floodAdvertInterval == null
                          ? _unknownBooleanPicker(
                              field: _SettingField.floodAdvertInterval,
                              onSelected: (enabled) {
                                setState(() {
                                  _floodAdvertInterval = enabled ? 3 : 0;
                                });
                                _markChanged(_SettingField.floodAdvertInterval);
                              },
                            )
                          : Switch(
                              value: floodAdvertInterval > 0,
                              onChanged: (value) {
                                setState(() {
                                  _floodAdvertInterval = value ? 3 : 0;
                                });
                                _markChanged(_SettingField.floodAdvertInterval);
                              },
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(
                    icon: _refreshingFloodAdvertInterval
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                    onPressed: _refreshingFloodAdvertInterval
                        ? null
                        : _refreshFloodAdvertInterval,
                    tooltip: l10n.repeater_floodAdvertInterval,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Slider(
                value: floodAdvertInterval == null || floodAdvertInterval == 0
                    ? 3.toDouble()
                    : floodAdvertInterval.toDouble(),
                min: 3,
                max: 168,
                divisions: 165,
                label: floodAdvertInterval == null
                    ? l10n.repeater_valueUnknown
                    : l10n.repeater_floodAdvertIntervalHours(
                        floodAdvertInterval,
                      ),
                activeColor: floodAdvertInterval == null
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
                inactiveColor: floodAdvertInterval == null
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : null,
                onChanged:
                    floodAdvertInterval == null || floodAdvertInterval > 0
                    ? (value) {
                        setState(() {
                          _floodAdvertInterval = value.toInt();
                        });
                        _markChanged(_SettingField.floodAdvertInterval);
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(l10n.repeater_floodMax),
                      subtitle: Text(l10n.repeater_floodMaxHelper),
                      trailing: floodMax == null
                          ? _unknownValue(_SettingField.floodMax)
                          : Text(
                              '$floodMax',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(
                    icon: _refreshingFloodMax
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                    onPressed: _refreshingFloodMax ? null : _refreshFloodMax,
                    tooltip: l10n.repeater_floodMax,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Slider(
                value: (floodMax ?? 0).toDouble(),
                min: 0,
                max: 64,
                divisions: 64,
                label: floodMax?.toString() ?? l10n.repeater_valueUnknown,
                activeColor: floodMax == null
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
                inactiveColor: floodMax == null
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : null,
                onChanged: (v) {
                  setState(() => _floodMax = v.toInt());
                  _markChanged(_SettingField.floodMax);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkHealthCard() {
    final l10n = context.l10n;
    final dutyCycle = _dutyCycle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_networkHealth),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('loop-detect-${_loopDetect ?? 'unknown'}'),
                      initialValue: _loopDetect,
                      decoration: _settingDecoration(
                        field: _SettingField.loopDetect,
                        labelText: l10n.repeater_loopDetect,
                        helperText: l10n.repeater_loopDetectHelper,
                        helperMaxLines: 3,
                      ),
                      hint: _unknownValue(_SettingField.loopDetect),
                      items: [
                        DropdownMenuItem(
                          value: 'off',
                          child: Text(l10n.repeater_loopDetectOff),
                        ),
                        DropdownMenuItem(
                          value: 'minimal',
                          child: Text(l10n.repeater_loopDetectMinimal),
                        ),
                        DropdownMenuItem(
                          value: 'moderate',
                          child: Text(l10n.repeater_loopDetectModerate),
                        ),
                        DropdownMenuItem(
                          value: 'strict',
                          child: Text(l10n.repeater_loopDetectStrict),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _loopDetect = v);
                          _markChanged(_SettingField.loopDetect);
                        }
                      },
                    ),
                  ),
                  _buildInlineRefreshButton(
                    isRefreshing: _refreshingLoopDetect,
                    onRefresh: _refreshLoopDetect,
                    tooltip: l10n.repeater_loopDetect,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: Text(l10n.repeater_dutyCycle),
                      subtitle: Text(l10n.repeater_dutyCycleHelper),
                      trailing: dutyCycle == null
                          ? _unknownValue(_SettingField.dutyCycle)
                          : Text(
                              l10n.repeater_dutyCyclePercent(dutyCycle),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(
                    icon: _refreshingDutyCycle
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 20),
                    onPressed: _refreshingDutyCycle ? null : _refreshDutyCycle,
                    tooltip: l10n.repeater_dutyCycle,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Slider(
                value: (dutyCycle ?? 1).toDouble(),
                min: 1,
                max: 100,
                divisions: 99,
                label: dutyCycle == null
                    ? l10n.repeater_valueUnknown
                    : l10n.repeater_dutyCyclePercent(dutyCycle),
                activeColor: dutyCycle == null
                    ? Theme.of(context).colorScheme.tertiary
                    : null,
                inactiveColor: dutyCycle == null
                    ? Theme.of(context).colorScheme.tertiaryContainer
                    : null,
                onChanged: (v) {
                  setState(() => _dutyCycle = v.toInt());
                  _markChanged(_SettingField.dutyCycle);
                },
              ),
              const SizedBox(height: 12),
              _buildPathHashModeField(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerInfoCard() {
    final l10n = context.l10n;
    final refreshButton = _refreshingOwnerInfo
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _refreshOwnerInfo,
            tooltip: l10n.repeater_refreshOwnerInfo,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_ownerInfo, trailing: refreshButton),
        MeshCard(
          child: TextField(
            controller: _ownerInfoController,
            decoration: _settingDecoration(
              field: _SettingField.ownerInfo,
              labelText: l10n.repeater_ownerInfo,
              helperText: l10n.repeater_ownerInfoHelper,
              helperMaxLines: 3,
            ),
            maxLines: 4,
            minLines: 2,
            onChanged: (_) => _markChanged(_SettingField.ownerInfo),
          ),
        ),
      ],
    );
  }

  Widget _buildPathHashModeField() {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<int>(
            key: ValueKey('path-hash-mode-${_pathHashMode ?? 'unknown'}'),
            initialValue: _pathHashMode,
            decoration: _settingDecoration(
              field: _SettingField.pathHashMode,
              labelText: l10n.repeater_pathHashMode,
              helperText: l10n.repeater_pathHashModeHelper,
              helperMaxLines: 5,
            ),
            hint: _unknownValue(_SettingField.pathHashMode),
            items: [
              for (var mode = 0; mode <= 2; mode++)
                DropdownMenuItem(
                  value: mode,
                  child: Text(l10n.repeater_pathHashModeOption(mode, mode + 1)),
                ),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _pathHashMode = v);
                _markChanged(_SettingField.pathHashMode);
              }
            },
          ),
        ),
        _buildInlineRefreshButton(
          isRefreshing: _refreshingPathHashMode,
          onRefresh: _refreshPathHashMode,
          tooltip: l10n.repeater_pathHashMode,
        ),
      ],
    );
  }

  Widget _buildActionsCard() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.repeater_actionsTitle),
        MeshCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.podcasts),
                title: Text(l10n.repeater_sendAdvert),
                subtitle: Text(l10n.repeater_sendAdvertSubtitle),
                enabled: !_runningAction,
                onTap: _runningAction
                    ? null
                    : () => _runAction('advert', l10n.repeater_sendAdvert),
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: const Icon(Icons.cell_tower),
                title: Text(l10n.repeater_sendAdvertZeroHop),
                subtitle: Text(l10n.repeater_sendAdvertZeroHopSubtitle),
                enabled: !_runningAction,
                onTap: _runningAction
                    ? null
                    : () => _runAction(
                        'advert.zerohop',
                        l10n.repeater_sendAdvertZeroHop,
                      ),
                contentPadding: EdgeInsets.zero,
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(l10n.repeater_clockSync),
                subtitle: Text(l10n.repeater_clockSyncSubtitle),
                enabled: !_runningAction,
                onTap: _runningAction
                    ? null
                    : () => _runAction('clock sync', l10n.repeater_clockSync),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedCard() {
    final l10n = context.l10n;
    final agcResetInterval = _agcResetInterval;
    return MeshCard(
      child: ExpansionTile(
        leading: const Icon(Icons.tune),
        title: Text(
          l10n.repeater_advancedSettings,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(l10n.repeater_advancedSettingsSubtitle),
        childrenPadding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _txDelayController,
                  decoration: _settingDecoration(
                    field: _SettingField.txDelay,
                    labelText: l10n.repeater_txDelay,
                    helperText: l10n.repeater_txDelayHelper,
                    helperMaxLines: 3,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markChanged(_SettingField.txDelay),
                ),
              ),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingTxDelay,
                onRefresh: _refreshTxDelay,
                tooltip: l10n.repeater_txDelay,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _directTxDelayController,
                  decoration: _settingDecoration(
                    field: _SettingField.directTxDelay,
                    labelText: l10n.repeater_directTxDelay,
                    helperText: l10n.repeater_directTxDelayHelper,
                    helperMaxLines: 3,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _markChanged(_SettingField.directTxDelay),
                ),
              ),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingDirectTxDelay,
                onRefresh: _refreshDirectTxDelay,
                tooltip: l10n.repeater_directTxDelay,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _intThreshController,
                  decoration: _settingDecoration(
                    field: _SettingField.intThresh,
                    labelText: l10n.repeater_intThresh,
                    helperText: l10n.repeater_intThreshHelper,
                    helperMaxLines: 3,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _markChanged(_SettingField.intThresh),
                ),
              ),
              _buildInlineRefreshButton(
                isRefreshing: _refreshingIntThresh,
                onRefresh: _refreshIntThresh,
                tooltip: l10n.repeater_intThresh,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFeatureToggleRow(
            field: _SettingField.channelActivityDetection,
            title: l10n.repeater_channelActivityDetection,
            subtitle: l10n.repeater_channelActivityDetectionHelper,
            value: _channelActivityDetectionEnabled,
            isRefreshing: _refreshingChannelActivityDetection,
            onChanged: (value) {
              setState(() => _channelActivityDetectionEnabled = value);
              _markChanged(_SettingField.channelActivityDetection);
            },
            onRefresh: _refreshChannelActivityDetection,
            refreshTooltip: l10n.repeater_channelActivityDetection,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ListTile(
                  title: Text(l10n.repeater_agcResetInterval),
                  subtitle: Text(l10n.repeater_agcResetIntervalHelper),
                  trailing: agcResetInterval == null
                      ? _unknownValue(_SettingField.agcResetInterval)
                      : Text(
                          '${agcResetInterval}s',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              IconButton(
                icon: _refreshingAgcResetInterval
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 20),
                onPressed: _refreshingAgcResetInterval
                    ? null
                    : _refreshAgcResetInterval,
                tooltip: l10n.repeater_agcResetInterval,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Slider(
            value: (agcResetInterval ?? 0).toDouble(),
            min: 0,
            max: 240,
            divisions: 60,
            label: agcResetInterval == null
                ? l10n.repeater_valueUnknown
                : '${agcResetInterval}s',
            activeColor: agcResetInterval == null
                ? Theme.of(context).colorScheme.tertiary
                : null,
            inactiveColor: agcResetInterval == null
                ? Theme.of(context).colorScheme.tertiaryContainer
                : null,
            onChanged: (v) {
              setState(() {
                // Clamp to multiple of 4 to match firmware semantics.
                _agcResetInterval = (v.toInt() ~/ 4) * 4;
              });
              _markChanged(_SettingField.agcResetInterval);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZoneCard() {
    final l10n = context.l10n;
    return MeshCard(
      color: MeshPalette.alertBg,
      borderColor: MeshPalette.alertLine,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: MeshPalette.alert),
              const SizedBox(width: 8),
              Text(
                l10n.repeater_dangerZone,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: MeshPalette.alert,
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: MeshPalette.alertLine),
          ListTile(
            leading: const Icon(Icons.refresh, color: MeshPalette.alert),
            title: Text(
              l10n.repeater_rebootRepeater,
              style: const TextStyle(color: MeshPalette.alert),
            ),
            subtitle: Text(
              l10n.repeater_rebootRepeaterSubtitle,
              style: const TextStyle(color: MeshPalette.warnDim),
            ),
            onTap: () => _confirmAction(
              l10n.repeater_rebootRepeater,
              l10n.repeater_rebootRepeaterConfirm,
              () => _sendDangerCommand('reboot'),
            ),
            contentPadding: EdgeInsets.zero,
          ),
          // Regenerate identity key - hidden until fully implemented
          ListTile(
            leading: const Icon(Icons.delete_forever, color: MeshPalette.alert),
            title: Text(
              l10n.repeater_eraseFileSystem,
              style: const TextStyle(color: MeshPalette.alert),
            ),
            subtitle: Text(
              l10n.repeater_eraseFileSystemSubtitle,
              style: const TextStyle(color: MeshPalette.warnDim),
            ),
            onTap: () => _confirmAction(
              l10n.repeater_eraseFileSystem,
              l10n.repeater_eraseFileSystemConfirm,
              () => _sendDangerCommand('erase'),
              isDestructive: true,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _sendDangerCommand(String command) async {
    final l10n = context.l10n;
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final repeater = _resolveRepeater(connector);

    if (command == 'erase') {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_eraseSerialOnly),
        );
      }
      return;
    }

    try {
      final selection = await connector.preparePathForContactSend(repeater);
      final timestampSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      connector.trackRepeaterAck(
        contact: repeater,
        selection: selection,
        text: command,
        timestampSeconds: timestampSeconds,
      );
      final frame = buildSendCliCommandFrame(
        repeater.publicKey,
        command,
        timestampSeconds: timestampSeconds,
      );
      await connector.sendFrame(frame);

      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_commandSent(command)),
        );
      }
    } catch (e) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(l10n.repeater_errorSendingCommand(e.toString())),
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    }
  }

  void _confirmAction(
    String title,
    String message,
    VoidCallback onConfirm, {
    bool isDestructive = false,
  }) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: isDestructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            child: Text(l10n.repeater_confirm),
          ),
        ],
      ),
    );
  }
}
