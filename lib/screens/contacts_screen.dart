import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meshcore_open/screens/path_trace_map.dart';
import 'package:meshcore_open/services/notification_service.dart';
import 'package:meshcore_open/utils/app_logger.dart';
import 'package:meshcore_open/utils/platform_info.dart';
import 'package:meshcore_open/widgets/app_bar.dart';
import 'package:provider/provider.dart';

import '../connector/meshcore_connector.dart';
import '../l10n/l10n.dart';
import '../connector/meshcore_protocol.dart';
import '../models/contact.dart';
import '../models/meshcore_share_link.dart';
import '../l10n/contact_localization.dart';
import '../models/contact_group.dart';
import '../services/ui_view_state_service.dart';
import '../theme/mesh_theme.dart';
import '../utils/contact_search.dart';
import '../storage/contact_group_store.dart';
import '../utils/dialog_utils.dart';
import '../utils/disconnect_navigation_mixin.dart';
import '../utils/emoji_utils.dart';
import '../utils/route_transitions.dart';
import '../helpers/path_hash.dart';
import '../widgets/list_filter_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/desktop_delete_shortcut.dart';
import '../widgets/desktop_page_scroll.dart';
import '../widgets/mesh_ui.dart';
import '../widgets/quick_switch_bar.dart';
import '../widgets/remote_node_auth.dart';
import '../widgets/sync_progress_overlay.dart';
import '../widgets/unread_badge.dart';
import '../helpers/snack_bar_builder.dart';
import '../helpers/public_key.dart';
import 'channels_screen.dart';
import 'chat_screen.dart';
import 'discovery_screen.dart';
import 'map_screen.dart';
import 'nearby_nodes_screen.dart';
import 'repeater_hub_screen.dart';
import 'settings_screen.dart';
import 'telemetry_screen.dart';

enum RoomLoginDestination { chat, management }

enum ContactOperationType { import, zeroHopShare }

class ContactsScreen extends StatefulWidget {
  final bool hideBackButton;
  final String? highlightedContactPublicKeyHex;

  const ContactsScreen({
    super.key,
    this.hideBackButton = false,
    this.highlightedContactPublicKeyHex,
  });

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with DisconnectNavigationMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ContactGroupStore _groupStore = ContactGroupStore();
  MeshCoreConnector? _scopeSyncConnector;
  List<ContactGroup> _groups = [];
  String _loadedGroupScopeKeyHex = '';
  Timer? _searchDebounce;

  final List<ContactOperationType> _pendingOperations = [];

