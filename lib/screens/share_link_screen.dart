import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/contact_localization.dart';
import '../l10n/l10n.dart';
import '../models/meshcore_share_link.dart';
import '../theme/mesh_theme.dart';
import '../widgets/app_bar.dart';
import '../widgets/byte_count_input.dart';
import '../helpers/snack_bar_builder.dart';

class ShareLinkScreen extends StatefulWidget {
  final MeshCoreShareLink link;

  const ShareLinkScreen({super.key, required this.link});

  @override
  State<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends State<ShareLinkScreen> {
  late final TextEditingController _channelNameController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final link = widget.link;
    _channelNameController = TextEditingController(
      text: link is MeshCoreChannelShareLink ? link.name : '',
    );
  }

  @override
  void dispose() {
    _channelNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return Scaffold(
      appBar: AppBar(title: AppBarTitle(context.l10n.shareLink_title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (link case final MeshCoreContactShareLink contactLink)
              _buildContact(context, contactLink)
            else if (link case final MeshCoreChannelShareLink channelLink)
              _buildChannel(context, channelLink),
          ],
        ),
      ),
    );
  }

  Widget _buildContact(BuildContext context, MeshCoreContactShareLink link) {
    final connector = context.watch<MeshCoreConnector>();
    final contact = link.hasStructuredContact ? link.toContact() : null;
    final name = link.name ?? context.l10n.shareLink_contact;
    final typeLabel = contact?.typeLabel(context.l10n);

    return _ShareCard(
      icon: Icons.person_add_alt_1,
      title: name,
      subtitle: typeLabel ?? context.l10n.shareLink_contact,
      children: [
        if (link.publicKey != null)
          _InfoRow(
            label: context.l10n.chat_publicKey,
            value: pubKeyToHex(link.publicKey!),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: connector.isConnected && !_submitting
              ? () => _addContact(link)
              : null,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_alt_1),
          label: Text(context.l10n.shareLink_addContact),
        ),
      ],
    );
  }

  Widget _buildChannel(BuildContext context, MeshCoreChannelShareLink link) {
    final connector = context.watch<MeshCoreConnector>();
    final nextIndex = _findNextAvailableChannelIndex(connector);

    return _ShareCard(
      icon: link.isPrivate ? Icons.lock_outline : Icons.tag,
      title: link.name,
      subtitle: link.isPrivate
          ? context.l10n.channels_private
          : context.l10n.shareLink_channel,
      children: [
        if (link.isPrivate) ...[
          ByteCountedTextField(
            key: const ValueKey('share_link_channel_name'),
            maxBytes: maxNameSize - 1,
            controller: _channelNameController,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: context.l10n.channels_channelName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.shareLink_privateChannelNameHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
        ] else
          _InfoRow(label: context.l10n.channels_channelName, value: link.name),
        _InfoRow(
          label: context.l10n.shareLink_channelSecret,
          value: link.secretHex,
        ),
        if (link.regionScope != null)
          _InfoRow(
            label: context.l10n.settings_regionName,
            value: link.regionScope!,
          ),
        if (nextIndex == null) ...[
          const SizedBox(height: 12),
          Text(
            context.l10n.shareLink_noChannelSlots,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: connector.isConnected && !_submitting && nextIndex != null
              ? () => _addChannel(link, nextIndex)
              : null,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(context.l10n.shareLink_addChannel),
        ),
      ],
    );
  }

  Future<void> _addContact(MeshCoreContactShareLink link) async {
    setState(() => _submitting = true);
    try {
      final connector = context.read<MeshCoreConnector>();
      if (link.hasStructuredContact) {
        await connector.importDiscoveredContact(link.toContact());
      } else if (link.advertData != null) {
        await connector.sendFrame(
          buildImportContactFrame(link.advertData!),
          waitForGenericAck: true,
        );
        await connector.getContacts();
      } else {
        throw const FormatException('Contact link has no importable data');
      }
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImported),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImportFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  Future<void> _addChannel(
    MeshCoreChannelShareLink link,
    int channelIndex,
  ) async {
    final name = link.isPrivate
        ? _channelNameController.text.trim()
        : link.name;
    if (name.isEmpty) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.channels_enterChannelName),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final connector = context.read<MeshCoreConnector>();
      await connector.setChannel(
        channelIndex,
        name,
        Uint8List.fromList(link.secret),
      );
      if (link.regionScope != null) {
        await connector.setChannelRegion(channelIndex, link.regionScope!);
      }
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.channels_channelAdded(name)),
      );
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.shareLink_channelAddFailed),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    }
  }

  int? _findNextAvailableChannelIndex(MeshCoreConnector connector) {
    final used = connector.channels.map((channel) => channel.index).toSet();
    for (var index = 0; index < connector.maxChannels; index++) {
      if (!used.contains(index)) return index;
    }
    return null;
  }
}

class _ShareCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _ShareCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(value, style: MeshTheme.mono(fontSize: 13)),
        ],
      ),
    );
  }
}
