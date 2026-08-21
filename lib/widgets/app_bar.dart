import 'package:flutter/material.dart';
import 'package:meshcore_open/connector/meshcore_connector.dart';
import 'package:meshcore_open/widgets/battery_indicator.dart';
import 'package:provider/provider.dart';

import '../l10n/l10n.dart';
import 'radio_stats_entry.dart';
import 'snr_indicator.dart';

typedef MainScreenMenuItemBuilder =
    List<PopupMenuEntry<void>> Function(BuildContext context);

/// Overflow menu shared by the primary destination and chat screens.
///
/// Screen-specific actions are shown first. Settings and Disconnect always
/// form the final group and keep the same order on every primary screen.
class MainScreenOverflowMenu extends StatelessWidget {
  final MainScreenMenuItemBuilder itemBuilder;
  final VoidCallback onSettings;
  final VoidCallback onDisconnect;
  final String? tooltip;

  const MainScreenOverflowMenu({
    super.key,
    required this.itemBuilder,
    required this.onSettings,
    required this.onDisconnect,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: tooltip,
      icon: const Icon(Icons.more_vert),
      itemBuilder: (menuContext) {
        final screenItems = itemBuilder(menuContext);
        return [
          ...screenItems,
          if (screenItems.isNotEmpty && screenItems.last is! PopupMenuDivider)
            const PopupMenuDivider(),
          PopupMenuItem<void>(
            onTap: onSettings,
            child: Row(
              children: [
                const Icon(Icons.settings),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    menuContext.l10n.settings_title,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem<void>(
            onTap: onDisconnect,
            child: Row(
              children: [
                Icon(
                  Icons.logout,
                  color: Theme.of(menuContext).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    menuContext.l10n.common_disconnect,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ];
      },
    );
  }
}

class AppBarTitle extends StatelessWidget {
  final String title;
  final Widget? content;
  final Widget? leading;
  final Widget? trailing;
  final bool indicators;
  final bool showBatteryIndicator;
  final bool showRadioStatsIndicator;
  final bool subtitle;
  const AppBarTitle(
    this.title, {
    this.content,
    this.leading,
    this.trailing,
    this.indicators = true,
    this.showBatteryIndicator = true,
    this.showRadioStatsIndicator = true,
    this.subtitle = true,
    super.key,
  });

  const AppBarTitle.custom(
    Widget this.content, {
    this.leading,
    this.trailing,
    this.indicators = true,
    this.showBatteryIndicator = true,
    this.showRadioStatsIndicator = true,
    this.subtitle = false,
    super.key,
  }) : title = '';

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    final selfName = connector.selfName;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final compact = availableWidth < 170;
        final showSubtitle =
            !compact && connector.isConnected && selfName != null && subtitle;
        final showBattery =
            connector.isConnected &&
            showBatteryIndicator &&
            availableWidth >= 60;
        final showSnr = connector.isConnected && availableWidth >= 110;
        final showIndicators = (showBattery || showSnr) && indicators;

        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            leading ?? const SizedBox.shrink(),
            Expanded(
              child:
                  content ??
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (showSubtitle)
                        Text(
                          selfName,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
            ),
            if (showIndicators) const SizedBox(width: 6),
            if (showIndicators)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showBattery) BatteryIndicator(connector: connector),
                  if (showSnr) SNRIndicator(connector: connector),
                  if (showRadioStatsIndicator &&
                      connector.supportsCompanionRadioStats)
                    const RadioStatsIconButton(compact: true),
                ],
              ),
            trailing ?? const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}
