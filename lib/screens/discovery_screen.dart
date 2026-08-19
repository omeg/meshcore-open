import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../l10n/l10n.dart';
import '../l10n/contact_localization.dart';
import '../models/app_settings.dart';
import '../models/contact.dart';
import '../models/meshcore_share_link.dart';
import '../services/app_settings_service.dart';
import '../theme/mesh_theme.dart';
import '../utils/contact_search.dart';
import '../utils/platform_info.dart';
import '../widgets/app_bar.dart';
import '../widgets/desktop_delete_shortcut.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/mesh_ui.dart';
import '../helpers/snack_bar_builder.dart';

enum DiscoverySortOption { lastSeen, name, type }

class DiscoveryScreen extends StatefulWidget {
  final String? highlightedContactPublicKeyHex;

  const DiscoveryScreen({super.key, this.highlightedContactPublicKeyHex});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';
  ContactSortOption sortOption = ContactSortOption.lastSeen;
  bool showUnreadOnly = false;
  ContactTypeFilter typeFilter = ContactTypeFilter.all;
  DiscoverySortOption discoverySortOption = DiscoverySortOption.lastSeen;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  DateTime _resolveLastSeen(Contact contact) {
    if (contact.type != advTypeChat) return contact.lastSeen;
    return contact.lastMessageAt.isAfter(contact.lastSeen)
        ? contact.lastMessageAt
        : contact.lastSeen;
  }

  int _hopSortValue(Contact contact) {
    final hops = contact.pathOverride ?? contact.pathLength;
    return hops < 0 ? 1 << 30 : hops;
  }

  int _compareByName(Contact a, Contact b) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _compareByLastAdvert(Contact a, Contact b, DateTime now) {
    final aIsFuture = a.lastSeen.isAfter(now);
    final bIsFuture = b.lastSeen.isAfter(now);
    if (aIsFuture != bIsFuture) return aIsFuture ? 1 : -1;

    final lastAdvert = b.lastSeen.compareTo(a.lastSeen);
    if (lastAdvert != 0) return lastAdvert;
    return _compareByName(a, b);
  }

  /// Node-type avatar color per design language.
  Color _avatarColor(int type) {
    switch (type) {
      case advTypeRepeater:
        return MeshPalette.warn;
      case advTypeRoom:
        return MeshPalette.magenta;
      case advTypeSensor:
        return const Color(0xFF4ACCC4); // teal
      default:
        return MeshPalette.blue;
    }
  }

