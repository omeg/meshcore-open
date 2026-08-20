import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../connector/meshcore_connector.dart';
import '../helpers/localized_time.dart';
import '../helpers/snack_bar_builder.dart';
import '../l10n/l10n.dart';
import '../models/app_settings.dart';
import '../models/translation_support.dart';
import '../services/app_settings_service.dart';
import '../services/influxdb_telemetry_service.dart';
import '../services/notification_service.dart';
import '../services/state_sync_service.dart';
import '../services/telemetry_saf_export.dart';
import '../services/translation_service.dart';
import '../storage/telemetry_log_store.dart';
import '../theme/mesh_theme.dart';
import '../utils/platform_info.dart';
import '../widgets/adaptive_app_bar_title.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/sync_progress_overlay.dart';
import 'map_cache_screen.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  final TelemetryLogStore _telemetryStore = TelemetryLogStore();
  final TelemetrySafExport _telemetrySaf = TelemetrySafExport();
  String? _telemetryStorageDir;

  @override
  void initState() {
    super.initState();
    if (PlatformInfo.isDesktop) {
      _telemetryStore.storageDirectoryPath().then((dir) {
        if (mounted) setState(() => _telemetryStorageDir = dir);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AdaptiveAppBarTitle(context.l10n.appSettings_title),
        centerTitle: true,
        bottom: const SyncProgressAppBarBottom(),
      ),
      body: SafeArea(
        top: false,
        child:
            Consumer4<
              AppSettingsService,
              MeshCoreConnector,
              TranslationService,
              StateSyncService
            >(
              builder:
                  (
                    context,
                    settingsService,
                    connector,
                    translationService,
                    stateSyncService,
                    child,
                  ) {
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                      children: [
                        // APPEARANCE
                        SectionHeader(context.l10n.appSettings_appearance),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildAppearanceContent(
                            context,
                            settingsService,
                          ),
                        ),

                        // NOTIFICATIONS
                        SectionHeader(context.l10n.appSettings_notifications),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildNotificationsContent(
                            context,
                            settingsService,
                          ),
                        ),

                        // MESSAGING
                        SectionHeader(context.l10n.appSettings_messaging),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildMessagingContent(
                            context,
                            settingsService,
                          ),
                        ),

                        // STATE SYNC
                        SectionHeader('Sync'),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildStateSyncContent(
                            context,
                            stateSyncService,
                            connector,
                          ),
                        ),

                        // TELEMETRY LOG
                        if (!kIsWeb) ...[
                          SectionHeader(context.l10n.telemetryLog_title),
                          MeshCard(
                            padding: EdgeInsets.zero,
                            child: _buildTelemetryLogContent(
                              context,
                              settingsService,
                            ),
                          ),
                        ],

                        // BATTERY
                        SectionHeader(context.l10n.appSettings_battery),
                        MeshCard(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: _buildBatteryContent(
                            context,
                            settingsService,
                            connector,
                          ),
                        ),

                        // MAP
                        SectionHeader(context.l10n.appSettings_mapDisplay),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildMapContent(context, settingsService),
                        ),

                        // TRANSLATION (non-web only)
                        if (!kIsWeb) ...[
                          SectionHeader(context.l10n.translation_title),
                          MeshCard(
                            padding: EdgeInsets.zero,
                            child: _buildTranslationContent(
                              context,
                              settingsService,
                              translationService,
                            ),
                          ),
                        ],

                        // CYR2LAT
                        SectionHeader(
                          context.l10n.channels_cyr2latSettingsHeading,
                        ),
                        MeshCard(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: _buildCyr2LatContent(context, settingsService),
                        ),

                        // DEBUG
                        SectionHeader(context.l10n.appSettings_debugCard),
                        MeshCard(
                          padding: EdgeInsets.zero,
                          child: _buildDebugContent(context, settingsService),
                        ),
                      ],
                    );
                  },
            ),
      ),
    );
  }

  Widget _buildTelemetryLogContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final influx = settingsService.settings.influxDb;
    return Column(
      children: [
        if (PlatformInfo.isAndroid) ...[
          Builder(
            builder: (context) {
              final folder = _telemetrySaf.rememberedFolderPath;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: const Icon(Icons.folder_outlined, size: 20),
                title: Text(context.l10n.telemetryLog_exportFolder),
                subtitle: Text(
                  folder ?? context.l10n.telemetryLog_exportFolderNotSet,
                ),
                trailing: TextButton(
                  onPressed: _changeTelemetryExportFolder,
                  child: Text(
                    folder == null
                        ? context.l10n.telemetryLog_choose
                        : context.l10n.telemetryLog_change,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1, indent: 16),
        ],
        if (PlatformInfo.isDesktop) ...[
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(context.l10n.telemetryLog_storageFolder),
            subtitle: _telemetryStorageDir == null
                ? const LinearProgressIndicator()
                : Text(
                    _telemetryStorageDir!,
                    style: const TextStyle(fontSize: 12),
                  ),
            trailing: _telemetryStorageDir == null
                ? null
                : TextButton(
                    onPressed: () =>
                        _openTelemetryStorageDir(_telemetryStorageDir!),
                    child: Text(context.l10n.telemetryLog_open),
                  ),
          ),
          const Divider(height: 1, indent: 16),
        ],
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: const Icon(Icons.storage_outlined, size: 20),
          title: const Text('InfluxDB'),
          subtitle: Text(
            influx.isConfigured
                ? '${influx.url} · ${influx.organization}/${influx.bucket}'
                : 'Not configured',
          ),
          trailing: const Icon(Icons.chevron_right, size: 16),
          onTap: () => _showInfluxDbSettings(context, settingsService),
        ),
      ],
    );
  }

  Future<void> _changeTelemetryExportFolder() async {
    final picked = await _telemetrySaf.pickDirectory();
    if (!mounted || picked == null) return;
    setState(() {});
    showDismissibleSnackBar(
      context,
      content: Text(
        context.l10n.telemetryLog_exportFolderSet(
          _telemetrySaf.rememberedFolderPath ?? '',
        ),
      ),
    );
  }

  Future<void> _openTelemetryStorageDir(String dir) async {
    await Clipboard.setData(ClipboardData(text: dir));
    try {
      await launchUrl(Uri.file(dir));
    } catch (_) {
      // Best effort: the path is on the clipboard regardless.
    }
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.telemetryLog_pathCopied(dir)),
    );
  }

  Future<void> _showInfluxDbSettings(
    BuildContext context,
    AppSettingsService settingsService,
  ) async {
    final updated = await showDialog<InfluxDbSettings>(
      context: context,
      builder: (context) =>
          _InfluxDbSettingsDialog(initial: settingsService.settings.influxDb),
    );
    if (updated == null) return;
    await settingsService.setInfluxDbSettings(updated);
    if (!context.mounted) return;
    showDismissibleSnackBar(
      context,
      content: const Text('InfluxDB settings saved'),
    );
  }

  Widget _buildAppearanceContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.brightness_6_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    context.l10n.appSettings_theme,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'system',
                    label: Text(context.l10n.appSettings_themeSystem),
                  ),
                  ButtonSegment(
                    value: 'light',
                    label: Text(context.l10n.appSettings_themeLight),
                  ),
                  ButtonSegment(
                    value: 'dark',
                    label: Text(context.l10n.appSettings_themeDark),
                  ),
                ],
                selected: {settingsService.settings.themeMode},
                onSelectionChanged: (selection) {
                  settingsService.setThemeMode(selection.first);
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showLanguageSheet(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.language_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_language,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _languageLabel(
                          context,
                          settingsService.settings.languageOverride,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showTimeFormatSheet(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_timeFormat,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _timeFormatLabel(
                          context,
                          settingsService.settings.timeFormatPreference,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (settingsService.settings.timeFormatPreference ==
            TimeFormatPreference.custom) ...[
          const Divider(height: 1, indent: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.edit_calendar_outlined, size: 20),
            title: Text(context.l10n.appSettings_customTimePattern),
            subtitle: Text(
              settingsService.settings.customTimePattern,
              style: MeshTheme.mono(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _showCustomTimePatternDialog(context, settingsService),
          ),
        ],
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showDateFormatSheet(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_dateFormat,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateFormatLabel(
                          context,
                          settingsService.settings.dateFormatPreference,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        if (settingsService.settings.dateFormatPreference ==
            DateFormatPreference.custom) ...[
          const Divider(height: 1, indent: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.edit_calendar_outlined, size: 20),
            title: Text(context.l10n.appSettings_customDatePattern),
            subtitle: Text(
              settingsService.settings.customDatePattern,
              style: MeshTheme.mono(fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _showCustomDatePatternDialog(context, settingsService),
          ),
        ],
      ],
    );
  }

  Widget _buildNotificationsContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final notifEnabled = settingsService.settings.notificationsEnabled;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.notifications_outlined, size: 20),
          title: Text(context.l10n.appSettings_enableNotifications),
          subtitle: Text(context.l10n.appSettings_enableNotificationsSubtitle),
          value: settingsService.settings.notificationsEnabled,
          onChanged: (value) async {
            if (value) {
              final granted = await NotificationService().requestPermissions();
              if (!granted) {
                if (context.mounted) {
                  showDismissibleSnackBar(
                    context,
                    content: Text(
                      context.l10n.appSettings_notificationPermissionDenied,
                    ),
                    duration: const Duration(seconds: 2),
                  );
                }
                return;
              }
            }
            await settingsService.setNotificationsEnabled(value);
            if (context.mounted) {
              showDismissibleSnackBar(
                context,
                content: Text(
                  value
                      ? context.l10n.appSettings_notificationsEnabled
                      : context.l10n.appSettings_notificationsDisabled,
                ),
                duration: const Duration(seconds: 2),
              );
            }
          },
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.message_outlined,
            size: 20,
            color: notifEnabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            context.l10n.appSettings_messageNotifications,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            context.l10n.appSettings_messageNotificationsSubtitle,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          value: settingsService.settings.notifyOnNewMessage,
          onChanged: notifEnabled
              ? (value) => settingsService.setNotifyOnNewMessage(value)
              : null,
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.forum_outlined,
            size: 20,
            color: notifEnabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            context.l10n.appSettings_channelMessageNotifications,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            context.l10n.appSettings_channelMessageNotificationsSubtitle,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          value: settingsService.settings.notifyOnNewChannelMessage,
          onChanged: notifEnabled
              ? (value) => settingsService.setNotifyOnNewChannelMessage(value)
              : null,
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.cell_tower,
            size: 20,
            color: notifEnabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            context.l10n.appSettings_advertisementNotifications,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            context.l10n.appSettings_advertisementNotificationsSubtitle,
            style: TextStyle(
              color: notifEnabled ? null : Theme.of(context).disabledColor,
            ),
          ),
          value: settingsService.settings.notifyOnNewAdvert,
          onChanged: notifEnabled
              ? (value) => settingsService.setNotifyOnNewAdvert(value)
              : null,
        ),
      ],
    );
  }

  Widget _buildMessagingContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final autoRouteEnabled = settingsService.settings.autoRouteRotationEnabled;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.refresh_outlined, size: 20),
          title: Text(context.l10n.appSettings_clearPathOnMaxRetry),
          subtitle: Text(context.l10n.appSettings_clearPathOnMaxRetrySubtitle),
          value: settingsService.settings.clearPathOnMaxRetry,
          onChanged: (value) {
            settingsService.setClearPathOnMaxRetry(value);
            showDismissibleSnackBar(
              context,
              content: Text(
                value
                    ? context.l10n.appSettings_pathsWillBeCleared
                    : context.l10n.appSettings_pathsWillNotBeCleared,
              ),
              duration: const Duration(seconds: 2),
            );
          },
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.vertical_align_top, size: 20),
          title: Text(context.l10n.appSettings_jumpToOldestUnread),
          subtitle: Text(context.l10n.appSettings_jumpToOldestUnreadSubtitle),
          value: settingsService.settings.jumpToOldestUnread,
          onChanged: settingsService.setJumpToOldestUnread,
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.alt_route, size: 20),
          title: Text(context.l10n.appSettings_autoRouteRotation),
          subtitle: Text(context.l10n.appSettings_autoRouteRotationSubtitle),
          value: autoRouteEnabled,
          onChanged: (value) {
            settingsService.setAutoRouteRotationEnabled(value);
            showDismissibleSnackBar(
              context,
              content: Text(
                value
                    ? context.l10n.appSettings_autoRouteRotationEnabled
                    : context.l10n.appSettings_autoRouteRotationDisabled,
              ),
              duration: const Duration(seconds: 2),
            );
          },
        ),
        // AnimatedSize sub-options for auto-route rotation
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topCenter,
          child: autoRouteEnabled
              ? Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      ListTile(
                        title: Text(context.l10n.appSettings_maxRouteWeight),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.appSettings_maxRouteWeightSubtitle,
                            ),
                            Slider(
                              value: settingsService.settings.maxRouteWeight,
                              min: 1,
                              max: 10,
                              divisions: 9,
                              label: settingsService.settings.maxRouteWeight
                                  .round()
                                  .toString(),
                              onChanged: (value) =>
                                  settingsService.setMaxRouteWeight(value),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          context.l10n.appSettings_initialRouteWeight,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context
                                  .l10n
                                  .appSettings_initialRouteWeightSubtitle,
                            ),
                            Slider(
                              value:
                                  settingsService.settings.initialRouteWeight,
                              min: 0.5,
                              max: 5.0,
                              divisions: 9,
                              label: settingsService.settings.initialRouteWeight
                                  .toStringAsFixed(1),
                              onChanged: (value) =>
                                  settingsService.setInitialRouteWeight(value),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          context.l10n.appSettings_routeWeightSuccessIncrement,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context
                                  .l10n
                                  .appSettings_routeWeightSuccessIncrementSubtitle,
                            ),
                            Slider(
                              value: settingsService
                                  .settings
                                  .routeWeightSuccessIncrement,
                              min: 0.1,
                              max: 2.0,
                              divisions: 19,
                              label: settingsService
                                  .settings
                                  .routeWeightSuccessIncrement
                                  .toStringAsFixed(1),
                              onChanged: (value) => settingsService
                                  .setRouteWeightSuccessIncrement(value),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          context.l10n.appSettings_routeWeightFailureDecrement,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context
                                  .l10n
                                  .appSettings_routeWeightFailureDecrementSubtitle,
                            ),
                            Slider(
                              value: settingsService
                                  .settings
                                  .routeWeightFailureDecrement,
                              min: 0.1,
                              max: 2.0,
                              divisions: 19,
                              label: settingsService
                                  .settings
                                  .routeWeightFailureDecrement
                                  .toStringAsFixed(1),
                              onChanged: (value) => settingsService
                                  .setRouteWeightFailureDecrement(value),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(context.l10n.appSettings_maxMessageRetries),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context
                                  .l10n
                                  .appSettings_maxMessageRetriesSubtitle,
                            ),
                            Slider(
                              value: settingsService.settings.maxMessageRetries
                                  .toDouble(),
                              min: 2,
                              max: 10,
                              divisions: 8,
                              label: settingsService.settings.maxMessageRetries
                                  .toString(),
                              onChanged: (value) => settingsService
                                  .setMaxMessageRetries(value.toInt()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.location_searching, size: 20),
          title: Text(context.l10n.appSettings_enableMessageTracing),
          subtitle: Text(context.l10n.appSettings_enableMessageTracingSubtitle),
          value: settingsService.settings.enableMessageTracing,
          onChanged: (value) {
            settingsService.setEnableMessageTracing(value);
          },
        ),
        const Divider(height: 1, indent: 16),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: const Icon(Icons.person_add_alt_1_outlined, size: 20),
          title: Text(context.l10n.appSettings_discoveredContactTapAction),
          subtitle: Text(
            settingsService.settings.discoveredContactTapAction ==
                    DiscoveredContactTapAction.importContact
                ? context
                      .l10n
                      .appSettings_discoveredContactTapActionImportSubtitle
                : context
                      .l10n
                      .appSettings_discoveredContactTapActionShowActionsSubtitle,
          ),
          trailing: DropdownButton<DiscoveredContactTapAction>(
            value: settingsService.settings.discoveredContactTapAction,
            underline: const SizedBox.shrink(),
            onChanged: (value) {
              if (value != null) {
                settingsService.setDiscoveredContactTapAction(value);
              }
            },
            items: [
              DropdownMenuItem(
                value: DiscoveredContactTapAction.importContact,
                child: Text(
                  context.l10n.appSettings_discoveredContactTapActionImport,
                ),
              ),
              DropdownMenuItem(
                value: DiscoveredContactTapAction.showActions,
                child: Text(
                  context
                      .l10n
                      .appSettings_discoveredContactTapActionShowActions,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStateSyncContent(
    BuildContext context,
    StateSyncService stateSyncService,
    MeshCoreConnector connector,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final supported = stateSyncService.isSupported;
    final folder = stateSyncService.folderPath;
    final canEnable = supported && stateSyncService.hasFolder;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.sync_outlined,
            size: 20,
            color: supported ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            'Automatic state sync',
            style: TextStyle(
              color: supported ? null : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            supported
                ? (folder ?? 'Choose a sync folder to enable handoff.')
                : 'Automatic folder sync is available on Android and desktop.',
            style: TextStyle(
              color: supported ? null : Theme.of(context).disabledColor,
            ),
          ),
          value: stateSyncService.isEnabled,
          onChanged: canEnable
              ? (value) async {
                  await stateSyncService.setEnabled(value);
                  if (value) {
                    await connector.importStateSyncNow();
                    connector.scheduleStateSyncExport();
                  }
                }
              : null,
        ),
        const Divider(height: 1, indent: 16),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          enabled: supported,
          leading: const Icon(Icons.folder_outlined, size: 20),
          title: Text(folder == null ? 'Choose sync folder' : 'Sync folder'),
          subtitle: Text(folder ?? 'No folder selected'),
          trailing: Icon(
            Icons.chevron_right,
            color: supported ? scheme.onSurfaceVariant : null,
            size: 16,
          ),
          onTap: supported
              ? () async {
                  final picked = await stateSyncService.pickFolder();
                  if (!context.mounted) return;
                  if (picked) {
                    await connector.importStateSyncNow();
                    connector.scheduleStateSyncExport();
                    if (!context.mounted) return;
                    showDismissibleSnackBar(
                      context,
                      content: Text(
                        'Sync folder set to ${stateSyncService.folderPath ?? 'folder'}',
                      ),
                      duration: const Duration(seconds: 2),
                    );
                  }
                }
              : null,
        ),
        if (stateSyncService.hasFolder) ...[
          const Divider(height: 1, indent: 16),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: const Icon(Icons.folder_off_outlined, size: 20),
            title: const Text('Forget sync folder'),
            subtitle: Text(
              PlatformInfo.isAndroid
                  ? 'Keeps files in the folder and disables automatic sync.'
                  : 'Keeps files on disk and disables automatic sync.',
            ),
            onTap: () async {
              await stateSyncService.clearFolder();
              if (!context.mounted) return;
              showDismissibleSnackBar(
                context,
                content: const Text('Automatic state sync disabled'),
                duration: const Duration(seconds: 2),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildBatteryContent(
    BuildContext context,
    AppSettingsService settingsService,
    MeshCoreConnector connector,
  ) {
    final deviceId = connector.batteryDeviceKey;
    final isConnected = connector.isConnected && deviceId != null;
    final selection = isConnected
        ? settingsService.batteryChemistryForDevice(deviceId)
        : 'nmc';
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.battery_full,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.appSettings_batteryChemistry,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isConnected
                          ? context.l10n.appSettings_batteryChemistryPerDevice(
                              connector.deviceDisplayName,
                            )
                          : context
                                .l10n
                                .appSettings_batteryChemistryConnectFirst,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: selection,
          isExpanded: true,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            isDense: true,
          ),
          onChanged: isConnected
              ? (value) {
                  if (value != null) {
                    settingsService.setBatteryChemistryForDevice(
                      deviceId,
                      value,
                    );
                  }
                }
              : null,
          items: [
            DropdownMenuItem(
              value: 'nmc',
              child: Text(context.l10n.appSettings_batteryNmc),
            ),
            DropdownMenuItem(
              value: 'lifepo4',
              child: Text(context.l10n.appSettings_batteryLifepo4),
            ),
            DropdownMenuItem(
              value: 'lipo',
              child: Text(context.l10n.appSettings_batteryLipo),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMapContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.router_outlined, size: 20),
          title: Text(context.l10n.appSettings_showRepeaters),
          subtitle: Text(context.l10n.appSettings_showRepeatersSubtitle),
          value: settingsService.settings.mapShowRepeaters,
          onChanged: (value) => settingsService.setMapShowRepeaters(value),
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.chat_outlined, size: 20),
          title: Text(context.l10n.appSettings_showChatNodes),
          subtitle: Text(context.l10n.appSettings_showChatNodesSubtitle),
          value: settingsService.settings.mapShowChatNodes,
          onChanged: (value) => settingsService.setMapShowChatNodes(value),
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.people_outline, size: 20),
          title: Text(context.l10n.appSettings_showOtherNodes),
          subtitle: Text(context.l10n.appSettings_showOtherNodesSubtitle),
          value: settingsService.settings.mapShowOtherNodes,
          onChanged: (value) => settingsService.setMapShowOtherNodes(value),
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showTimeFilterSheet(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.timer_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_timeFilter,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settingsService.settings.mapTimeFilterHours == 0
                            ? context.l10n.appSettings_timeFilterShowAll
                            : context.l10n.appSettings_timeFilterShowLast(
                                settingsService.settings.mapTimeFilterHours
                                    .toInt(),
                              ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showUnitsSheet(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.straighten,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_unitsTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settingsService.settings.unitSystem ==
                                UnitSystem.imperial
                            ? context.l10n.appSettings_unitsImperial
                            : context.l10n.appSettings_unitsMetric,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const MapCacheScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.download_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.appSettings_offlineMapCache,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settingsService.settings.mapCacheBounds == null
                            ? context.l10n.appSettings_noAreaSelected
                            : context.l10n.appSettings_areaSelectedZoom(
                                settingsService.settings.mapCacheMinZoom,
                                settingsService.settings.mapCacheMaxZoom,
                              ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranslationContent(
    BuildContext context,
    AppSettingsService settingsService,
    TranslationService translationService,
  ) {
    final settings = settingsService.settings;
    final translationEnabled = settings.translationEnabled;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: const Icon(Icons.translate, size: 20),
          title: Text(context.l10n.translation_enableTitle),
          subtitle: Text(context.l10n.translation_enableSubtitle),
          value: settings.translationEnabled,
          onChanged: settingsService.setTranslationEnabled,
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.auto_awesome_outlined,
            size: 20,
            color: translationEnabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            context.l10n.translation_autoIncomingTitle,
            style: TextStyle(
              color: translationEnabled
                  ? null
                  : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            context.l10n.translation_autoIncomingSubtitle,
            style: TextStyle(
              color: translationEnabled
                  ? null
                  : Theme.of(context).disabledColor,
            ),
          ),
          value: settings.autoTranslateIncomingMessages,
          onChanged: translationEnabled
              ? settingsService.setAutoTranslateIncomingMessages
              : null,
        ),
        const Divider(height: 1, indent: 16),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          secondary: Icon(
            Icons.outgoing_mail,
            size: 20,
            color: translationEnabled ? null : Theme.of(context).disabledColor,
          ),
          title: Text(
            context.l10n.translation_composerTitle,
            style: TextStyle(
              color: translationEnabled
                  ? null
                  : Theme.of(context).disabledColor,
            ),
          ),
          subtitle: Text(
            context.l10n.translation_composerSubtitle,
            style: TextStyle(
              color: translationEnabled
                  ? null
                  : Theme.of(context).disabledColor,
            ),
          ),
          value: settings.composerTranslationEnabled,
          onChanged: translationEnabled
              ? settingsService.setComposerTranslationEnabled
              : null,
        ),
        const Divider(height: 1, indent: 16),
        InkWell(
          onTap: () => _showTranslationLanguageDialog(context, settingsService),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.language, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.translation_targetLanguage,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _translationLanguageLabel(
                          context,
                          settings.translationTargetLanguageCode,
                        ),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: scheme.onSurfaceVariant,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, indent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: settings.translationSelectedModelId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.translation_downloadedModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final model in settings.translationDownloadedModels)
                DropdownMenuItem(
                  value: model.id,
                  child: Text(translationModelFriendlyName(model)),
                ),
            ],
            onChanged: settings.translationDownloadedModels.isEmpty
                ? null
                : (value) {
                    settingsService.setTranslationSelectedModelId(value);
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: DropdownButtonFormField<String>(
            initialValue: null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.l10n.translation_presetModelLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final preset in translationPresetModels)
                DropdownMenuItem(
                  value: preset.sourceUrl,
                  child: Text(translationModelFriendlyName(preset)),
                ),
            ],
            onChanged: translationService.isBusy
                ? null
                : (value) async {
                    if (value == null) return;
                    final preset = translationPresetModels.firstWhere(
                      (entry) => entry.sourceUrl == value,
                    );
                    await _downloadTranslationModel(
                      context,
                      translationService,
                      settingsService,
                      sourceUrl: preset.sourceUrl,
                      fileName: preset.name,
                      id: preset.id,
                    );
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TranslationUrlField(
                initialValue: settings.translationModelSourceUrl ?? '',
                onChanged: settingsService.setTranslationModelSourceUrl,
                onDownload: translationService.isBusy
                    ? null
                    : (url) => _downloadTranslationModel(
                        context,
                        translationService,
                        settingsService,
                        sourceUrl: url,
                      ),
                downloadLabel: translationService.isDownloading
                    ? context.l10n.translation_downloading
                    : translationService.isBusy
                    ? context.l10n.translation_working
                    : context.l10n.translation_downloadModel,
                isDownloading: translationService.isDownloading,
                onCancel: translationService.cancelDownload,
                labelText: context.l10n.translation_manualUrlLabel,
                stopLabel: context.l10n.translation_stop,
              ),
              if (translationService.isDownloading) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value:
                        translationService.downloadFileName ==
                            'Merging chunks...'
                        ? null
                        : translationService.downloadProgress,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _downloadProgressLabel(context, translationService),
                    style: MeshTheme.mono(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              if (settings.translationDownloadedModels.isNotEmpty) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.l10n.translation_downloadedModels,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                for (final model in settings.translationDownloadedModels)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          model.id == settings.translationSelectedModelId
                              ? Icons.check_circle
                              : Icons.memory_outlined,
                          size: 20,
                          color: model.id == settings.translationSelectedModelId
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(MeshRadii.xs),
                            onTap: () => settingsService
                                .setTranslationSelectedModelId(model.id),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  translationModelFriendlyName(model),
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _downloadedModelLabel(model),
                                  style: MeshTheme.mono(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.l10n.translation_deleteModel,
                          onPressed: translationService.isBusy
                              ? null
                              : () => _deleteTranslationModel(
                                  context,
                                  translationService,
                                  model,
                                ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
              ],
              if (translationService.lastError != null) ...[
                const SizedBox(height: 8),
                Text(
                  translationService.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCyr2LatContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final selectedProfile = settingsService.getSelectedCyr2LatProfile();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: settingsService.settings.selectedCyr2latProfileId,
          decoration: InputDecoration(
            labelText: context.l10n.channels_cyr2latSettingsSubheading,
            border: const OutlineInputBorder(),
          ),
          items: settingsService.settings.cyr2latProfiles.map((profile) {
            return DropdownMenuItem(
              value: profile.id,
              child: Text(profile.name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              settingsService.setSelectedCyr2LatProfile(value);
            }
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _showAddCyr2LatProfileDialog(context, settingsService),
                icon: const Icon(Icons.add),
                label: Text(context.l10n.common_add),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showEditCyr2LatProfileDialog(
                  context,
                  settingsService,
                  selectedProfile,
                ),
                icon: const Icon(Icons.edit),
                label: Text(context.l10n.common_edit),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: settingsService.settings.cyr2latProfiles.length > 1
                    ? () => _showDeleteCyr2LatProfileDialog(
                        context,
                        settingsService,
                        selectedProfile,
                      )
                    : null,
                icon: const Icon(Icons.delete),
                label: Text(context.l10n.common_delete),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDebugContent(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: const Icon(Icons.bug_report_outlined, size: 20),
      title: Text(context.l10n.appSettings_appDebugLogging),
      subtitle: Text(context.l10n.appSettings_appDebugLoggingSubtitle),
      value: settingsService.settings.appDebugLogEnabled,
      onChanged: (value) async {
        await settingsService.setAppDebugLogEnabled(value);
        if (!context.mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(
            value
                ? context.l10n.appSettings_appDebugLoggingEnabled
                : context.l10n.appSettings_appDebugLoggingDisabled,
          ),
          duration: const Duration(seconds: 2),
        );
      },
    );
  }

  String _languageLabel(BuildContext context, String? languageCode) {
    switch (languageCode) {
      case 'en':
        return context.l10n.appSettings_languageEn;
      case 'fr':
        return context.l10n.appSettings_languageFr;
      case 'es':
        return context.l10n.appSettings_languageEs;
      case 'de':
        return context.l10n.appSettings_languageDe;
      case 'pl':
        return context.l10n.appSettings_languagePl;
      case 'sl':
        return context.l10n.appSettings_languageSl;
      case 'pt':
        return context.l10n.appSettings_languagePt;
      case 'it':
        return context.l10n.appSettings_languageIt;
      case 'zh':
        return context.l10n.appSettings_languageZh;
      case 'sv':
        return context.l10n.appSettings_languageSv;
      case 'nl':
        return context.l10n.appSettings_languageNl;
      case 'sk':
        return context.l10n.appSettings_languageSk;
      case 'bg':
        return context.l10n.appSettings_languageBg;
      case 'ru':
        return context.l10n.appSettings_languageRu;
      case 'uk':
        return context.l10n.appSettings_languageUk;
      case 'hu':
        return context.l10n.appSettings_languageHu;
      case 'ja':
        return context.l10n.appSettings_languageJa;
      case 'ko':
        return context.l10n.appSettings_languageKo;
      default:
        return context.l10n.appSettings_languageSystem;
    }
  }

  String _timeFormatLabel(
    BuildContext context,
    TimeFormatPreference preference,
  ) {
    switch (preference) {
      case TimeFormatPreference.system:
        return context.l10n.appSettings_timeFormatSystem;
      case TimeFormatPreference.twelveHour:
        return context.l10n.appSettings_timeFormat12Hour;
      case TimeFormatPreference.twentyFourHour:
        return context.l10n.appSettings_timeFormat24Hour;
      case TimeFormatPreference.custom:
        return context.l10n.appSettings_timeFormatCustom;
    }
  }

  void _showTimeFormatSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: context.l10n.appSettings_timeFormat),
          for (final preference in TimeFormatPreference.values)
            _sheetOption<TimeFormatPreference>(
              ctx,
              label: _timeFormatLabel(context, preference),
              value: preference,
              selected:
                  settingsService.settings.timeFormatPreference == preference,
              onTap: () {
                settingsService.setTimeFormatPreference(preference);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showCustomTimePatternDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) async {
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => _CustomTimePatternDialog(
        initialPattern: settingsService.settings.customTimePattern,
      ),
    );
    if (pattern == null) return;
    await settingsService.setCustomTimePattern(pattern);
    await settingsService.setTimeFormatPreference(TimeFormatPreference.custom);
  }

  String _dateFormatLabel(
    BuildContext context,
    DateFormatPreference preference,
  ) {
    switch (preference) {
      case DateFormatPreference.system:
        return context.l10n.appSettings_timeFormatSystem;
      case DateFormatPreference.dayMonthYear:
        return context.l10n.appSettings_dateFormatDayMonthYear;
      case DateFormatPreference.monthDayYear:
        return context.l10n.appSettings_dateFormatMonthDayYear;
      case DateFormatPreference.yearMonthDay:
        return context.l10n.appSettings_dateFormatYearMonthDay;
      case DateFormatPreference.custom:
        return context.l10n.appSettings_timeFormatCustom;
    }
  }

  void _showDateFormatSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: context.l10n.appSettings_dateFormat),
          for (final preference in DateFormatPreference.values)
            _sheetOption<DateFormatPreference>(
              ctx,
              label: _dateFormatLabel(context, preference),
              value: preference,
              selected:
                  settingsService.settings.dateFormatPreference == preference,
              onTap: () {
                settingsService.setDateFormatPreference(preference);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _showCustomDatePatternDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) async {
    final pattern = await showDialog<String>(
      context: context,
      builder: (context) => _CustomDatePatternDialog(
        initialPattern: settingsService.settings.customDatePattern,
      ),
    );
    if (pattern == null) return;
    await settingsService.setCustomDatePattern(pattern);
    await settingsService.setDateFormatPreference(DateFormatPreference.custom);
  }

  void _showLanguageSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: context.l10n.appSettings_language),
          SizedBox(
            height: 400,
            child: ListView(
              children: [
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageSystem,
                  value: null,
                  selected: settingsService.settings.languageOverride == null,
                  onTap: () {
                    settingsService.setLanguageOverride(null);
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageEn,
                  value: 'en',
                  selected: settingsService.settings.languageOverride == 'en',
                  onTap: () {
                    settingsService.setLanguageOverride('en');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageFr,
                  value: 'fr',
                  selected: settingsService.settings.languageOverride == 'fr',
                  onTap: () {
                    settingsService.setLanguageOverride('fr');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageEs,
                  value: 'es',
                  selected: settingsService.settings.languageOverride == 'es',
                  onTap: () {
                    settingsService.setLanguageOverride('es');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageDe,
                  value: 'de',
                  selected: settingsService.settings.languageOverride == 'de',
                  onTap: () {
                    settingsService.setLanguageOverride('de');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languagePl,
                  value: 'pl',
                  selected: settingsService.settings.languageOverride == 'pl',
                  onTap: () {
                    settingsService.setLanguageOverride('pl');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageSl,
                  value: 'sl',
                  selected: settingsService.settings.languageOverride == 'sl',
                  onTap: () {
                    settingsService.setLanguageOverride('sl');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languagePt,
                  value: 'pt',
                  selected: settingsService.settings.languageOverride == 'pt',
                  onTap: () {
                    settingsService.setLanguageOverride('pt');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageIt,
                  value: 'it',
                  selected: settingsService.settings.languageOverride == 'it',
                  onTap: () {
                    settingsService.setLanguageOverride('it');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageZh,
                  value: 'zh',
                  selected: settingsService.settings.languageOverride == 'zh',
                  onTap: () {
                    settingsService.setLanguageOverride('zh');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageSv,
                  value: 'sv',
                  selected: settingsService.settings.languageOverride == 'sv',
                  onTap: () {
                    settingsService.setLanguageOverride('sv');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageNl,
                  value: 'nl',
                  selected: settingsService.settings.languageOverride == 'nl',
                  onTap: () {
                    settingsService.setLanguageOverride('nl');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageSk,
                  value: 'sk',
                  selected: settingsService.settings.languageOverride == 'sk',
                  onTap: () {
                    settingsService.setLanguageOverride('sk');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageBg,
                  value: 'bg',
                  selected: settingsService.settings.languageOverride == 'bg',
                  onTap: () {
                    settingsService.setLanguageOverride('bg');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageRu,
                  value: 'ru',
                  selected: settingsService.settings.languageOverride == 'ru',
                  onTap: () {
                    settingsService.setLanguageOverride('ru');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageUk,
                  value: 'uk',
                  selected: settingsService.settings.languageOverride == 'uk',
                  onTap: () {
                    settingsService.setLanguageOverride('uk');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageHu,
                  value: 'hu',
                  selected: settingsService.settings.languageOverride == 'hu',
                  onTap: () {
                    settingsService.setLanguageOverride('hu');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageJa,
                  value: 'ja',
                  selected: settingsService.settings.languageOverride == 'ja',
                  onTap: () {
                    settingsService.setLanguageOverride('ja');
                    Navigator.pop(ctx);
                  },
                ),
                _sheetOption<String?>(
                  ctx,
                  label: context.l10n.appSettings_languageKo,
                  value: 'ko',
                  selected: settingsService.settings.languageOverride == 'ko',
                  onTap: () {
                    settingsService.setLanguageOverride('ko');
                    Navigator.pop(ctx);
                  },
                ),
                SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showTimeFilterSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: context.l10n.appSettings_mapTimeFilter),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(context.l10n.appSettings_showNodesDiscoveredWithin),
          ),
          _sheetOption<double>(
            ctx,
            label: context.l10n.appSettings_allTime,
            value: 0,
            selected: settingsService.settings.mapTimeFilterHours == 0,
            onTap: () {
              settingsService.setMapTimeFilterHours(0);
              Navigator.pop(ctx);
            },
          ),
          _sheetOption<double>(
            ctx,
            label: context.l10n.appSettings_lastHour,
            value: 1,
            selected: settingsService.settings.mapTimeFilterHours == 1,
            onTap: () {
              settingsService.setMapTimeFilterHours(1);
              Navigator.pop(ctx);
            },
          ),
          _sheetOption<double>(
            ctx,
            label: context.l10n.appSettings_last6Hours,
            value: 6,
            selected: settingsService.settings.mapTimeFilterHours == 6,
            onTap: () {
              settingsService.setMapTimeFilterHours(6);
              Navigator.pop(ctx);
            },
          ),
          _sheetOption<double>(
            ctx,
            label: context.l10n.appSettings_last24Hours,
            value: 24,
            selected: settingsService.settings.mapTimeFilterHours == 24,
            onTap: () {
              settingsService.setMapTimeFilterHours(24);
              Navigator.pop(ctx);
            },
          ),
          _sheetOption<double>(
            ctx,
            label: context.l10n.appSettings_lastWeek,
            value: 168,
            selected: settingsService.settings.mapTimeFilterHours == 168,
            onTap: () {
              settingsService.setMapTimeFilterHours(168);
              Navigator.pop(ctx);
            },
          ),
          SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8),
        ],
      ),
    );
  }

  void _showUnitsSheet(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showMeshSheet(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BottomSheetHeader(title: context.l10n.appSettings_unitsTitle),
          _sheetOption<UnitSystem>(
            ctx,
            label: context.l10n.appSettings_unitsMetric,
            value: UnitSystem.metric,
            selected: settingsService.settings.unitSystem == UnitSystem.metric,
            onTap: () {
              settingsService.setUnitSystem(UnitSystem.metric);
              Navigator.pop(ctx);
            },
          ),
          _sheetOption<UnitSystem>(
            ctx,
            label: context.l10n.appSettings_unitsImperial,
            value: UnitSystem.imperial,
            selected:
                settingsService.settings.unitSystem == UnitSystem.imperial,
            onTap: () {
              settingsService.setUnitSystem(UnitSystem.imperial);
              Navigator.pop(ctx);
            },
          ),
          SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8),
        ],
      ),
    );
  }

  Widget _sheetOption<T>(
    BuildContext context, {
    required String label,
    required T value,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }

  void _showTranslationLanguageDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    showDialog(
      context: context,
      builder: (context) => _TranslationLanguageDialogContent(
        currentLanguageCode:
            settingsService.settings.translationTargetLanguageCode,
        onLanguageSelected: (value) {
          settingsService.setTranslationTargetLanguageCode(value);
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _downloadTranslationModel(
    BuildContext context,
    TranslationService translationService,
    AppSettingsService settingsService, {
    required String sourceUrl,
    String? fileName,
    String? id,
  }) async {
    if (sourceUrl.isEmpty) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.translation_enterUrlFirst),
      );
      return;
    }
    try {
      await translationService.downloadModel(
        sourceUrl: sourceUrl,
        fileName: fileName,
        id: id,
      );
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.translation_modelDownloaded),
      );
      await settingsService.setTranslationEnabled(true);
    } on TranslationDownloadCancelled {
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.translation_downloadStopped),
      );
    } catch (error) {
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.translation_downloadFailed(error.toString()),
        ),
      );
    }
  }

  String _translationLanguageLabel(BuildContext context, String? languageCode) {
    if (languageCode == null || languageCode.isEmpty) {
      return context.l10n.translation_useAppLanguage;
    }
    for (final option in supportedTranslationLanguages) {
      if (option.code == languageCode) {
        return option.label;
      }
    }
    return languageCode.toUpperCase();
  }

  String _downloadProgressLabel(
    BuildContext context,
    TranslationService translationService,
  ) {
    final fileName = translationService.downloadFileName ?? 'Model';
    if (fileName == 'Merging chunks...') {
      return context.l10n.translation_mergingChunks;
    }
    final currentMb = translationService.downloadedBytes / (1024 * 1024);
    final totalBytes = translationService.downloadTotalBytes;
    if (totalBytes == null || totalBytes <= 0) {
      return '$fileName: ${currentMb.toStringAsFixed(1)} MB';
    }
    final totalMb = totalBytes / (1024 * 1024);
    final percent = ((translationService.downloadProgress ?? 0) * 100)
        .toStringAsFixed(0);
    return '$fileName: ${currentMb.toStringAsFixed(1)} / ${totalMb.toStringAsFixed(1)} MB ($percent%)';
  }

  Future<void> _deleteTranslationModel(
    BuildContext context,
    TranslationService translationService,
    TranslationModelRecord model,
  ) async {
    try {
      await translationService.removeModel(model);
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.appSettings_translationModelDeleted(
            translationModelFriendlyName(model),
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(
          context.l10n.appSettings_translationModelDeleteFailed('$error'),
        ),
      );
    }
  }

  String _downloadedModelLabel(TranslationModelRecord model) {
    final sizeMb = model.fileSizeBytes / (1024 * 1024);
    final source = model.sourceUrl.isEmpty ? model.name : model.sourceUrl;
    return '${sizeMb.toStringAsFixed(1)} MB • $source';
  }

  void _showAddCyr2LatProfileDialog(
    BuildContext context,
    AppSettingsService settingsService,
  ) {
    final nameController = TextEditingController();
    final jsonController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(defaultCyr2LatCharMap),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settings_cyr2latProfileAdd),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.settings_cyr2latProfileName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: jsonController,
                maxLines: 15,
                decoration: InputDecoration(
                  labelText: context.l10n.channels_cyr2latSettingsDialogHint,
                  border: const OutlineInputBorder(),
                  hintText: context.l10n.channels_cyr2latSettingsDscr,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.settings_cyr2latProfileNameEmpty),
                );
                return;
              }
              try {
                final json =
                    jsonDecode(jsonController.text) as Map<String, dynamic>;
                final map = json.map(
                  (key, value) => MapEntry(key, value.toString()),
                );
                final profile = Cyr2LatProfile(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text,
                  charMap: map,
                );
                await settingsService.addCyr2LatProfile(profile);
                if (!context.mounted) return;
                Navigator.pop(context);
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.settings_cyr2latProfileAdded),
                );
              } catch (e) {
                showDismissibleSnackBar(
                  context,
                  content: Text(
                    context.l10n.channels_cyr2latSettingsDialogWrongJSON(
                      e.toString(),
                    ),
                  ),
                );
              }
            },
            child: Text(context.l10n.common_save),
          ),
        ],
      ),
    );
  }

  void _showEditCyr2LatProfileDialog(
    BuildContext context,
    AppSettingsService settingsService,
    Cyr2LatProfile profile,
  ) {
    final nameController = TextEditingController(text: profile.name);
    final jsonController = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(profile.charMap),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settings_cyr2latProfileEdit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.settings_cyr2latProfileName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: jsonController,
                maxLines: 15,
                decoration: InputDecoration(
                  labelText: context.l10n.channels_cyr2latSettingsDialogHint,
                  border: const OutlineInputBorder(),
                  hintText: context.l10n.channels_cyr2latSettingsDscr,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.settings_cyr2latProfileNameEmpty),
                );
                return;
              }
              try {
                final json =
                    jsonDecode(jsonController.text) as Map<String, dynamic>;
                final map = json.map(
                  (key, value) => MapEntry(key, value.toString()),
                );
                final updatedProfile = profile.copyWith(
                  name: nameController.text,
                  charMap: map,
                );
                await settingsService.updateCyr2LatProfile(updatedProfile);
                if (!context.mounted) return;
                Navigator.pop(context);
                showDismissibleSnackBar(
                  context,
                  content: Text(context.l10n.settings_cyr2latProfileUpdated),
                );
              } catch (e) {
                showDismissibleSnackBar(
                  context,
                  content: Text(
                    context.l10n.channels_cyr2latSettingsDialogWrongJSON(
                      e.toString(),
                    ),
                  ),
                );
              }
            },
            child: Text(context.l10n.common_save),
          ),
        ],
      ),
    );
  }

  void _showDeleteCyr2LatProfileDialog(
    BuildContext context,
    AppSettingsService settingsService,
    Cyr2LatProfile profile,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settings_cyr2latProfileDelete),
        content: Text(
          context.l10n.settings_cyr2latProfileDeleteDscr(profile.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              await settingsService.removeCyr2LatProfile(profile.id);
              if (!context.mounted) return;
              Navigator.pop(context);
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.settings_cyr2latProfileDeleted),
              );
            },
            child: Text(context.l10n.common_delete),
          ),
        ],
      ),
    );
  }
}

