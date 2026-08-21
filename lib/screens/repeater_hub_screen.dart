import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:provider/provider.dart';
import '../connector/meshcore_connector.dart';
import '../helpers/public_key.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../l10n/contact_localization.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/remote_node_auth.dart';
import 'repeater_status_screen.dart';
import 'repeater_cli_screen.dart';
import 'repeater_settings_screen.dart';
import 'telemetry_screen.dart';
import 'telemetry_log_screen.dart';
import 'neighbors_screen.dart';
import 'map_screen.dart';

class RepeaterHubScreen extends StatelessWidget {
  final Contact repeater;
  final String password;
  final bool isAdmin;

  const RepeaterHubScreen({
    super.key,
    required this.repeater,
    required this.password,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final settingsService = context.watch<AppSettingsService>();
    final authSession = context
        .watch<MeshCoreConnector>()
        .remoteNodeAuthSession(repeater);
    final effectivePassword = authSession?.password ?? password;
    final effectiveIsAdmin = authSession?.isAdmin ?? isAdmin;
    final chemistry = settingsService.batteryChemistryForRepeater(
      repeater.publicKeyHex,
    );

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(
          repeater.type == advTypeRepeater
              ? (effectiveIsAdmin
                    ? l10n.repeater_management
                    : l10n.repeater_guest)
              : (effectiveIsAdmin ? l10n.room_management : l10n.room_guest),
          subtitle: false,
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            tooltip: l10n.contacts_moreOptions,
            onSelected: (value) {
              switch (value) {
                case 'reauthenticate':
                  _reauthenticate(context);
                case 'forgetCredentials':
                  _forgetCredentials(context);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reauthenticate',
                child: Row(
                  children: [
                    const Icon(Icons.lock_reset, size: 20),
                    const SizedBox(width: 12),
                    Text(l10n.login_reauthenticate),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'forgetCredentials',
                child: Row(
                  children: [
                    Icon(
                      Icons.key_off,
                      size: 20,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.login_forgetCredentials,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            // ── Identity card ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: MeshCard(
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    AvatarCircle(
                      name: repeater.name,
                      size: 52,
                      color: MeshPalette.warn,
                      icon: Icons.cell_tower,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            repeater.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                fit: FlexFit.loose,
                                child: Text(
                                  formatPublicKeyHex(repeater.publicKeyHex),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: MeshTheme.mono(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              IconButton(
                                tooltip: l10n.common_copy,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(24, 24),
                                  maximumSize: const Size(24, 24),
                                  padding: EdgeInsets.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                alignment: Alignment.centerLeft,
                                icon: const Icon(Icons.copy_outlined, size: 15),
                                onPressed: () => copyPublicKeyHex(
                                  context,
                                  repeater.publicKeyHex,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            repeater.pathLabel(l10n),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          if (repeater.hasLocation) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  fit: FlexFit.loose,
                                  child: Text(
                                    '${repeater.latitude?.toStringAsFixed(4)}, '
                                    '${repeater.longitude?.toStringAsFixed(4)}',
                                    maxLines: 1,
                                    style: MeshTheme.mono(
                                      fontSize: 10,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  key: const ValueKey('repeater_show_on_map'),
                                  tooltip: l10n.settings_locationShowOnMap,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(24, 24),
                                    maximumSize: const Size(24, 24),
                                    padding: EdgeInsets.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  alignment: Alignment.centerLeft,
                                  icon: const Icon(
                                    Icons.map_outlined,
                                    size: 15,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => MapScreen(
                                          highlightPosition: LatLng(
                                            repeater.latitude!,
                                            repeater.longitude!,
                                          ),
                                          highlightLabel: repeater.name,
                                          highlightMarkerKey:
                                              repeater.publicKeyHex,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    StatusChip(
                      label: effectiveIsAdmin ? 'ADMIN' : 'GUEST',
                      color: effectiveIsAdmin
                          ? MeshPalette.blue
                          : scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // ── Battery chemistry (admin only) ─────────────────────────────
            if (effectiveIsAdmin) ...[
              SectionHeader(l10n.appSettings_batteryChemistry),
              MeshCard(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: DropdownButtonFormField<String>(
                  initialValue: chemistry,
                  isExpanded: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.battery_full, size: 18),
                    labelText: l10n.appSettings_batteryChemistry,
                  ),
                  onChanged: (value) {
                    if (value == null) return;
                    settingsService.setBatteryChemistryForRepeater(
                      repeater.publicKeyHex,
                      value,
                    );
                  },
                  items: [
                    DropdownMenuItem(
                      value: 'nmc',
                      child: Text(l10n.appSettings_batteryNmc),
                    ),
                    DropdownMenuItem(
                      value: 'lifepo4',
                      child: Text(l10n.appSettings_batteryLifepo4),
                    ),
                    DropdownMenuItem(
                      value: 'lipo',
                      child: Text(l10n.appSettings_batteryLipo),
                    ),
                  ],
                ),
              ),
            ],

            // ── Tools ──────────────────────────────────────────────────────
            SectionHeader(
              effectiveIsAdmin
                  ? l10n.repeater_managementTools
                  : l10n.repeater_guestTools,
            ),

            _HubActionTile(
              index: 0,
              icon: Icons.analytics,
              title: l10n.repeater_status,
              subtitle: l10n.repeater_statusSubtitle,
              accentColor: MeshPalette.blue,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RepeaterStatusScreen(
                      repeater: repeater,
                      password: effectivePassword,
                    ),
                  ),
                );
              },
            ),

            _HubActionTile(
              index: 1,
              icon: Icons.bar_chart_sharp,
              title: l10n.repeater_telemetry,
              subtitle: l10n.repeater_telemetrySubtitle,
              accentColor: MeshPalette.magenta,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TelemetryScreen(contact: repeater),
                  ),
                );
              },
            ),
            _HubActionTile(
              index: 2,
              icon: Icons.group,
              title: l10n.repeater_neighbors,
              subtitle: l10n.repeater_neighborsSubtitle,
              accentColor: MeshPalette.signal,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NeighborsScreen(
                      repeater: repeater,
                      password: effectivePassword,
                    ),
                  ),
                );
              },
            ),

            if (effectiveIsAdmin) ...[
              _HubActionTile(
                index: 3,
                icon: Icons.history,
                title: l10n.telemetryLog_title,
                subtitle: l10n.telemetryLog_subtitle,
                accentColor: MeshPalette.blue,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          TelemetryLogScreen(repeater: repeater),
                    ),
                  );
                },
              ),
              _HubActionTile(
                index: 4,
                icon: Icons.terminal,
                title: l10n.repeater_cli,
                subtitle: l10n.repeater_cliSubtitle,
                accentColor: MeshPalette.warn,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterCliScreen(
                        repeater: repeater,
                        password: effectivePassword,
                      ),
                    ),
                  );
                },
              ),
              _HubActionTile(
                index: 5,
                icon: Icons.settings,
                title: l10n.repeater_settings,
                subtitle: l10n.repeater_settingsSubtitle,
                accentColor: MeshPalette.alert,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RepeaterSettingsScreen(
                        repeater: repeater,
                        password: effectivePassword,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reauthenticate(BuildContext context) async {
    final session = await ensureRemoteNodeAuthenticated(
      context,
      contact: repeater,
      forceLogin: true,
    );
    if (!context.mounted) return;
    if (session == null) {
      Navigator.pop(context);
    }
  }

  Future<void> _forgetCredentials(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.login_forgetCredentialsTitle),
        content: Text(
          context.l10n.login_forgetCredentialsMessage(repeater.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              context.l10n.login_forgetCredentials,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await forgetRemoteNodeCredentials(context, contact: repeater);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}

class _HubActionTile extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _HubActionTile({
    required this.index,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListEntrance(
      index: index,
      child: MeshCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(MeshRadii.md),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: accentColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }
}
