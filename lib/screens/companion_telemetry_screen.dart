import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/cayenne_lpp.dart';
import '../helpers/localized_time.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/mesh_ui.dart';

class CompanionTelemetryScreen extends StatefulWidget {
  const CompanionTelemetryScreen({super.key});

  @override
  State<CompanionTelemetryScreen> createState() =>
      _CompanionTelemetryScreenState();
}

class _CompanionTelemetryScreenState extends State<CompanionTelemetryScreen> {
  StreamSubscription<Uint8List>? _frameSubscription;
  Timer? _requestTimeout;
  List<Map<String, dynamic>>? _telemetry;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final connector = context.read<MeshCoreConnector>();
    _frameSubscription = connector.receivedFrames.listen(_handleFrame);
    unawaited(_loadTelemetry());
  }

  void _handleFrame(Uint8List frame) {
    if (frame.length < 8 || frame[0] != pushCodeTelemetryResponse) return;

    final connector = context.read<MeshCoreConnector>();
    final selfKey = connector.selfPublicKey;
    if (selfKey != null &&
        selfKey.length >= 6 &&
        !listEquals(frame.sublist(2, 8), selfKey.sublist(0, 6))) {
      return;
    }

    final parsed = CayenneLpp.parseByChannel(frame.sublist(8));
    _requestTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _telemetry = parsed;
      _isLoading = false;
      _error = null;
    });
  }

  Future<void> _loadTelemetry() async {
    final connector = context.read<MeshCoreConnector>();
    if (!connector.isConnected) {
      setState(() {
        _isLoading = false;
        _error = context.l10n.radioStats_notConnected;
      });
      return;
    }

    _requestTimeout?.cancel();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await connector.sendFrame(buildSendTelemetryReq(null));
      _requestTimeout = Timer(const Duration(seconds: 5), () {
        if (!mounted || !_isLoading) return;
        setState(() {
          _isLoading = false;
          _error = context.l10n.telemetry_requestTimeout;
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = context.l10n.telemetry_errorLoading(error.toString());
      });
    }
  }

  @override
  void dispose() {
    _requestTimeout?.cancel();
    _frameSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isImperial =
        context.watch<AppSettingsService>().settings.unitSystem ==
        UnitSystem.imperial;

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(l10n.companionTelemetry_title, subtitle: false),
        centerTitle: true,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: l10n.repeater_refresh,
            onPressed: _isLoading ? null : _loadTelemetry,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTelemetry,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else if (!_isLoading && (_telemetry == null || _telemetry!.isEmpty))
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.telemetry_noData,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final channel in _telemetry ?? const [])
              _buildChannelCard(channel, isImperial),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelCard(Map<String, dynamic> channel, bool isImperial) {
    final number = channel['channel'] as int;
    final values = channel['values'] as Map<String, dynamic>;
    final rows = [
      for (final value in values.entries)
        _formatValue(value.key, value.value, number, isImperial),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          context.l10n.telemetry_channelTitle(number),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        ),
        MeshCard(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FixedColumnWidth(8),
              2: FlexColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [for (final row in rows) _buildValueRow(row)],
          ),
        ),
      ],
    );
  }

  TableRow _buildValueRow(({String label, String value}) display) {
    final scheme = Theme.of(context).colorScheme;
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            display.label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox.shrink(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            display.value,
            textAlign: TextAlign.end,
            style: MeshTheme.mono(fontSize: 13, color: scheme.onSurface),
          ),
        ),
      ],
    );
  }

  ({String label, String value}) _formatValue(
    String key,
    dynamic value,
    int channel,
    bool isImperial,
  ) {
    final l10n = context.l10n;
    final text = _valueText(value);
    switch (key) {
      case 'digitalInput':
        return (label: l10n.telemetry_digitalInputLabel, value: text);
      case 'digitalOutput':
        return (label: l10n.telemetry_digitalOutputLabel, value: text);
      case 'analogInput':
        return (
          label: l10n.telemetry_analogInputLabel,
          value: l10n.telemetry_analogValue(text),
        );
      case 'analogOutput':
        return (
          label: l10n.telemetry_analogOutputLabel,
          value: l10n.telemetry_analogValue(text),
        );
      case 'generic':
        return (label: l10n.telemetry_genericLabel, value: text);
      case 'luminosity':
        return (
          label: l10n.telemetry_luminosityLabel,
          value: l10n.telemetry_luminosityValue(text),
        );
      case 'presence':
        return (label: l10n.telemetry_presenceLabel, value: text);
      case 'temperature':
        final celsius = value is num ? value.toDouble() : null;
        final temperature = celsius == null
            ? text
            : isImperial
            ? '${(celsius * 9 / 5 + 32).toStringAsFixed(1)}°F'
            : '${celsius.toStringAsFixed(1)}°C';
        return (
          label: channel == 1
              ? l10n.telemetry_mcuTemperatureLabel
              : l10n.telemetry_temperatureLabel,
          value: temperature,
        );
      case 'humidity':
        return (label: l10n.telemetry_humidityLabel, value: '$text%');
      case 'accelerometer':
        return (
          label: l10n.telemetry_accelerometerLabel,
          value: _axisText(value),
        );
      case 'pressure':
        return (
          label: l10n.telemetry_pressureLabel,
          value: l10n.telemetry_pressureValue(text),
        );
      case 'altitude':
        return (
          label: l10n.telemetry_altitudeLabel,
          value: l10n.telemetry_altitudeValue(text),
        );
      case 'voltage':
        return (
          label: channel == 1
              ? l10n.telemetry_batteryLabel
              : l10n.telemetry_voltageLabel,
          value: l10n.telemetry_voltageValue(text),
        );
      case 'current':
        return (
          label: l10n.telemetry_currentLabel,
          value: l10n.telemetry_currentValue(text),
        );
      case 'frequency':
        return (
          label: l10n.telemetry_frequencyLabel,
          value: l10n.telemetry_frequencyValue(text),
        );
      case 'percentage':
        return (
          label: l10n.telemetry_percentageLabel,
          value: l10n.telemetry_percentageValue(text),
        );
      case 'concentration':
        return (
          label: l10n.telemetry_concentrationLabel,
          value: l10n.telemetry_concentrationValue(text),
        );
      case 'power':
        return (
          label: l10n.telemetry_powerLabel,
          value: l10n.telemetry_powerValue(text),
        );
      case 'distance':
        return (
          label: l10n.telemetry_distanceLabel,
          value: l10n.telemetry_distanceValue(text),
        );
      case 'energy':
        return (
          label: l10n.telemetry_energyLabel,
          value: l10n.telemetry_energyValue(text),
        );
      case 'direction':
        return (
          label: l10n.telemetry_directionLabel,
          value: l10n.telemetry_directionValue(text),
        );
      case 'time':
        return (label: l10n.telemetry_timeLabel, value: _timeText(value));
      case 'gyrometer':
        return (label: l10n.telemetry_gyrometerLabel, value: _axisText(value));
      case 'colour':
        return (label: l10n.telemetry_colourLabel, value: _mapText(value));
      case 'gps':
        return (label: l10n.telemetry_gpsLabel, value: _gpsText(value));
      case 'switch':
        return (label: l10n.telemetry_switchLabel, value: text);
      case 'polyline':
        return (label: l10n.telemetry_polylineLabel, value: _mapText(value));
      default:
        return (label: key, value: text);
    }
  }

  String _valueText(dynamic value) {
    if (value == null) return context.l10n.common_notAvailable;
    if (value is double) {
      return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
    }
    return value.toString();
  }

  String _axisText(dynamic value) {
    if (value is! Map) return _valueText(value);
    return 'X: ${_valueText(value['x'])}, '
        'Y: ${_valueText(value['y'])}, Z: ${_valueText(value['z'])}';
  }

  String _mapText(dynamic value) {
    if (value is! Map) return _valueText(value);
    return value.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');
  }

  String _gpsText(dynamic value) {
    if (value is! Map) return _valueText(value);
    final latitude = value['latitude'];
    final longitude = value['longitude'];
    final altitude = value['altitude'];
    return [
      if (latitude is num) latitude.toStringAsFixed(5),
      if (longitude is num) longitude.toStringAsFixed(5),
      if (altitude is num) '${altitude.toStringAsFixed(1)} m',
    ].join(', ');
  }

  String _timeText(dynamic value) {
    if (value is! num || value <= 0) return _valueText(value);
    final dateTime = DateTime.fromMillisecondsSinceEpoch(
      value.toInt() * 1000,
      isUtc: true,
    ).toLocal();
    final date = formatLocalizedFullDate(context, dateTime);
    final time = formatLocalizedTime(context, dateTime);
    return '$date $time';
  }
}