  StreamSubscription<Uint8List>? _frameSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.text = context
        .read<UiViewStateService>()
        .contactsSearchText;
    _loadGroups();
    _setupFrameListener();
    _clearAdvertNotifications();
  }

  void _clearAdvertNotifications() {
    final connector = context.read<MeshCoreConnector>();
    final contactIds = connector.contacts.map((c) => c.publicKeyHex).toList();
    NotificationService().clearAdvertNotifications(contactIds);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final connector = context.read<MeshCoreConnector>();
    if (!identical(_scopeSyncConnector, connector)) {
      _scopeSyncConnector?.removeListener(_handleConnectorScopeChange);
      _scopeSyncConnector = connector;
      _scopeSyncConnector?.addListener(_handleConnectorScopeChange);
    }
    _handleConnectorScopeChange();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _frameSubscription?.cancel();
    _scopeSyncConnector?.removeListener(_handleConnectorScopeChange);
    super.dispose();
  }

  void _handleConnectorScopeChange() {
    final connector = _scopeSyncConnector;
    if (connector == null) return;
    _syncGroupScopeIfNeeded(connector);
  }

  Future<void> _loadGroups() async {
    final selfPublicKeyHex = context.read<MeshCoreConnector>().selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty) {
      return;
    }
    _groupStore.setPublicKeyHex = selfPublicKeyHex;
    final groups = await _groupStore.loadGroups();
    if (!mounted) return;
    setState(() {
      _loadedGroupScopeKeyHex = selfPublicKeyHex;
      _groups = groups;
      _ensureValidSelectedGroup();
    });
  }

  Future<void> _saveGroups() async {
    final selfPublicKeyHex = context.read<MeshCoreConnector>().selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty) {
      return;
    }
    _groupStore.setPublicKeyHex = selfPublicKeyHex;
    await _groupStore.saveGroups(_groups);
  }

  bool _hasGroupStoreScope(MeshCoreConnector connector) {
    return connector.selfPublicKeyHex.isNotEmpty;
  }

  void _syncGroupScopeIfNeeded(MeshCoreConnector connector) {
    final selfPublicKeyHex = connector.selfPublicKeyHex;
    if (selfPublicKeyHex.isEmpty ||
        selfPublicKeyHex == _loadedGroupScopeKeyHex) {
      return;
    }
    _loadGroups();
  }

  void _collapseContactsSearch(UiViewStateService viewState) {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchController.clear();
    viewState.setContactsSearchText('');
    viewState.setContactsSearchExpanded(false);
  }

  void _showGroupsUnavailableMessage(BuildContext context) {
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.common_loading),
    );
  }

  void _setupFrameListener() {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    // Listen for incoming text messages from the repeater
    _frameSubscription = connector.receivedFrames.listen((frame) {
      if (frame.isEmpty) return;
      final frameBuffer = BufferReader(frame);
      try {
        final code = frameBuffer.readUInt8();

        // Generic OK/ERR acks carry no command correlation, so consume only
        // the oldest pending operation per ack instead of clearing all.
        if (code == respCodeOk) {
          if (!mounted) return;
          if (_pendingOperations.isEmpty) return;
          final op = _pendingOperations.removeAt(0);
          switch (op) {
            case ContactOperationType.import:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactImported),
              );
            case ContactOperationType.zeroHopShare:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_zeroHopContactAdvertSent),
              );
          }
        }

        if (code == respCodeErr) {
          if (!mounted) return;
          if (_pendingOperations.isEmpty) return;
          final op = _pendingOperations.removeAt(0);
          switch (op) {
            case ContactOperationType.import:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_contactImportFailed),
              );
            case ContactOperationType.zeroHopShare:
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_zeroHopContactAdvertFailed),
              );
          }
        }
      } catch (e) {
        appLogger.error(
          'Error processing received frame: $e',
          tag: 'ContactsScreen',
        );
      }
    });
  }

  Future<void> _contactZeroHop(Uint8List pubKey) async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    final exportContactZeroHopFrame = buildZeroHopContact(pubKey);
    _pendingOperations.add(ContactOperationType.zeroHopShare);
    try {
      await connector.sendFrame(
        exportContactZeroHopFrame,
        expectsGenericAck: true,
      );
    } catch (e) {
      _pendingOperations.remove(ContactOperationType.zeroHopShare);
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_zeroHopContactAdvertFailed),
        );
      }
    }
  }

  Uint8List _contactPathHashPrefix(Contact contact, int hashByteWidth) {
    final width = normalizePathHashByteWidth(hashByteWidth);
    if (contact.publicKey.length < width) {
      return Uint8List.fromList(contact.publicKey);
    }
    return Uint8List.fromList(contact.publicKey.sublist(0, width));
  }

  Future<void> _contactImport() async {
    final connector = Provider.of<MeshCoreConnector>(context, listen: false);
    if (connector.isContactPersistenceSuspended) {
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.contacts_syncChangesDisabled),
      );
      return;
    }
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null || clipboardData.text == null) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_clipboardEmpty),
        );
      }
      return;
    }
    final text = clipboardData.text!.trim();
    final shareLink = MeshCoreShareLink.tryParse(text);
    if (shareLink is! MeshCoreContactShareLink) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_invalidAdvertFormat),
        );
      }
      return;
    }

    if (shareLink.hasStructuredContact) {
      try {
        await connector.importDiscoveredContact(shareLink.toContact());
        if (!mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactImported),
        );
      } catch (_) {
        if (!mounted) return;
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactImportFailed),
        );
      }
      return;
    }

    if (shareLink.advertData == null) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_invalidAdvertFormat),
        );
      }
      return;
    }

    final Uint8List importContactFrame;
    try {
      importContactFrame = buildImportContactFrame(shareLink.advertData!);
    } catch (e) {
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_invalidAdvertFormat),
        );
      }
      return;
    }
    _pendingOperations.add(ContactOperationType.import);
    try {
      await connector.sendFrame(importContactFrame, expectsGenericAck: true);
    } catch (e) {
      _pendingOperations.remove(ContactOperationType.import);
      if (mounted) {
        showDismissibleSnackBar(
          context,
          content: Text(context.l10n.contacts_contactImportFailed),
        );
      }
    }
  }

  Future<void> _copyContactShareLink(Contact contact) async {
    final link = MeshCoreContactShareLink.fromContact(contact).toUriString();
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.shareLink_copied),
    );
  }

  Future<void> _copySelfShareLink(MeshCoreConnector connector) async {
    final publicKey = connector.selfPublicKey;
    final name = connector.selfName?.trim();
    if (publicKey == null || name == null || name.isEmpty) {
      if (!mounted) return;
      showDismissibleSnackBar(
        context,
        content: Text(context.l10n.shareLink_unavailable),
      );
      return;
    }
    final link = MeshCoreContactShareLink(
      name: name,
      publicKey: Uint8List.fromList(publicKey),
      type: advTypeChat,
    ).toUriString();
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    showDismissibleSnackBar(
      context,
      content: Text(context.l10n.shareLink_copied),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connector = context.watch<MeshCoreConnector>();

    // Auto-navigate back to scanner if disconnected
    if (!checkConnectionAndNavigate(connector)) {
      return const SizedBox.shrink();
    }

    final allowBack = !connector.isConnected;
    final screen = PopScope(
      canPop: allowBack,
      child: Scaffold(
        appBar: AppBar(
          title: AppBarTitle(context.l10n.contacts_title),
          automaticallyImplyLeading: false,
          bottom: const SyncProgressAppBarBottom(),
          actions: [
            PopupMenuButton(
              tooltip: context.l10n.contacts_moreOptions,
              itemBuilder: (context) => <PopupMenuEntry<dynamic>>[
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.wifi_find),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.nearbyNodes_menu,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NearbyNodesScreen(),
                    ),
                  ),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.person_add_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.discoveredContacts_Title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DiscoveryScreen(),
                    ),
                  ),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.paste),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.contacts_addContactFromClipboard,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _contactImport(),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.connect_without_contact),
                      const SizedBox(width: 8),
                      Text(context.l10n.contacts_zeroHopAdvert),
                    ],
                  ),
                  onTap: () => {
                    connector.sendSelfAdvert(flood: false),
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.settings_advertisementSent),
                    ),
                  },
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.cell_tower),
                      const SizedBox(width: 8),
                      Text(context.l10n.contacts_floodAdvert),
                    ],
                  ),
                  onTap: () => {
                    connector.sendSelfAdvert(flood: true),
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.settings_advertisementSent),
                    ),
                  },
                ),
                PopupMenuItem(
                  enabled:
                      connector.selfPublicKey != null &&
                      (connector.selfName?.trim().isNotEmpty ?? false),
                  child: Row(
                    children: [
                      const Icon(Icons.link),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.shareLink_copySelfShareLink,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  onTap: () => _copySelfShareLink(connector),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  enabled: connector.contacts.isNotEmpty,
                  onTap: () => _confirmDeleteAllContacts(context, connector),
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_sweep,
                        color: connector.contacts.isNotEmpty
                            ? Theme.of(context).colorScheme.error
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.contacts_deleteAllContacts,
                          overflow: TextOverflow.ellipsis,
                          style: connector.contacts.isNotEmpty
                              ? TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  child: Row(
                    children: [
                      Icon(
                        Icons.logout,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(context.l10n.common_disconnect),
                    ],
                  ),
                  onTap: () => _disconnect(context, connector),
                ),
                PopupMenuItem(
                  child: Row(
                    children: [
                      const Icon(Icons.settings),
                      const SizedBox(width: 8),
                      Text(context.l10n.settings_title),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: Column(
          children: [
            if (connector.isContactSyncSlow || connector.contactSyncFailed)
              _buildContactSyncNotice(context, connector),
            Expanded(child: _buildContactsBody(context, connector)),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            if (connector.isContactPersistenceSuspended) {
              showDismissibleSnackBar(
                context,
                content: Text(context.l10n.contacts_syncChangesDisabled),
              );
              return;
            }
            _showAddContactSheet(context);
          },
          child: const Icon(Icons.person_add),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: QuickSwitchBar(
            selectedIndex: 0,
            onDestinationSelected: (index) =>
                _handleQuickSwitch(index, context),
            contactsUnreadCount: connector.getTotalContactsUnreadCount(),
            channelsUnreadCount: connector.getTotalChannelsUnreadCount(),
          ),
        ),
      ),
    );
    return DesktopPageScroll(controller: _scrollController, child: screen);
  }

  Widget _buildContactSyncNotice(
    BuildContext context,
    MeshCoreConnector connector,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final failed = connector.contactSyncFailed;
    return MeshCard(
      key: const ValueKey('contact_sync_notice'),
      color: scheme.errorContainer.withValues(alpha: 0.55),
      borderColor: scheme.error.withValues(alpha: 0.4),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failed
                  ? context.l10n.contacts_syncFailedWarning
                  : context.l10n.contacts_syncSlowWarning,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (failed) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => connector.getContacts(),
              child: Text(context.l10n.common_retry),
            ),
          ],
        ],
      ),
    );
  }

  void _showAddContactSheet(BuildContext context) {
    showMeshSheet(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(title: context.l10n.contacts_title),
            ListTile(
              leading: const Icon(Icons.paste),
              title: Text(context.l10n.contacts_addContactFromClipboard),
              onTap: () {
                Navigator.pop(sheetContext);
                _contactImport();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_add_rounded),
              title: Text(context.l10n.discoveredContacts_Title),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DiscoveryScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _disconnect(
    BuildContext context,
    MeshCoreConnector connector,
  ) async {
    await showDisconnectDialog(context, connector);
  }

  ContactGroup? _selectedGroupForName(String selectedGroupName) {
    if (selectedGroupName == contactsAllGroupsValue) return null;
    for (final group in _groups) {
      if (group.name == selectedGroupName) return group;
    }
    return null;
  }

  int _hopSortValue(Contact contact) {
    final hops = contact.pathOverride ?? contact.pathLength;
    return hops < 0 ? 1 << 30 : hops;
  }

  void _ensureValidSelectedGroup() {
    final viewState = context.read<UiViewStateService>();
    if (viewState.contactsSelectedGroupName == contactsAllGroupsValue) return;
    final exists = _groups.any(
      (group) => group.name == viewState.contactsSelectedGroupName,
    );
    if (!exists) {
      viewState.setContactsSelectedGroupName(contactsAllGroupsValue);
    }
  }

  void _closeDropdownAndRun(BuildContext popupContext, VoidCallback action) {
    final route = ModalRoute.of(popupContext);
    if (route != null && route.isCurrent) {
      Navigator.of(popupContext).pop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      action();
    });
  }

  Widget _buildFilterButton(
    BuildContext context,
    UiViewStateService viewState,
  ) {
    return ContactsFilterMenu(
      sortOption: viewState.contactsSortOption,
      typeFilter: viewState.contactsTypeFilter,
      showUnreadOnly: viewState.contactsShowUnreadOnly,
      onSortChanged: (value) {
        viewState.setContactsSortOption(value);
      },
      onTypeFilterChanged: (value) {
        viewState.setContactsTypeFilter(value);
      },
      onUnreadOnlyChanged: (value) {
        viewState.setContactsShowUnreadOnly(value);
      },
    );
  }

  Widget _buildGroupButton(
    BuildContext context,
    MeshCoreConnector connector,
    UiViewStateService viewState,
    List<Contact> contacts,
    List<ContactGroup> sortedGroups,
  ) {
    final canManageGroups = _hasGroupStoreScope(connector);
    final selectedGroupName =
        _selectedGroupForName(viewState.contactsSelectedGroupName)?.name ??
        context.l10n.listFilter_all;
    final double menuWidth = (MediaQuery.sizeOf(context).width - 16).clamp(
      0.0,
      double.infinity,
    );

    return PopupMenuButton<String>(
      position: PopupMenuPosition.under,
      constraints: BoxConstraints.tightFor(width: menuWidth),
      onSelected: (String value) {
        viewState.setContactsSelectedGroupName(value);
      },
      itemBuilder: (menuContext) => [
        PopupMenuItem<String>(
          value: contactsAllGroupsValue,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(menuContext.l10n.listFilter_all),
              IconButton(
                tooltip: menuContext.l10n.contacts_newGroup,
                icon: const Icon(Icons.group_add, size: 20),
                onPressed: canManageGroups
                    ? () => _closeDropdownAndRun(
                        menuContext,
                        () => _showGroupEditor(this.context, contacts),
                      )
                    : () => _closeDropdownAndRun(
                        menuContext,
                        () => _showGroupsUnavailableMessage(this.context),
                      ),
              ),
            ],
          ),
        ),
        ...sortedGroups.map((group) {
          return PopupMenuItem<String>(
            value: group.name,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(group.name, overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  tooltip: menuContext.l10n.contacts_editGroup,
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: canManageGroups
                      ? () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupEditor(
                            this.context,
                            contacts,
                            group: group,
                          ),
                        )
                      : () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupsUnavailableMessage(this.context),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: menuContext.l10n.contacts_deleteGroup,
                  icon: Icon(
                    Icons.delete,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: canManageGroups
                      ? () => _closeDropdownAndRun(
                          menuContext,
                          () => _confirmDeleteGroup(this.context, group),
                        )
                      : () => _closeDropdownAndRun(
                          menuContext,
                          () => _showGroupsUnavailableMessage(this.context),
                        ),
                ),
              ],
            ),
          );
        }),
      ],
      child: SizedBox(
        height: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedGroupName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactsBody(BuildContext context, MeshCoreConnector connector) {
    final viewState = context.watch<UiViewStateService>();
    final contacts = connector.contacts;
    final waitingForInitialContacts =
        connector.isConnected &&
        !connector.hasLoadedContacts &&
        !connector.isLoadingContacts;
    final waitingForFirstContact =
        connector.isLoadingContacts && contacts.isEmpty;

    if (waitingForInitialContacts || waitingForFirstContact) {
      return const Center(child: CircularProgressIndicator());
    }

    if (contacts.isEmpty && _groups.isEmpty) {
      return EmptyState(
        icon: Icons.people_outline,
        title: context.l10n.contacts_noContacts,
        subtitle: context.l10n.contacts_contactsWillAppear,
        action: FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DiscoveryScreen()),
          ),
          icon: const Icon(Icons.person_add_rounded),
          label: Text(context.l10n.discoveredContacts_Title),
        ),
      );
    }

    final filteredAndSorted = _filterAndSortContacts(
      contacts,
      connector,
      viewState,
    );

    String hintText = "";

    switch (viewState.contactsTypeFilter) {
      case ContactTypeFilter.all:
        hintText = context.l10n.contacts_searchContacts(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.users:
        hintText = context.l10n.contacts_searchUsers(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.repeaters:
        hintText = context.l10n.contacts_searchRepeaters(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.rooms:
        hintText = context.l10n.contacts_searchRoomServers(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
      case ContactTypeFilter.favorites:
        hintText = context.l10n.contacts_searchFavorites(
          filteredAndSorted.length,
          viewState.contactsShowUnreadOnly
              ? " ${context.l10n.contacts_unread}"
              : "",
        );
        break;
    }

    final groupsByName = <String, ContactGroup>{};
    for (final group in _groups) {
      groupsByName.putIfAbsent(group.name, () => group);
    }
    final sortedGroups = groupsByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final screenWidth = MediaQuery.sizeOf(context).width;
    final searchExpandedWidth = (screenWidth * 0.52).clamp(
      97.0,
      double.infinity,
    ); // allow expansion up to 52% of screen width, but not less than the collapsed width
    final searchCollapsedWidth = (screenWidth * 0.22).clamp(
      97.0,
      120.0,
    ); //two 48px icon buttons + 1px divider

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: _buildGroupButton(
                  context,
                  connector,
                  viewState,
                  contacts,
                  sortedGroups,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: viewState.contactsSearchExpanded
                    ? searchExpandedWidth
                    : searchCollapsedWidth,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: viewState.contactsSearchExpanded
                            ? TextField(
                                controller: _searchController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: hintText,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                onChanged: (value) {
                                  _searchDebounce?.cancel();
                                  _searchDebounce = Timer(
                                    const Duration(milliseconds: 300),
                                    () {
                                      if (!mounted) return;
                                      context
                                          .read<UiViewStateService>()
                                          .setContactsSearchText(value);
                                    },
                                  );
                                },
                              )
                            : const SizedBox.shrink(),
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: IconButton(
                          tooltip: viewState.contactsSearchExpanded
                              ? context.l10n.contacts_searchClose
                              : context.l10n.contacts_searchOpen,
                          onPressed: () {
                            if (viewState.contactsSearchExpanded) {
                              _collapseContactsSearch(viewState);
                              return;
                            }
                            viewState.setContactsSearchExpanded(true);
                          },
                          icon: Icon(
                            viewState.contactsSearchExpanded
                                ? Icons.close
                                : Icons.search,
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: _buildFilterButton(context, viewState),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => connector.getContacts(),
            child: filteredAndSorted.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: EmptyState(
                            icon: Icons.search_off,
                            title: viewState.contactsShowUnreadOnly
                                ? context.l10n.contacts_noUnreadContacts
                                : context.l10n.contacts_noContactsFound,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: filteredAndSorted.length,
                    itemBuilder: (context, index) {
                      final contact = filteredAndSorted[index];
                      final unreadCount = connector.getUnreadCountForContact(
                        contact,
                      );
                      return _ContactTileEntrance(
                        key: ValueKey(
                          'contact_delete_shortcut_${contact.publicKeyHex}',
                        ),
                        index: index,
                        contact: contact,
                        lastSeen: _resolveLastSeen(contact),
                        unreadCount: unreadCount,
                        isFavorite: contact.isFavorite,
                        isHighlighted:
                            contact.publicKeyHex ==
                            widget.highlightedContactPublicKeyHex,
                        onTap: () => _openChat(context, contact),
                        onLongPress: () =>
                            _showContactOptions(context, connector, contact),
                        onDelete: () =>
                            _confirmDelete(context, connector, contact),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  List<Contact> _filterAndSortContacts(
    List<Contact> contacts,
    MeshCoreConnector connector,
    UiViewStateService viewState,
  ) {
    var filtered = contacts.where((contact) {
      if (viewState.contactsSearchText.isEmpty) return true;
      return matchesContactQuery(contact, viewState.contactsSearchText);
    }).toList();

    final selectedGroup = _selectedGroupForName(
      viewState.contactsSelectedGroupName,
    );
    if (selectedGroup != null) {
      final memberKeys = selectedGroup.memberKeys.toSet();
      filtered = filtered
          .where((contact) => memberKeys.contains(contact.publicKeyHex))
          .toList();
    }

    // Filter out own node from the list
    if (connector.selfPublicKey != null) {
      final selfPubKeyHex = pubKeyToHex(connector.selfPublicKey!);
      filtered = filtered.where((contact) {
        return contact.publicKeyHex != selfPubKeyHex;
      }).toList();
    }

    if (viewState.contactsTypeFilter != ContactTypeFilter.all) {
      filtered = filtered
          .where(
            (contact) =>
                _matchesTypeFilter(contact, viewState.contactsTypeFilter),
          )
          .toList();
    }

    if (viewState.contactsShowUnreadOnly) {
      filtered = filtered.where((contact) {
        return connector.getUnreadCountForContact(contact) > 0;
      }).toList();
    }

    switch (viewState.contactsSortOption) {
      case ContactSortOption.lastSeen:
        filtered.sort(
          (a, b) => _resolveLastSeen(b).compareTo(_resolveLastSeen(a)),
        );
        break;
      case ContactSortOption.recentMessages:
        filtered.sort((a, b) {
          final aMessages = connector.getMessages(a);
          final bMessages = connector.getMessages(b);
          final aLastMsg = aMessages.isEmpty
              ? DateTime(1970)
              : aMessages.last.timestamp;
          final bLastMsg = bMessages.isEmpty
              ? DateTime(1970)
              : bMessages.last.timestamp;
          return bLastMsg.compareTo(aLastMsg);
        });
        break;
      case ContactSortOption.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case ContactSortOption.hops:
        filtered.sort((a, b) {
          final hops = _hopSortValue(a).compareTo(_hopSortValue(b));
          if (hops != 0) return hops;
          final lastSeen = _resolveLastSeen(b).compareTo(_resolveLastSeen(a));
          if (lastSeen != 0) return lastSeen;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
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

  bool _matchesTypeFilter(Contact contact, ContactTypeFilter typeFilter) {
    switch (typeFilter) {
      case ContactTypeFilter.all:
        return true;
      case ContactTypeFilter.favorites:
        return contact.isFavorite;
      case ContactTypeFilter.users:
        return contact.type == advTypeChat;
      case ContactTypeFilter.repeaters:
        return contact.type == advTypeRepeater;
      case ContactTypeFilter.rooms:
        return contact.type == advTypeRoom;
    }
  }

  DateTime _resolveLastSeen(Contact contact) {
    if (contact.type != advTypeChat) return contact.lastSeen;
    return contact.lastMessageAt.isAfter(contact.lastSeen)
        ? contact.lastMessageAt
        : contact.lastSeen;
  }

  void _openChat(BuildContext context, Contact contact) {
    // Check if this is a repeater
    if (contact.type == advTypeRepeater) {
      _showRepeaterLogin(context, contact);
    } else if (contact.type == advTypeRoom) {
      _showRoomLogin(context, contact, RoomLoginDestination.chat);
    } else {
      final connector = context.read<MeshCoreConnector>();
      final unread = connector.getUnreadCountForContactKey(
        contact.publicKeyHex,
      );
      connector.markContactRead(contact.publicKeyHex);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ChatScreen(contact: contact, initialUnreadCount: unread),
        ),
      );
    }
  }

  void _handleQuickSwitch(int index, BuildContext context) {
    if (index == 0) return;
    switch (index) {
      case 1:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const ChannelsScreen(hideBackButton: true)),
        );
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          buildQuickSwitchRoute(const MapScreen(hideBackButton: true)),
        );
        break;
    }
  }

  Future<void> _showRepeaterLogin(
    BuildContext context,
    Contact repeater,
  ) async {
    final session = await ensureRemoteNodeAuthenticated(
      context,
      contact: repeater,
    );
    if (!context.mounted || session == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RepeaterHubScreen(
          repeater: repeater,
          password: session.password,
          isAdmin: session.isAdmin,
        ),
      ),
    );
  }

  Future<void> _showRoomLogin(
    BuildContext context,
    Contact room,
    RoomLoginDestination destination,
  ) async {
    final session = await ensureRemoteNodeAuthenticated(context, contact: room);
    if (!context.mounted || session == null) return;
    final connector = context.read<MeshCoreConnector>();
    final unread = connector.getUnreadCountForContactKey(room.publicKeyHex);
    connector.markContactRead(room.publicKeyHex);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => destination == RoomLoginDestination.management
            ? RepeaterHubScreen(
                repeater: room,
                password: session.password,
                isAdmin: session.isAdmin,
              )
            : ChatScreen(contact: room, initialUnreadCount: unread),
      ),
    );
  }

  Future<void> _showContactTelemetry(
    BuildContext context,
    Contact contact,
  ) async {
    if (contactRequiresRemoteAuthentication(contact)) {
      final session = await ensureRemoteNodeAuthenticated(
        context,
        contact: contact,
      );
      if (!context.mounted || session == null) return;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TelemetryScreen(contact: contact),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context, ContactGroup group) {
    if (!_hasGroupStoreScope(context.read<MeshCoreConnector>())) {
      _showGroupsUnavailableMessage(context);
      return;
    }
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contacts_deleteGroup),
        content: Text(context.l10n.contacts_deleteGroupConfirm(group.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              setState(() {
                _groups.removeWhere((g) => g.name == group.name);
                _ensureValidSelectedGroup();
              });
              await _saveGroups();
            },
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showGroupEditor(
    BuildContext context,
    List<Contact> contacts, {
    ContactGroup? group,
  }) {
    if (!_hasGroupStoreScope(context.read<MeshCoreConnector>())) {
      _showGroupsUnavailableMessage(context);
      return;
    }
    final isEditing = group != null;
    final nameController = TextEditingController(text: group?.name ?? '');
    final selectedKeys = <String>{...group?.memberKeys ?? []};
    String filterQuery = '';
    final sortedContacts = List<Contact>.from(contacts)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          final filteredContacts = filterQuery.isEmpty
              ? sortedContacts
              : sortedContacts
                    .where(
                      (contact) => matchesContactQuery(contact, filterQuery),
                    )
                    .toList();
          return AlertDialog(
            title: Text(
              isEditing
                  ? context.l10n.contacts_editGroup
                  : context.l10n.contacts_newGroup,
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: context.l10n.contacts_groupName,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.l10n.contacts_filterContacts,
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          filterQuery = value.toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredContacts.isEmpty
                          ? Center(
                              child: Text(
                                context.l10n.contacts_noContactsMatchFilter,
                              ),
                            )
                          : ListView.builder(
                              itemCount: filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = filteredContacts[index];
                                final isSelected = selectedKeys.contains(
                                  contact.publicKeyHex,
                                );
                                return CheckboxListTile(
                                  value: isSelected,
                                  title: Text(contact.name),
                                  subtitle: Text(
                                    contact.typeLabel(context.l10n),
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedKeys.add(contact.publicKeyHex);
                                      } else {
                                        selectedKeys.remove(
                                          contact.publicKeyHex,
                                        );
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.l10n.common_cancel),
              ),
              TextButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.contacts_groupNameRequired),
                    );
                    return;
                  }
                  if (name.toLowerCase() ==
                      contactsAllGroupsValue.toLowerCase()) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(context.l10n.contacts_groupNameReserved),
                    );
                    return;
                  }
                  final exists = _groups.any((g) {
                    if (isEditing && g.name == group.name) return false;
                    return g.name.toLowerCase() == name.toLowerCase();
                  });
                  if (exists) {
                    showDismissibleSnackBar(
                      context,
                      content: Text(
                        context.l10n.contacts_groupAlreadyExists(name),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    final viewState = context.read<UiViewStateService>();
                    if (isEditing) {
                      final index = _groups.indexWhere(
                        (g) => g.name == group.name,
                      );
                      if (index != -1) {
                        final wasSelected =
                            viewState.contactsSelectedGroupName == group.name;
                        _groups[index] = ContactGroup(
                          name: name,
                          memberKeys: selectedKeys.toList(),
                        );
                        if (wasSelected) {
                          viewState.setContactsSelectedGroupName(name);
                        }
                      }
                    } else {
                      _groups.add(
                        ContactGroup(
                          name: name,
                          memberKeys: selectedKeys.toList(),
                        ),
                      );
                      viewState.setContactsSelectedGroupName(name);
                    }
                    _ensureValidSelectedGroup();
                  });
                  await _saveGroups();
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                child: Text(
                  isEditing
                      ? context.l10n.common_save
                      : context.l10n.common_create,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showContactOptions(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    final isRepeater = contact.type == advTypeRepeater;
    final isRoom = contact.type == advTypeRoom;
    final isFavorite = contact.isFavorite;

    showMeshSheet(
      context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(
              title: contact.name,
              subtitle: contact.typeLabel(context.l10n),
            ),
            if (isRepeater) ...[
              ListTile(
                leading: Icon(Icons.radar, color: MeshPalette.signal),
                title: Text(context.l10n.contacts_ping),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final hw = context
                      .read<MeshCoreConnector>()
                      .pathHashByteWidth;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PathTraceMapScreen(
                        title: context.l10n.contacts_repeaterPing,
                        path: _contactPathHashPrefix(contact, hw),
                        targetContact: contact,
                        pathHashByteWidth: hw,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.cell_tower, color: MeshPalette.warn),
                title: Text(context.l10n.contacts_manageRepeater),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRepeaterLogin(context, contact);
                },
              ),
            ] else if (isRoom) ...[
              ListTile(
                leading: Icon(Icons.radar, color: MeshPalette.signal),
                title: Text(context.l10n.contacts_pathTrace),
                onTap: () {
                  Navigator.pop(sheetContext);
                  final hw = context
                      .read<MeshCoreConnector>()
                      .pathHashByteWidth;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PathTraceMapScreen(
                        title: contact.pathBytesForDisplay.isNotEmpty
                            ? context.l10n.contacts_roomPathTrace
                            : context.l10n.contacts_roomPing,
                        path: contact.pathBytesForDisplay.isNotEmpty
                            ? contact.pathBytesForDisplay
                            : _contactPathHashPrefix(contact, hw),
                        flipPathAround: contact.pathBytesForDisplay.isNotEmpty,
                        targetContact: contact,
                        pathHashByteWidth: hw,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.meeting_room, color: MeshPalette.blue),
                title: Text(context.l10n.contacts_roomLogin),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRoomLogin(context, contact, RoomLoginDestination.chat);
                },
              ),
              ListTile(
                leading: Icon(Icons.room_preferences, color: MeshPalette.warn),
                title: Text(context.l10n.room_management),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRoomLogin(
                    context,
                    contact,
                    RoomLoginDestination.management,
                  );
                },
              ),
            ] else ...[
              if (contact.pathLength > 0)
                ListTile(
                  leading: Icon(Icons.radar, color: MeshPalette.signal),
                  title: Text(context.l10n.contacts_chatTraceRoute),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final hw = context
                        .read<MeshCoreConnector>()
                        .pathHashByteWidth;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PathTraceMapScreen(
                          title: context.l10n.contacts_pathTraceTo(
                            contact.name,
                          ),
                          path: contact.pathBytesForDisplay,
                          flipPathAround: true,
                          targetContact: contact,
                          pathHashByteWidth: hw,
                        ),
                      ),
                    );
                  },
                ),
            ],
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: Text(context.l10n.contact_telemetry),
              onTap: () {
                Navigator.pop(sheetContext);
                _showContactTelemetry(context, contact);
              },
            ),
            ListTile(
              leading: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: MeshPalette.warn,
              ),
              title: Text(
                isFavorite
                    ? context.l10n.listFilter_removeFromFavorites
                    : context.l10n.listFilter_addToFavorites,
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await connector.setContactFlags(
                  contact,
                  isFavorite: !isFavorite,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: Text(context.l10n.shareLink_copyShareLink),
              onTap: () {
                Navigator.pop(sheetContext);
                _copyContactShareLink(contact);
              },
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(context.l10n.nearbyNodes_copyPublicKey),
              onTap: () {
                Navigator.pop(sheetContext);
                copyPublicKeyHex(context, contact.publicKeyHex);
              },
            ),
            ListTile(
              leading: const Icon(Icons.connect_without_contact),
              title: Text(context.l10n.contacts_ShareContactZeroHop),
              onTap: () {
                Navigator.pop(sheetContext);
                _contactZeroHop(contact.publicKey);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                context.l10n.contacts_deleteContact,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmDelete(context, connector, contact);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    MeshCoreConnector connector,
    Contact contact,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contacts_deleteContact),
        content: Text(context.l10n.contacts_removeConfirm(contact.name)),
        actions: [
          TextButton(
            autofocus: PlatformInfo.isDesktop,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              connector.removeContact(contact);
            },
            child: Text(
              context.l10n.common_delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAllContacts(
    BuildContext context,
    MeshCoreConnector connector,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.contacts_deleteAllContacts),
        content: Text(context.l10n.contacts_deleteAllContactsConfirm),
        actions: [
          TextButton(
            autofocus: PlatformInfo.isDesktop,
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.common_cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              unawaited(connector.removeAllContacts());
            },
            child: Text(
              context.l10n.common_deleteAll,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;
  final DateTime lastSeen;
  final int unreadCount;
  final bool isFavorite;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ContactTile({
    required this.contact,
    required this.lastSeen,
    required this.unreadCount,
    required this.isFavorite,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  /// Node-type avatar color per design language.
  Color _avatarColor() {
    switch (contact.type) {
      case advTypeRepeater:
        return MeshPalette.warn;
      case advTypeRoom:
        return MeshPalette.magenta;
      case advTypeSensor:
        return const Color(0xFF4ACCC4); // teal
      default:
        return MeshPalette
            .blue; // chat — AvatarCircle handles deterministic hue
    }
  }

  /// Node-type avatar icon. Returns null for chat nodes so AvatarCircle shows initials.
  IconData? _avatarIcon() {
    switch (contact.type) {
      case advTypeRepeater:
        return Icons.cell_tower;
      case advTypeRoom:
        return Icons.meeting_room;
      case advTypeSensor:
        return Icons.sensors;
      default:
        return null; // chat uses initials
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emoji = firstEmoji(contact.name);
    final isChat = contact.type == advTypeChat;
    final routeHops = contact.pathOverride ?? contact.pathLength;
    final isDirect = routeHops >= 0;

    return GestureDetector(
      onSecondaryTapUp: PlatformInfo.isDesktop ? (_) => onLongPress() : null,
      child: MeshCard(
        borderColor: isSelected ? scheme.primary : null,
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Avatar
            if (emoji != null)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHigh,
                  border: Border.all(color: scheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: Text(emoji, style: const TextStyle(fontSize: 20)),
              )
            else
              AvatarCircle(
                name: contact.name,
                size: 42,
                color: isChat ? null : _avatarColor(),
                icon: _avatarIcon(),
              ),
            const SizedBox(width: 12),
            // Main content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Name row + route chip
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 15,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (isFavorite) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.star, size: 13, color: MeshPalette.warn),
                      ],
                      if (contact.hasLocation) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.location_on,
                          size: 13,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Path / subtitle row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          contact.pathLabel(context.l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (PlatformInfo.isDesktop) ...[
                        const SizedBox(width: 6),
                        RouteChip(
                          isDirect: isDirect,
                          hops: isDirect ? routeHops : null,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Trailing: time + unread badge
            // Clamp text scale to prevent overflow in trailing section.
            MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.3),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unreadCount > 0) ...[
                    UnreadBadge(count: unreadCount),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    _formatLastSeen(context, lastSeen),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: MeshTheme.mono(
                      fontSize: 11,
                      color: unreadCount > 0
                          ? MeshPalette.blue
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(BuildContext context, DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.isNegative || diff.inMinutes < 5) {
      return context.l10n.contacts_lastSeenNow;
    }
    if (diff.inMinutes < 60) {
      return context.l10n.contacts_lastSeenMinsAgo(diff.inMinutes);
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return hours == 1
          ? context.l10n.contacts_lastSeenHourAgo
          : context.l10n.contacts_lastSeenHoursAgo(hours);
    }
    final days = diff.inDays;
    return days == 1
        ? context.l10n.contacts_lastSeenDayAgo
        : context.l10n.contacts_lastSeenDaysAgo(days);
  }
}

// Wrap each contact tile with staggered entrance.
class _ContactTileEntrance extends StatelessWidget {
  final int index;
  final Contact contact;
  final DateTime lastSeen;
  final int unreadCount;
  final bool isFavorite;
  final bool isHighlighted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  const _ContactTileEntrance({
    super.key,
    required this.index,
    required this.contact,
    required this.lastSeen,
    required this.unreadCount,
    required this.isFavorite,
    this.isHighlighted = false,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListEntrance(
      index: index,
      child: DesktopDeleteShortcut(
        onDelete: onDelete,
        builder: (context, selected) => _ContactTile(
          contact: contact,
          lastSeen: lastSeen,
          unreadCount: unreadCount,
          isFavorite: isFavorite,
          isSelected: selected || isHighlighted,
          onTap: onTap,
          onLongPress: onLongPress,
        ),
      ),
    );
  }
}
