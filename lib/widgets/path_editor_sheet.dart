import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../connector/meshcore_protocol.dart';
import '../helpers/path_hash.dart';
import '../helpers/path_helper.dart';
import '../l10n/contact_localization.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';

class PathEditorSheet extends StatefulWidget {
  final List<Contact> availableContacts;
  final List<int> initialPath;
  final int pathHashByteWidth;

  const PathEditorSheet({
    super.key,
    required this.availableContacts,
    this.initialPath = const [],
    this.pathHashByteWidth = 1,
  });

  static Future<Uint8List?> show(
    BuildContext context, {
    required List<Contact> availableContacts,
    List<int> initialPath = const [],
    int pathHashByteWidth = 1,
  }) {
    return showModalBottomSheet<Uint8List>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.9,
          child: PathEditorSheet(
            availableContacts: availableContacts,
            initialPath: initialPath,
            pathHashByteWidth: pathHashByteWidth,
          ),
        ),
      ),
    );
  }

  @override
  State<PathEditorSheet> createState() => _PathEditorSheetState();
}

class _Hop {
  final int id;
  final Uint8List bytes;

  const _Hop(this.id, this.bytes);
}

class _PathEditorSheetState extends State<PathEditorSheet> {
  final List<_Hop> _hops = [];
  final _hexController = TextEditingController();
  String? _hexError;
  bool _syncingHex = false;
  String _search = '';
  int _nextHopId = 0;

  int get _hashByteWidth =>
      normalizePathHashByteWidth(widget.pathHashByteWidth);

  int get _maxHops => maxPathHopCountForWidth(_hashByteWidth);

  int get _hexCharsPerHop => _hashByteWidth * 2;

  @override
  void initState() {
    super.initState();
    final chunks = PathHelper.splitPathBytes(
      trimPathBytesToWidth(widget.initialPath, _hashByteWidth),
      _hashByteWidth,
    );
    for (final chunk in chunks) {
      _hops.add(_Hop(_nextHopId++, chunk));
    }
    _syncHexFromHops();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  List<Contact> get _repeaters {
    final query = _search.trim().toLowerCase();
    return widget.availableContacts
        .where((c) => c.type == advTypeRepeater || c.type == advTypeRoom)
        .where((c) => c.publicKey.length >= _hashByteWidth)
        .where((c) => query.isEmpty || c.name.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  void _syncHexFromHops() {
    _syncingHex = true;
    _hexController.text = PathHelper.formatPathHex(
      _hops.expand((h) => h.bytes).toList(),
      _hashByteWidth,
    );
    _syncingHex = false;
    _hexError = null;
  }

  Uint8List? _parseHopToken(String token) {
    if (token.length != _hexCharsPerHop ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(token)) {
      return null;
    }
    final bytes = <int>[];
    for (var i = 0; i < token.length; i += 2) {
      final value = int.tryParse(token.substring(i, i + 2), radix: 16);
      if (value == null) return null;
      bytes.add(value);
    }
    return Uint8List.fromList(bytes);
  }

  void _onHexChanged(String text) {
    if (_syncingHex) return;
    final l10n = context.l10n;
    final tokens = text
        .split(RegExp(r'[,\s]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final parsed = <Uint8List>[];
    final invalid = <String>[];
    for (final token in tokens) {
      final hop = _parseHopToken(token);
      if (hop == null) {
        invalid.add(token);
      } else {
        parsed.add(hop);
      }
    }
    setState(() {
      if (invalid.isNotEmpty) {
        _hexError = l10n.pathEditor_invalidTokens(invalid.join(', '));
        return;
      }
      if (tokens.length > _maxHops) {
        _hexError = l10n.pathEditor_tooManyHops;
        return;
      }
      _hexError = null;
      _hops
        ..clear()
        ..addAll(parsed.map((hop) => _Hop(_nextHopId++, hop)));
    });
  }

  void _addHop(Contact contact) {
    if (_hops.length >= _maxHops) return;
    if (contact.publicKey.length < _hashByteWidth) return;
    setState(() {
      _hops.add(
        _Hop(
          _nextHopId++,
          Uint8List.fromList(contact.publicKey.sublist(0, _hashByteWidth)),
        ),
      );
      _syncHexFromHops();
    });
  }

  void _removeHop(int index) {
    setState(() {
      _hops.removeAt(index);
      _syncHexFromHops();
    });
  }

  void _reorderHop(int oldIndex, int newIndex) {
    setState(() {
      final hop = _hops.removeAt(oldIndex);
      _hops.insert(newIndex, hop);
      _syncHexFromHops();
    });
  }

  void _save() {
    Navigator.pop(
      context,
      Uint8List.fromList(_hops.expand((h) => h.bytes).toList()),
    );
  }

  String? _hopName(List<int> hopBytes) {
    final matches = widget.availableContacts
        .where(
          (c) =>
              c.publicKey.length >= hopBytes.length &&
              listEquals(c.publicKey.sublist(0, hopBytes.length), hopBytes) &&
              (c.type == advTypeRepeater || c.type == advTypeRoom),
        )
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first.name;
    return matches.map((c) => c.name).join(' | ');
  }

  Widget _hopTile(BuildContext context, int index) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final hop = _hops[index];
    final hex = PathHelper.formatHopHex(hop.bytes);
    final name = _hopName(hop.bytes);

    return ListTile(
      key: ValueKey(hop.id),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: scheme.primaryContainer,
        child: Text(
          '${index + 1}',
          style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        name ?? l10n.pathEditor_unknownHop,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(hex),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: l10n.pathEditor_removeHop,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => _removeHop(index),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _repeaterTile(BuildContext context, Contact contact) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isRepeater = contact.type == advTypeRepeater;
    final full = _hops.length >= _maxHops;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !full,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: isRepeater
            ? scheme.primaryContainer
            : scheme.secondaryContainer,
        child: Icon(
          isRepeater ? Icons.router : Icons.meeting_room,
          size: 16,
          color: isRepeater
              ? scheme.onPrimaryContainer
              : scheme.onSecondaryContainer,
        ),
      ),
      title: Text(contact.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${contact.typeLabel(l10n)} • ${PathHelper.formatHopHex(contact.publicKey.sublist(0, _hashByteWidth))}',
      ),
      trailing: const Icon(Icons.add_circle_outline),
      onTap: full ? null : () => _addHop(contact),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repeaters = _repeaters;

    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(
            color: scheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.pathEditor_title, style: theme.textTheme.titleLarge),
              Text(
                l10n.pathEditor_hopCounter(_hops.length),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              if (_hops.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.pathEditor_noHops,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: _hops.length,
                  onReorderItem: _reorderHop,
                  itemBuilder: _hopTile,
                ),
              const Divider(),
              const SizedBox(height: 8),
              Text(l10n.pathEditor_addHops, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() => _search = value),
                decoration: InputDecoration(
                  labelText: l10n.pathEditor_searchRepeaters,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 4),
              if (repeaters.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.path_noRepeatersFound,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                ...repeaters.map((c) => _repeaterTile(context, c)),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  l10n.pathEditor_advancedHex,
                  style: theme.textTheme.titleSmall,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _hexController,
                      onChanged: _onHexChanged,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l10n.pathEditor_hexLabel,
                        helperText: _hexError == null
                            ? l10n.pathEditor_hexHelper
                            : null,
                        errorText: _hexError,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.common_cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _hexError != null ? null : _save,
                    child: Text(l10n.pathEditor_usePath),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