class _CustomTimePatternDialog extends StatefulWidget {
  const _CustomTimePatternDialog({required this.initialPattern});

  final String initialPattern;

  @override
  State<_CustomTimePatternDialog> createState() =>
      _CustomTimePatternDialogState();
}

class _CustomTimePatternDialogState extends State<_CustomTimePatternDialog> {
  late final TextEditingController _controller;
  late String _pattern;

  @override
  void initState() {
    super.initState();
    _pattern = widget.initialPattern;
    _controller = TextEditingController(text: _pattern);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidCustomTimePattern(_pattern);
    final preview = valid
        ? formatLocalizedTime(
            context,
            DateTime.now(),
            timeFormatPreference: TimeFormatPreference.custom,
            customTimePattern: _pattern.trim(),
          )
        : '—';
    return AlertDialog(
      title: Text(context.l10n.appSettings_customTimePattern),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 64,
              style: MeshTheme.mono(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: defaultCustomTimePattern,
                errorText: _pattern.isNotEmpty && !valid
                    ? context.l10n.appSettings_customTimePatternInvalid
                    : null,
              ),
              onChanged: (value) => setState(() => _pattern = value),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.appSettings_customTimePatternHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              '${context.l10n.appSettings_customTimePatternPreview}: $preview',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_cancel),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, _pattern.trim())
              : null,
          child: Text(context.l10n.common_save),
        ),
      ],
    );
  }
}

