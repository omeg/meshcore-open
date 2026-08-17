# Contacts

## Overview

The Contacts screen is the main place for finding and managing mesh nodes known to the connected companion radio. A contact is a node whose signed advertisement has been imported or automatically added. Contacts can be chat users, repeaters, room servers, or sensors.

Discovered Contacts and Nearby Nodes are related but separate views:

- **Contacts** is the companion radio's active contact list.
- **Discovered Contacts** is an app-side, persisted list of advertisements heard over time but not currently in Contacts.
- **Nearby Nodes** is a temporary active scan for repeaters that answer a zero-hop discovery request.

## How to access

- Choose the leftmost **Contacts** destination in the QuickSwitchBar from Channels or Map.
- Return to Contacts with back navigation after opening a contact chat, repeater screen, or Settings from Contacts.

## Contact types

| Type | Avatar | Description |
|---|---|---|
| Chat | Initials, or a leading emoji from the name | Another user's mesh radio |
| Repeater | Amber cell-tower icon | A mesh repeater or relay node |
| Room | Magenta meeting-room icon | A room server used for group chat |
| Sensor | Teal sensor icon | A sensor device |

## Contact list

Each contact row shows:

- A type-specific avatar, or the first emoji in the contact name when present
- The contact name
- A route label such as **Direct**, a hop count, or **Flood**, including forced-route variants when an override is active
- An amber star when the contact is a favorite
- A location pin when the contact advertises coordinates
- An unread-count badge when unread messages exist
- A relative last-seen time; for chat contacts, the app uses whichever is newer: the last advertisement or the last message
- A separate route chip on desktop

The full or shortened public key is not shown in the normal Contacts row. It remains searchable, is available in contact information, and is included in copied share links.

Pull down on the list to fetch the complete contact list from the companion again.

## Search, sort, and filter

Tap the search icon to expand the search field. Search matches a contact name case-insensitively or a hexadecimal public-key prefix. A key search may optionally begin with `0x` or `<`; spaces are ignored. Input is debounced by 300 ms.

The filter menu provides these sort orders:

- **Latest Messages**: most recent message first
- **Heard Recently**: most recent last-seen/message time first
- **A–Z**: contact name
- **Hops**: lowest known route hop count first, then recency and name; unknown or flood routes appear last

It also provides **All**, **Favorites**, **Users**, **Repeaters**, and **Room Servers** type filters. **Unread Only** is an independent toggle and can be combined with the selected type and group filters. Sensors appear under **All**; there is no sensor-only filter.

## Contact groups

Groups are a client-side organizational feature. They do not create mesh rooms, alter the companion's contact records, or send anything to other nodes.

- **Create a group**: Open the group dropdown, choose the add-group icon beside **All**, enter a name, select members, and choose **Create**.
- **Edit a group**: Open the group dropdown and choose the pencil beside the group.
- **Delete a group**: Open the group dropdown and choose the trash icon beside the group, then confirm.
- **Filter by group**: Select the group in the dropdown. The type, unread, and search filters still apply.

The member picker has its own name/public-key search. A newly created group becomes the active filter. Group names must be non-empty, must be unique without regard to case, and cannot be `all` in any letter case.

Groups are stored separately for each companion identity, using its public key as the scope. Group management is unavailable until the connected companion's identity is known.

## Tap actions

| Contact type | Action on tap |
|---|---|
| Chat / Sensor | Opens direct chat and marks that conversation read |
| Repeater | Authenticates if necessary, then opens the Repeater Hub |
| Room | Authenticates if necessary, then opens the room chat |

Repeater and room authentication can reuse a valid remembered session; it does not necessarily prompt for a password every time.

## Long-press and right-click actions

Long-press a row, or right-click it on desktop, to open the actions that apply to that node.

| Action | Availability | Behavior |
|---|---|---|
| Ping | Repeaters | Opens the path-trace map targeting the repeater |
| Path Trace / Ping | Rooms | Uses the known path when available; otherwise targets the room directly |
| Path Trace | Chat / Sensor with a known multi-hop path | Opens the path-trace map with the current path |
| Manage Repeater | Repeaters | Authenticates if necessary and opens the Repeater Hub |
| Room Login | Rooms | Authenticates if necessary and opens room chat |
| Room Management | Rooms | Authenticates if necessary and opens the management hub |
| Telemetry | All types | Opens the ordinary live telemetry request screen; repeaters and rooms authenticate first |
| Add/Remove Favorite | All types | Updates the favorite flag on the companion |
| Copy Share Link | All types | Copies a structured contact link to the clipboard |
| Share Contact Zero-Hop | All types | Broadcasts that contact's advertisement to directly reachable nodes |
| Delete Contact | All types | After confirmation, removes the contact from the companion and clears its local conversation |

