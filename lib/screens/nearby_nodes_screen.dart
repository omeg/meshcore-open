import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import '../theme/mesh_theme.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/platform_info.dart';
import '../widgets/empty_state.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/nearby_repeater_actions.dart';
import '../widgets/snr_indicator.dart';

class NearbyNodesScreen extends StatefulWidget {
  const NearbyNodesScreen({super.key});

  @override
  State<NearbyNodesScreen> createState() => _NearbyNodesScreenState();
}

class _NearbyNodesScreenState extends State<NearbyNodesScreen>
    with DisconnectNavigationMixin {
  static const _discoveryWindow = Duration(seconds: 15);

  final Map<String, DiscoveryResponse> _responses = {};
  StreamSubscription<Uint8List>? _frameSubscription;
  Timer? _discoveryTimer;
  int? _activeTag;
  bool _isDiscovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_discover());
  }

  @override
  void dispose() {
    _frameSubscription?.cancel();
    _discoveryTimer?.cancel();
    super.dispose();
  }

  Future<void> _discover() async {
    final connector = context.read<MeshCoreConnector>();
    if (!connector.isConnected || _isDiscovering) return;

    await _frameSubscription?.cancel();
    _discoveryTimer?.cancel();

    final tag = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
    setState(() {
      _activeTag = tag;
      _responses.clear();
      _error = null;
      _isDiscovering = true;
    });

    _frameSubscription = connector.receivedFrames.listen((frame) {
      final response = parseDiscoveryResponseFrame(frame);
      if (response == null ||
          response.tag != _activeTag ||
          response.nodeType != advTypeRepeater ||
          response.publicKey.length != pubKeySize) {
        return;
      }

      final key = pubKeyToHex(response.publicKey);
      if (key == connector.selfPublicKeyHex || !mounted) return;
      setState(() => _responses[key] = response);
    });

    try {
      final payload = buildDiscoveryRequestPayload(tag);
      await connector.sendFrame(buildSendControlDataFrame(payload));
      _discoveryTimer = Timer(_discoveryWindow, _finishDiscovery);
    } catch (error) {
      await _frameSubscription?.cancel();
      _frameSubscription = null;
      if (!mounted) return;
      setState(() {
        _isDiscovering = false;
        _error = error.toString();
      });
    }
  }

  void _finishDiscovery() {
    _frameSubscription?.cancel();
    _frameSubscription = null;
    if (!mounted) return;
    setState(() => _isDiscovering = false);
  }

  Contact? _findContact(
    MeshCoreConnector connector,
    DiscoveryResponse response,
  ) {
    final key = pubKeyToHex(response.publicKey);
    for (final contact in connector.allContactsUnfiltered) {
      if (contact.publicKeyHex == key) return contact;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final responses = _responses.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.nearbyNodes_title),
        actions: [
          IconButton(
            tooltip: context.l10n.repeater_refresh,
            onPressed: _isDiscovering ? null : _discover,
            icon: _isDiscovering
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_isDiscovering) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _discover,
                child: responses.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.sizeOf(context).height * 0.65,
                            child: EmptyState(
                              icon: Icons.wifi_find,
                              title: _isDiscovering
                                  ? context.l10n.nearbyNodes_listening
                                  : _error == null
                                  ? context.l10n.nearbyNodes_noneFound
                                  : context.l10n.nearbyNodes_failed,
                              subtitle:
                                  _error ??
                                  context.l10n.nearbyNodes_description,
                              action: _isDiscovering
                                  ? null
                                  : FilledButton.icon(
                                      onPressed: _discover,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(context.l10n.common_retry),
                                    ),
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: responses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final response = responses[index];
                          return _NearbyNodeTile(
                            response: response,
                            contact: _findContact(connector, response),
                            isSavedContact: connector.contacts.any(
                              (contact) =>
                                  contact.publicKeyHex ==
                                  pubKeyToHex(response.publicKey),
                            ),
                            spreadingFactor: connector.currentSf,
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyNodeTile extends StatelessWidget {
  final DiscoveryResponse response;
  final Contact? contact;
  final bool isSavedContact;
  final int? spreadingFactor;

  const _NearbyNodeTile({
    required this.response,
    required this.contact,
    required this.isSavedContact,
    required this.spreadingFactor,
  });

  @override
  Widget build(BuildContext context) {
    final keyHex = pubKeyToHex(response.publicKey);
    final displayName = contact?.name.trim().isNotEmpty == true
        ? contact!.name
        : context.l10n.nearbyNodes_unknownRepeater;
    final snrUi = snrUiFromSNR(response.snr, spreadingFactor);
    final scheme = Theme.of(context).colorScheme;

    return MeshCard(
      onTap: () {
        Clipboard.setData(ClipboardData(text: keyHex));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.nearbyNodes_keyCopied)),
        );
      },
      onLongPress: () => showNearbyRepeaterActions(
        context,
        identityHex: keyHex,
        hasFullPublicKey: true,
        isSavedContact: isSavedContact,
        contact: contact,
      ),
      onSecondaryTap: PlatformInfo.isDesktop
          ? () => showNearbyRepeaterActions(
              context,
              identityHex: keyHex,
              hasFullPublicKey: true,
              isSavedContact: isSavedContact,
              contact: contact,
            )
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AvatarCircle(name: displayName, size: 42, icon: Icons.cell_tower),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  keyHex,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MeshTheme.mono(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'RSSI ${response.rssi} dBm',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(snrUi.icon, size: 18, color: snrUi.color),
              const SizedBox(height: 3),
              Text(
                snrUi.text,
                style: MeshTheme.mono(fontSize: 11, color: snrUi.color),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