class _CustomDatePatternDialog extends StatefulWidget {
  const _CustomDatePatternDialog({required this.initialPattern});

  final String initialPattern;

  @override
  State<_CustomDatePatternDialog> createState() =>
      _CustomDatePatternDialogState();
}

class _CustomDatePatternDialogState extends State<_CustomDatePatternDialog> {
  late final TextEditingController _controller;
  late String _pattern;

  @override
  void initState() {
    super.initState();
    _pattern = widget.initialPattern;
    _controller = TextEditingController(text: _pattern);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = isValidCustomDatePattern(_pattern);
    final preview = valid
        ? formatLocalizedNumericDate(
            context,
            DateTime.now(),
            dateFormatPreference: DateFormatPreference.custom,
            customDatePattern: _pattern.trim(),
          )
        : '—';
    return AlertDialog(
      title: Text(context.l10n.appSettings_customDatePattern),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 64,
              style: MeshTheme.mono(),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: defaultCustomDatePattern,
                errorText: _pattern.isNotEmpty && !valid
                    ? context.l10n.appSettings_customDatePatternInvalid
                    : null,
              ),
              onChanged: (value) => setState(() => _pattern = value),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.appSettings_customDatePatternHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              '${context.l10n.appSettings_customTimePatternPreview}: $preview',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_cancel),
        ),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, _pattern.trim())
              : null,
          child: Text(context.l10n.common_save),
        ),
      ],
    );
  }
}