The live **Telemetry** action above is separate from recorded telemetry-log download and InfluxDB import, which require the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore) and are documented in [Telemetry Logs, InfluxDB, and State Sync](telemetry-and-sync.md#firmware-fork-telemetry-logs-and-influxdb).

On desktop, selecting a row and pressing Delete also opens the delete confirmation.

## App-bar menu and add shortcut

The Contacts three-dot menu contains:

- **Nearby Nodes**
- **Discovered Contacts**
- **Add Contact from Clipboard**
- **Zero-Hop Advert**, which broadcasts your own advertisement to directly reachable nodes
- **Flood Advert**, which broadcasts your own advertisement across the mesh
- **Copy Self Share Link**, enabled after the companion's public key and name are known
- **Delete All Contacts**, enabled when Contacts is not empty and requiring confirmation
- **Disconnect**
- **Settings**

The person-add floating button is a shortcut sheet for **Add Contact from Clipboard** and **Discovered Contacts**.

Deleting all contacts removes them one at a time from the companion and clears their local conversations. Deleted contacts can still remain or reappear in Discovered Contacts when their advertisements are known.

## Adding contacts

### Automatic addition

When the companion hears an advertisement, it can automatically add the node according to **Settings → Contact Settings**. Users, repeaters, room servers, and sensors have independent auto-add switches. The **Overwrite Oldest** option allows the companion to replace its oldest record when its contact capacity is full.

Advertisements that are not auto-added can still be retained in Discovered Contacts.

### Import from the clipboard

Choose **Add Contact from Clipboard** from the overflow menu or the person-add shortcut. The app reads a supported contact link from the clipboard, validates it, and imports the contact to the companion. Empty, malformed, channel, or otherwise unsupported clipboard content is rejected.

### Import from Discovered Contacts

Open **Discovered Contacts**, then tap a row or use its action sheet. The tap behavior is configurable under **App Settings → Messaging → Discovered contact tap**:

- **Import contact** imports immediately and offers an Undo action in the confirmation message.
- **Show actions** opens the add/copy/delete sheet first.

## Discovered Contacts

Discovered Contacts stores advertisements heard by the app even when the nodes are not in the companion's contact list. The data is persisted separately for each companion identity and filters out the companion itself and nodes already present in Contacts.

Each row shows the node avatar and name, shortened public key, last-seen time, location and raw-advert indicators when available, and route state.

The screen provides:

- Name or public-key-prefix search with a 300 ms debounce
- **Heard Recently**, **A–Z**, and **Hops** sort orders
- **All**, **Users**, **Repeaters**, and **Room Servers** filters
- Long-press/right-click actions to add the contact, copy its structured share link, or remove it from discovery
- Desktop Delete-key removal for the selected row
- A confirmed **Delete All** action for the discovery list

Sensors appear under **All** because the discovery screen has no sensor-only filter. Hops sorting places unknown/flood routes last. Discovered-contact removal changes only the app-side discovery record; importing adds the node to the companion's contact list.

## Nearby Nodes

**Nearby Nodes** starts automatically when the screen opens and listens for 15 seconds. Refresh or pull to refresh starts another request after the current discovery window ends.

The request is zero-hop and only accepts repeater responses. Results are ordered by strongest RSSI and show:

- A known contact name when the full public key matches a stored contact, otherwise **Unknown Repeater**
- The full 64-character public key
- RSSI in dBm
- SNR with a signal-quality indicator

Tap a result to copy its full public key. Nearby Nodes is an active, temporary proximity check; it does not import a contact and is not the persisted history shown by Discovered Contacts.

## Contact sharing format

New contact links use a structured URI:

```text
meshcore://contact/add?name=<encoded-name>&public_key=<64-hex>&type=<number>
```

The app also accepts:

- Legacy business-card links containing a raw hexadecimal advertisement: `meshcore://<hex-encoded-advertisement>`
- Compact contact strings: `<64-hex-public-key:type:name>`
- The older compact variant with one extra field before `type`

A structured or compact link contains a public identity, contact type, and descriptive name; it does not contain a private identity key. A legacy advertisement may also carry signed public metadata such as location.

Contact links found in messages open a preview before import. See [Channels](channels.md#channel-share-links) for the separate channel-link format.
