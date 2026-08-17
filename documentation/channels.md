# Channels

## Overview

Channels are broadcast group-chat spaces secured by a 16-byte pre-shared key (PSK). Any device that stores the same PSK in one of its local channel slots can receive and decrypt the traffic; channel indexes do not need to match between devices. Unlike direct messages, channel messages use flood routing across the mesh, optionally constrained by a selected region scope.

The number of active channels is determined by the firmware (default 40); the device reports its actual limit at login.

## How to Access

QuickSwitchBar tab 1 (middle) from any main screen.

## Channel Types

| Type | Icon | Color | Description |
|---|---|---|---|
| Public | Globe | Green | Fixed well-known PSK; any device can join |
| Hashtag | Hash tag | Blue | PSK derived from the hashtag name via SHA-256; discoverable by convention |
| Private | Lock | Blue | Random PSK; requires out-of-band sharing of the 32-hex key |
| Community | Groups/Tag | Magenta | PSK derived via HMAC-SHA256 from a community's shared secret |

## Channels List Screen

### What the User Sees

- **Search bar** with live text filtering (300ms debounce)
- **Sort/filter button**
- **Scrollable list of channel cards**, each showing:
  - Type icon with color coding (magenta badge overlay for community channels)
  - Channel name (or "Channel N" if unnamed)
  - Unread badge (if messages are unread)
  - Drag handle (when manual sort is active)
- **"+" FAB** to add a new channel
- **Overflow menu**: Nearby Nodes, Discovered Contacts, Manage Communities (when any exist), Disconnect, and Settings

If no channels exist, an empty state with an "Add Public Channel" shortcut is shown. If a search produces no results, a separate "no results" empty state with a search-off icon is shown.

Pull-to-refresh (swipe down) forces a re-fetch of channels from the device firmware.

### Sorting Options

- **Manual** (default): Drag-and-drop reordering, persisted (drag handles are hidden when a search query is active)
- **A–Z**: Alphabetical
- **Latest messages**: Most recent first
- **Unread**: Most unread first

## Adding a Channel

Tap the "+" FAB to open a dialog with six options:

1. **Create Private Channel** — Enter a name (max 31 characters); a random PSK is generated
2. **Join Private Channel** — Enter a name and a 32-hex PSK (non-hex characters like spaces and dashes are silently stripped, so pasted keys with formatting are accepted)
3. **Join Public Channel** — One tap; uses the well-known public PSK (only shown if no public channel exists)
4. **Join Hashtag Channel** — Enter a hashtag name; PSK is derived from the name. If communities exist, choose between regular hashtag (SHA-256) or community hashtag (HMAC)
5. **Scan Community QR** — Opens QR scanner to join a community
6. **Create Community** — Enter a name; generates a random 32-byte secret; optionally adds a community public channel; shows QR code for sharing

## Channel Actions (Long-Press / Right-Click)

| Action | Description |
|---|---|
| Edit | Change name, PSK (with a dice icon to generate a random PSK), SMAZ compression toggle (compresses outgoing messages to allow longer text within the byte limit), or Cyr2Lat encoding toggle (transliterates Cyrillic to Latin for compatibility) |
| Copy Share Link | Copies a channel link containing its name, 16-byte secret, and optional region scope |
| Mute / Unmute | Toggle push notification suppression for this channel |
| Delete | Remove the channel from the device (confirmation required) |

## Channel Chat

Tap a channel card to open the channel chat screen.

### App Bar