class _InfluxDbSettingsDialog extends StatefulWidget {
  const _InfluxDbSettingsDialog({required this.initial});

  final InfluxDbSettings initial;

  @override
  State<_InfluxDbSettingsDialog> createState() =>
      _InfluxDbSettingsDialogState();
}

class _InfluxDbSettingsDialogState extends State<_InfluxDbSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  late final TextEditingController _organization;
  late final TextEditingController _bucket;
  late final TextEditingController _retention;
  bool _showToken = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial.url);
    _token = TextEditingController(text: widget.initial.token);
    _organization = TextEditingController(text: widget.initial.organization);
    _bucket = TextEditingController(text: widget.initial.bucket);
    _retention = TextEditingController(
      text: widget.initial.retentionSeconds.toString(),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    _organization.dispose();
    _bucket.dispose();
    _retention.dispose();
    super.dispose();
  }

  InfluxDbSettings get _value => InfluxDbSettings(
    url: _url.text.trim(),
    token: _token.text.trim(),
    organization: _organization.text.trim(),
    bucket: _bucket.text.trim(),
    retentionSeconds: int.tryParse(_retention.text.trim()) ?? 0,
  );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final service = InfluxDbTelemetryService();
    try {
      await service.testConnection(_value);
      if (mounted) setState(() => _testResult = 'Connection successful');
    } catch (e) {
      if (mounted) setState(() => _testResult = e.toString());
    } finally {
      service.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('InfluxDB settings'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'InfluxDB v2 URL',
                  hintText: 'http://localhost:8086',
                ),
              ),
              TextField(
                controller: _token,
                obscureText: !_showToken,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'API token',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _showToken = !_showToken),
                    icon: Icon(
                      _showToken ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              TextField(
                controller: _organization,
                decoration: const InputDecoration(labelText: 'Organization'),
              ),
              TextField(
                controller: _bucket,
                decoration: const InputDecoration(labelText: 'Bucket'),
              ),
              TextField(
                controller: _retention,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Retention (seconds)',
                  helperText:
                      '0 keeps data indefinitely; used when creating the bucket.',
                ),
              ),
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_testResult!),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing ? null : () => Navigator.pop(context),
          child: Text(context.l10n.common_cancel),
        ),
        OutlinedButton(
          onPressed: _testing ? null : _test,
          child: _testing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test connection'),
        ),
        FilledButton(
          onPressed: _testing ? null : () => Navigator.pop(context, _value),
          child: Text(context.l10n.common_save),
        ),
      ],
    );
  }
}