  /// Node-type avatar icon; null = show initials for chat nodes.
  IconData? _avatarIcon(int type) {
    switch (type) {
      case advTypeRepeater:
        return Icons.cell_tower;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final connector = context.watch<MeshCoreConnector>();
    final settings = context.watch<AppSettingsService>().settings;

    final discoveredContacts = connector.discoveredContacts;
    final filteredAndSorted = _filterAndSortContacts(
      discoveredContacts,
      connector,
    );

    return Scaffold(
      appBar: AppBar(
        title: AppBarTitle(
          l10n.discoveredContacts_Title,
          indicators: false,
          subtitle: false,
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(
                      Icons.delete,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.discoveredContacts_deleteContactAll),
                  ],
                ),
                onTap: () {
                  _deleteContacts(context, connector);
                },
              ),
            ],
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(filteredAndSorted, connector),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: discoveredContacts.isEmpty
                  ? Center(
                      key: const ValueKey('empty_all'),
                      child: Text(l10n.contacts_noContacts),
                    )
                  : filteredAndSorted.isEmpty
                  ? Center(
                      key: const ValueKey('empty_filtered'),
                      child: Text(l10n.discoveredContacts_noMatching),
                    )
                  : ListView.builder(
                      key: const ValueKey('list'),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: filteredAndSorted.length,
                      itemBuilder: (context, index) {
                        final contact = filteredAndSorted[index];
                        final tile = _buildDiscoveryTile(
                          context,
                          contact,
                          connector,
                          settings.discoveredContactTapAction,
                          index,
                        );
                        return tile;
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoveryTile(
    BuildContext context,
    Contact contact,
    MeshCoreConnector connector,
    DiscoveredContactTapAction tapAction,
    int index,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isChat = contact.type == advTypeChat;
    final routeHops = contact.pathOverride ?? contact.pathLength;
    final isDirect = routeHops >= 0;

    return ListEntrance(
      key: ValueKey(
        'discovered_contact_delete_shortcut_${contact.publicKeyHex}',
      ),
      index: index,
      child: DesktopDeleteShortcut(
        onDelete: () => connector.removeDiscoveredContact(contact),
        builder: (context, selected) => MeshCard(
          borderColor:
              selected ||
                  contact.publicKeyHex == widget.highlightedContactPublicKeyHex
              ? scheme.primary
              : null,
          onTap: () => _handleContactTap(contact, connector, tapAction),
          onLongPress: () => _showContactContextMenu(contact, connector),
          onSecondaryTap: PlatformInfo.isDesktop
              ? () => _showContactContextMenu(contact, connector)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              AvatarCircle(
                name: contact.name,
                size: 42,
                color: isChat ? null : _avatarColor(contact.type),
                icon: _avatarIcon(contact.type),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name + last seen time
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(
                              MediaQuery.textScalerOf(
                                context,
                              ).scale(1.0).clamp(1.0, 1.3),
                            ),
                          ),
                          child: Text(
                            _formatLastSeen(_resolveLastSeen(contact)),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: MeshTheme.mono(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Short pub key
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.shortPubKeyHex,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MeshTheme.mono(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (contact.hasLocation) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.location_on,
                            size: 13,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ],
                        if (contact.rawPacket != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.cell_tower,
                            size: 13,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.55,
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        RouteChip(
                          isDirect: isDirect,
                          hops: isDirect ? routeHops : null,
                          showDirectIcon: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleContactTap(
    Contact contact,
    MeshCoreConnector connector,
    DiscoveredContactTapAction tapAction,
  ) async {
    switch (tapAction) {
      case DiscoveredContactTapAction.showActions:
        await _showContactContextMenu(contact, connector);
      case DiscoveredContactTapAction.importContact:
        await _importContact(contact, connector);
    }
  }

  Future<void> _importContact(
    Contact contact,
    MeshCoreConnector connector,
  ) async {
    if (connector.isContactPersistenceSuspended) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_syncChangesDisabled),
      );
      return;
    }
    try {
      final imported = await connector.importDiscoveredContact(contact);
      if (!mounted) return;
      if (!imported) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactImportFailed),
        );
        return;
      }
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.discoveredContacts_contactAdded),
        action: SnackBarAction(
          label: context.l10n.common_undo,
          onPressed: () => connector.removeContact(contact),
        ),
        persist: false,
      );
    } catch (_) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_contactImportFailed),
      );
    }
  }