- Type icon: globe for public channels, tag (#) for all other channel types
- Channel name
- Subtitle: "{Public|Private} • {N} unread" plus the selected region scope, when set
- Region button (or tapping the title): choose/clear a stored region or open Region Management. The choice is saved per channel and scopes subsequent flood traffic

### Message Display

- Reverse-scrolling list (newest at bottom)
- **Incoming messages**: Colored avatar with sender's initial (or first emoji if name starts with one; color is deterministic from sender name hash), sender name in primary color, message bubble
- **Outgoing messages**: Primary container color bubble with a small status icon: pending (clock), sent (checkmark), or failed (red error circle)
- **Flood scope**: Scoped messages show their saved region below the content. Incoming raw packets are matched against known regions; an unresolved scoped packet shows its raw transport tag instead
- Automatic older-message loading on scroll-to-top
- Jump-to-bottom button when scrolled up
- **Pinch-to-zoom**: Two-finger zoom (0.8x–1.8x) and double-tap to reset text size
- **Message tracing mode** (when enabled in App Settings): Each bubble additionally shows path prefix bytes (`via XX,YY,...`), a timestamp, and a repeat count icon

### Message Types in Chat

- **Plain text** with linkified URLs
- **GIFs** (`g:{gifId}`) rendered inline via Giphy CDN
- **Location pins** (`m:{lat},{lon}|{label}|`) shown as tappable location cards
- **Reactions** displayed as emoji pills below target messages

The composer provides GIF and optional translation controls, plus a desktop emoji picker. Trailing whitespace is removed before sending, and whitespace-only messages are ignored.

### Replies (Channel Chat Only)

- **All platforms**: Long-press/right-click → "Reply"
- **Browser build**: An incoming message can also be swiped left to reply. Swipe-to-reply is disabled in the native mobile and desktop builds.
- Reply banner appears above the input bar with the quoted message (tap X to cancel)
- Sent replies are prefixed `@[{senderName}] {text}`
- Replies sent on this device show a bordered quote block inside the bubble; tapping scrolls to the original. Reply previews render GIF thumbnails and location pin icons, not just text.
- The on-air prefix contains a sender name but no message identifier. Received replies therefore show the addressee and "Original message not found" instead of guessing from a companion's potentially incomplete history.

### Message Path Viewing

- **All platforms**: Long-press (or right-click on desktop) a message bubble → "Path"
- Opens the Channel Message Path Screen (see [Additional Features](additional-features.md))

### Context Actions (Long-Press / Right-Click)

| Action | Availability | Description |
|---|---|---|
| Reply | All messages | Triggers reply mode |
| Path | All messages | Opens message path view |
| Copy Path | Messages with path data | Copies hop prefixes using the message's recorded hash width |
| Add Reaction | Incoming messages only | Opens emoji picker (cannot react to your own messages) |
| Copy | All messages | Copies text to clipboard |
| Translate | Incoming messages only, when translation is enabled | Runs on-device translation |
| Mark as Unread | Incoming messages only | Marks this message and all subsequent incoming messages as unread |
| Resend Message | Outgoing messages | Sends the content as a new channel message |
| Delete | All messages | Removes locally (not from mesh) |

## Channel share links

The copied format is:

```text
meshcore://channel/add?name=<encoded-name>&secret=<32-hex>&region_scope=<encoded-region>
```

`region_scope` is omitted when no scope is selected. A received link opens a preview and requires an available companion channel slot before it can be added. For private channels, the receiver can edit the displayed name before import.

The `secret` parameter is the channel's PSK. Anyone who receives the link can decrypt and transmit on that channel, so treat private and community channel links as sensitive credentials.

## Communities

Communities are a layer above channels that provide a private namespace.

### What is a Community?

A community has a name and a 32-byte random secret. Channel PSKs are derived from this secret:
- **Public channel**: `HMAC-SHA256(secret, "channel:v1:__public__")[:16]`
- **Hashtag channel**: `HMAC-SHA256(secret, "channel:v1:{hashtag}")[:16]`

Outsiders who don't know the secret cannot discover or join community channels.

### Sharing a Community

Communities are shared via QR codes containing a JSON payload:
```json
{"v": 1, "type": "meshcore_community", "name": "...", "k": "<base64url-secret>"}
```

### Managing Communities

From the channels screen overflow menu → "Manage Communities". Opens a draggable scrollable sheet (resizable 30–90% of screen height):

- Each community shows its name and a short community ID (first 8 hex characters)
- **Tap a community** to directly show its QR code for sharing
- **Popup menu** per community:
  - **Show QR** — displays the QR code for sharing with new members
  - **Leave Community** — removes the community locally and deletes all associated device channels (confirmation dialog warns how many channels will be removed)

## How Channels Differ from Direct Messages

| Aspect | Channels | Direct Messages |
|---|---|---|
| Addressing | Broadcast to all nodes with matching PSK | Point-to-point to a specific contact |
| Encryption | Shared PSK (symmetric) | Contact's public key (asymmetric) |
| Sender identity | Plain text prefix in payload | Verified via public key |
| Replies | Supported from the context menu; browser swipe is optional | Not supported |
| Retry mechanism | No automatic retry | Exponential backoff with path rotation |