/// Owns the [TextEditingController] for the manual model URL field so it
/// survives rebuilds of the parent [Consumer3].
class _TranslationUrlField extends StatefulWidget {
  const _TranslationUrlField({
    required this.initialValue,
    required this.onChanged,
    required this.onDownload,
    required this.downloadLabel,
    required this.isDownloading,
    required this.onCancel,
    required this.labelText,
    required this.stopLabel,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final void Function(String url)? onDownload;
  final String downloadLabel;
  final bool isDownloading;
  final VoidCallback onCancel;
  final String labelText;
  final String stopLabel;

  @override
  State<_TranslationUrlField> createState() => _TranslationUrlFieldState();
}

class _TranslationUrlFieldState extends State<_TranslationUrlField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.labelText,
            border: const OutlineInputBorder(),
          ),
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.onDownload == null
                    ? null
                    : () => widget.onDownload!(_controller.text.trim()),
                icon: const Icon(Icons.download),
                label: Text(widget.downloadLabel),
              ),
            ),
            if (widget.isDownloading) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(widget.stopLabel),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Dialog content for choosing the translation target language.
/// Owns the search [TextEditingController] so it is properly disposed.
class _TranslationLanguageDialogContent extends StatefulWidget {
  const _TranslationLanguageDialogContent({
    required this.currentLanguageCode,
    required this.onLanguageSelected,
  });

  final String? currentLanguageCode;
  final ValueChanged<String?> onLanguageSelected;

  @override
  State<_TranslationLanguageDialogContent> createState() =>
      _TranslationLanguageDialogContentState();
}

class _TranslationLanguageDialogContentState
    extends State<_TranslationLanguageDialogContent> {
  late final TextEditingController _searchController;
  List<TranslationLanguageOption> _filtered = supportedTranslationLanguages;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.translation_targetLanguage),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final normalized = value.trim().toLowerCase();
                setState(() {
                  _filtered = supportedTranslationLanguages.where((option) {
                    return option.label.toLowerCase().contains(normalized) ||
                        option.code.toLowerCase().contains(normalized);
                  }).toList();
                });
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: RadioGroup<String?>(
                groupValue: widget.currentLanguageCode,
                onChanged: (value) {
                  widget.onLanguageSelected(value);
                },
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    RadioListTile<String?>(
                      value: null,
                      title: Text(context.l10n.translation_useAppLanguage),
                    ),
                    for (final option in _filtered)
                      RadioListTile<String?>(
                        value: option.code,
                        title: Text(option.label),
                        subtitle: Text(option.code.toUpperCase()),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.common_close),
        ),
      ],
    );
  }
}