  Future<void> _showContactContextMenu(
    Contact contact,
    MeshCoreConnector connector,
  ) async {
    final action = await showMeshSheet<String>(
      context,
      builder: (sheetContext) {
        final l10n = context.l10n;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BottomSheetHeader(
                title: contact.name,
                subtitle: contact.typeLabel(l10n),
              ),
              ListTile(
                leading: const Icon(Icons.person_add),
                title: Text(l10n.discoveredContacts_addContact),
                onTap: () => Navigator.of(sheetContext).pop('add_contact'),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(l10n.discoveredContacts_copyContact),
                onTap: () => Navigator.of(sheetContext).pop('copy_contact'),
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: Text(l10n.discoveredContacts_deleteContact),
                onTap: () => Navigator.of(sheetContext).pop('delete_contact'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;

    switch (action) {
      case 'add_contact':
        await _importContact(contact, connector);
        break;
      case 'copy_contact':
        final link = MeshCoreContactShareLink.fromContact(
          contact,
        ).toUriString();
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.shareLink_copied),
        );
        break;
      case 'delete_contact':
        connector.removeDiscoveredContact(contact);
        break;
    }
  }

  void _deleteContacts(BuildContext context, MeshCoreConnector connector) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.common_deleteAll),
        content: Text(l10n.discoveredContacts_deleteContactAllContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              connector.removeAllDiscoveredContacts();
            },
            child: Text(l10n.common_deleteAll),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(
    List<Contact> filteredAndSorted,
    MeshCoreConnector connector,
  ) {
    String hintText = "";
    switch (typeFilter) {
      case ContactTypeFilter.all:
        hintText = context.l10n.contacts_searchContacts(
          filteredAndSorted.length,
          showUnreadOnly ? " ${context.l10n.contacts_unread}" : "",
        );
        break;
      case ContactTypeFilter.users:
        hintText = context.l10n.contacts_searchUsers(
          filteredAndSorted.length,
          showUnreadOnly ? " ${context.l10n.contacts_unread}" : "",
        );
        break;
      case ContactTypeFilter.repeaters:
        hintText = context.l10n.contacts_searchRepeaters(
          filteredAndSorted.length,
          showUnreadOnly ? " ${context.l10n.contacts_unread}" : "",
        );
        break;
      case ContactTypeFilter.rooms:
        hintText = context.l10n.contacts_searchRoomServers(
          filteredAndSorted.length,
          showUnreadOnly ? " ${context.l10n.contacts_unread}" : "",
        );
        break;
      case ContactTypeFilter.favorites:
        hintText = context.l10n.contacts_searchFavorites(
          filteredAndSorted.length,
          showUnreadOnly ? " ${context.l10n.contacts_unread}" : "",
        );
        break;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          searchQuery = '';
                        });
                      },
                    ),
                  _buildFilterButton(context, connector),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilterButton(BuildContext context, MeshCoreConnector connector) {
    return DiscoveryContactsFilterMenu(
      sortOption: sortOption,
      typeFilter: typeFilter,
      onSortChanged: (value) {
        setState(() {
          sortOption = value;
        });
      },
      onTypeFilterChanged: (value) {
        setState(() {
          typeFilter = value;
        });
      },
    );
  }

  List<Contact> _filterAndSortContacts(
    List<Contact> contacts,
    MeshCoreConnector connector,
  ) {
    var filtered = contacts.where((contact) {
      if (searchQuery.isEmpty) return true;
      return matchesDiscoveryContactQuery(contact, searchQuery);
    }).toList();

    filtered = filtered.where((contact) {
      return !connector.knownContactKeys.contains(contact.publicKeyHex);
    }).toList();

    // Filter out own node from the list
    if (connector.selfPublicKey != null) {
      final selfPubKeyHex = pubKeyToHex(connector.selfPublicKey!);
      filtered = filtered.where((contact) {
        return contact.publicKeyHex != selfPubKeyHex;
      }).toList();
    }

    if (typeFilter != ContactTypeFilter.all) {
      filtered = filtered.where(_matchesTypeFilter).toList();
    }

    final now = DateTime.now();
    switch (sortOption) {
      case ContactSortOption.lastSeen:
        filtered.sort((a, b) => _compareByLastAdvert(a, b, now));
        break;
      case ContactSortOption.name:
        filtered.sort(_compareByName);
        break;
      case ContactSortOption.hops:
        filtered.sort((a, b) {
          final hops = _hopSortValue(a).compareTo(_hopSortValue(b));
          if (hops != 0) return hops;
          final lastSeen = _resolveLastSeen(b).compareTo(_resolveLastSeen(a));
          if (lastSeen != 0) return lastSeen;
          return _compareByName(a, b);
        });
        break;
      case ContactSortOption.recentMessages:
        filtered.sort(
          (a, b) => _resolveLastSeen(b).compareTo(_resolveLastSeen(a)),
        );
        break;
    }

    final highlightedKey = widget.highlightedContactPublicKeyHex;
    if (highlightedKey != null) {
      Contact? highlighted;
      for (final contact in contacts) {
        if (contact.publicKeyHex == highlightedKey) {
          highlighted = contact;
          break;
        }
      }
      if (highlighted != null) {
        filtered.removeWhere(
          (contact) => contact.publicKeyHex == highlightedKey,
        );
        filtered.insert(0, highlighted);
      }
    }

    return filtered;
  }

  bool _matchesTypeFilter(Contact contact) {
    switch (typeFilter) {
      case ContactTypeFilter.all:
        return true;
      case ContactTypeFilter.users:
        return contact.type == advTypeChat;
      case ContactTypeFilter.repeaters:
        return contact.type == advTypeRepeater;
      case ContactTypeFilter.rooms:
        return contact.type == advTypeRoom;
      default:
        return false;
    }
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    final elapsed = diff.isNegative ? Duration.zero : diff;

    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} m';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h';
    return '${elapsed.inDays} d';
  }
}
