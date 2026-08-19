# Settings

## How to Access

- From Contacts, Channels, or Map: overflow menu (three-dot) → Settings

Settings are only accessible while a device is connected.

## Settings Screen Layout

The settings screen is a scrollable list of cards:

1. [Device Info](#device-info)
2. [Identity](#identity)
3. [Node Settings](#node-settings)
4. [Location](#location)
5. [App Settings](#app-settings) (link to sub-screen)
6. [Actions](#actions)
7. [Export](#export)
8. [Debug](#debug)
9. [About](#about)

---

## Device Info

A collapsible card showing read-only device information. **Collapsed by default** — tap the header to expand with an animated chevron indicator:

| Field | Description |
|---|---|
| Name | Connected device's display name |
| ID | Device identifier |
| Firmware Version | Companion firmware version, when reported |
| Status | Connected / Disconnected |
| Battery | Percentage or voltage (tap to toggle) |
| Uptime | Time since the companion was last booted (firmware v8+) |
| Node Name | The node's mesh identity name |
| Contacts Count | Number of known contacts |
| Channel Count | Number of configured channels |

Battery shows an alert icon and orange text when at 15% or below. The toggle only works when millivolt data is available from the firmware.

---

## Identity

Shows the companion's full public key and provides two identity actions:

- **Copy Self Share Link**: Copies a contact link for the current public identity
- **Change Identity**: Imports a complete 64-byte MeshCore private identity key (128 hexadecimal characters). The firmware validates and persists the key, then the app copies identity-scoped data into the new public-key storage scope

Changing the identity changes the node's public key, so other nodes must rediscover it. Messages, contacts, discovered contacts, channels, groups, communities, unread state, and per-contact/channel preferences are copied into the new identity scope. The old identity's copy is retained, and data already stored for a previously used destination identity is not overwritten. Firmware builds with private-key import disabled reject the operation without changing the identity.

---

## Node Settings

These settings are sent directly to the connected device firmware.

### Node Name
- Opens a dialog with a text field (max 31 characters)
- Sends the new name to the device
- Confirmed via snackbar

### Radio Settings
Opens a dialog pre-populated with the device's current radio settings. Contains:
- **Preset dropdown**: Regional presets — selecting a preset immediately fills all fields below. Includes presets for Australia, Australia (Narrow), Australia SA WA QLD, Czech Republic, EU 433MHz, EU/UK (Long Range), EU/UK (Medium Range), EU/UK (Narrow), New Zealand, New Zealand (Narrow), Portugal 433, Portugal 869, numerous Russia city presets, Switzerland, USA Arizona, USA/Canada, Vietnam, and Off-Grid 433/869/918
- **Frequency** (MHz): Free text, validated 300–2500 MHz
- **Bandwidth**: Dropdown (7.8 / 10.4 / 15.6 / 20.8 / 31.25 / 41.7 / 62.5 / 125 / 250 / 500 kHz)
- **Spreading Factor**: SF5–SF12
- **Coding Rate**: 4/5, 4/6, 4/7, 4/8
- **TX Power** (dBm): Validated 0 to device max (typically 22 dBm)
- **Client Repeat** toggle: Only shown on firmware v9+; requires frequency to be exactly 433.000, 869.000, or 918.000 MHz (the Off-Grid presets). Save is blocked with a warning if enabled on other frequencies

### Path Hash Size
Selects 1-, 2-, or 3-byte public-key prefixes per route hop. Larger prefixes reduce hash collisions but reduce the 64-byte route field to 64, 32, or 21 hops respectively. The control is enabled only when supported by the companion. Use more than one byte only when every node that must forward the traffic runs firmware v1.14 or newer.

### Regions
Opens Region Management, where stored region definitions can be created, removed, and fetched from repeaters. Regions can be assigned to channel messages to constrain flood scope.

### Companion Radio Stats
Opens the paired radio's RF statistics screen: noise floor, latest RSSI/SNR, transmit/receive airtime, and a rolling noise-floor chart of up to 120 one-second samples. It requires companion firmware v8 or newer.

### Companion Telemetry
Requests the companion radio's current battery and connected-sensor readings. This live view is distinct from the firmware-fork telemetry-log workflow described in [Telemetry Logs, InfluxDB, and State Sync](telemetry-and-sync.md).

---

## Location

### Location
Opens a dialog pre-populated with the device's current coordinates (if known):
- Latitude and longitude fields (decimal, 6 decimal places). If only one field is provided, the other uses the device's current value
- **Show on map** opens the map centered on the entered coordinates, or the device's current coordinates when the fields are empty
- If GPS-capable hardware (detected via `gps` custom variable):
  - GPS Update Interval (seconds, 60–86399, default 900 = 15 minutes). Validated and sent separately before lat/lon
  - Enable GPS toggle (takes effect immediately, not deferred to Save)
- Validation: lat ±90, lon ±180

### Contact Settings
Five toggles controlling which node types are auto-added when heard:
- Auto-add Chat Users
- Auto-add Repeaters
- Auto-add Room Servers
- Auto-add Sensors
- Overwrite Oldest (when contact list is full)

### Privacy
Opens a dialog with controls for how the node shares telemetry and location data:
- **Advert Location**: Toggle whether the node broadcasts its location in advertisements
- **Multi-Ack**: Toggle multi-ack delivery confirmations
- **Telemetry Base Mode**: Deny All / Allow by Contact / Allow All
- **Telemetry Location Mode**: Deny All / Allow by Contact / Allow All
- **Telemetry Environment Mode**: Deny All / Allow by Contact / Allow All

Settings take effect when saved. A snackbar confirms the update.

---

## App Settings

A dedicated sub-screen for app-level preferences (nothing here is sent to the device). Preferences use local app storage; features such as map caching, translation, telemetry logs, and state sync also write files.

### Appearance
- **Theme**: System / Light / Dark
- **Language**: System default or one of 18 languages (English, French, Spanish, German, Polish, Slovenian, Portuguese, Italian, Chinese, Swedish, Dutch, Slovak, Bulgarian, Russian, Ukrainian, Hungarian, Japanese, Korean)

### Notifications
- **Master enable/disable**: Requests OS permission when enabling
- **Message notifications**: New direct message alerts
- **Channel message notifications**: New channel message alerts
- **Advertisement notifications**: New node discovery alerts

### Messaging
- **Clear Path on Max Retry**: Erases the stored routing path after all retries fail
- **Jump to Oldest Unread**: When opening a chat, scrolls to the oldest unread message instead of the newest
- **Auto Route Rotation**: Enables weighted routing algorithm. When enabled, expands to show five slider sub-settings (hidden when off):
  - Max Route Weight (1–10, default 5, integer steps)
  - Initial Route Weight (0.5–5.0, default 3.0)
  - Success Increment (0.1–2.0, default 0.5, 0.1 steps)
  - Failure Decrement (0.1–2.0, default 0.2, 0.1 steps)
  - Max Message Retries (2–10, default 5)
- **Enable Message Tracing**: Shows path trace overlays and extra metadata on messages
- **Discovered Contact Tap**: Choose whether a tap imports the node immediately or first displays its action sheet

### Sync
Automatic folder handoff is available on Android and desktop. After the user selects a folder, the app imports compatible state for the current identity and writes an identity-scoped `meshcore-open-state-<scope>.json` bundle after changes. A cloud-synced folder can be used to hand state to another installation, but MeshCore Open itself does not upload it.

The bundle includes app settings, contacts, discovered contacts, conversations, channels, ordering, groups, and per-contact/channel encoding and region preferences. Communities, the standalone pending-send store, unread counts, repeater passwords, auto-clock-sync preferences, and state-sync configuration are excluded. Conversation records retain their stored status fields, including any pending entries already present in conversation history. The JSON is not app-encrypted; app settings can include an InfluxDB API token. Choose the folder and its sharing policy accordingly. See [Telemetry Logs, InfluxDB, and State Sync](telemetry-and-sync.md#state-sync).

### Firmware-Fork Telemetry Log and InfluxDB
On native platforms, this section selects the Android export folder, opens the desktop log-storage folder, and configures InfluxDB v2. Telemetry-log download and InfluxDB import require the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore); they are documented together in [Telemetry Logs, InfluxDB, and State Sync](telemetry-and-sync.md#firmware-fork-telemetry-logs-and-influxdb).

### Battery
- **Battery Chemistry**: NMC / LiFePO4 / LiPo (per device, used to calibrate percentage from voltage)

### Map Display
- **Show Repeaters**: Toggle repeater markers on map
- **Show Users**: Toggle user markers
- **Show Other Nodes**: Toggle room/sensor markers
- **Time Filter**: All time / Last 1h / Last 6h / Last 24h / Last week
- **Units**: Metric / Imperial
- **Offline Map Cache**: Navigate to tile download screen

### Translation
Not shown on web. Controls on-device message translation powered by a locally-downloaded ML model:
- **Enable Translation**: Master switch that exposes translation controls in chats
- **Auto-translate Incoming Messages**: Automatically translates eligible incoming messages into the selected target language
- **Translate Composer**: Translates outgoing messages from the target language back before sending
- **Target Language**: Language to translate into (searchable list; defaults to the app language)
- **Downloaded Model**: Dropdown to select among already-downloaded translation models
- **Preset Model**: Download a curated preset model with one tap
- **Custom Model URL**: Enter a URL to download a custom GGUF-format model; shows download progress and a cancel button

### Cyrillic-to-Latin (Cyr2Lat)
Controls character-substitution profiles used to encode outgoing Cyrillic text as Latin characters. A dropdown selects the active profile; Add, Edit, and Delete buttons manage the profile list (the last remaining profile cannot be deleted). Each profile stores a JSON character map.

### Debug
- **App Debug Logging**: Enable the in-app debug log

---

## Actions

One-tap device operations:

| Action | Description |
|---|---|
| Sync Time | Sends current Unix timestamp to the device |
| Refresh Contacts | Re-requests the full contact list |
| Reboot Device | Confirmation dialog → reboots the device (shown in warning color) |
| Delete All Paths | Confirmation dialog → clears all stored routing paths (shown in alert color) |

---

## Export

Three GPX export options (not available on web):

| Option | Exports |
|---|---|
| Export Repeaters | Repeaters and Rooms with GPS coordinates |
| Export Contacts | Chat contacts with GPS coordinates |
| Export All | All contacts with GPS coordinates |

Each creates a `.gpx` file and opens the OS share sheet. Feedback via snackbar for four outcomes: success, no contacts with coordinates, feature not available (web), or error.

---

## Debug

Two log viewers accessible via list tiles:

### BLE Debug Log
Two views (togglable via segmented button):
- **Frames view**: Direction icon, description, hex preview, timestamp per frame. Long-press to copy hex.
- **Raw Log RX view**: Decoded LoRa packets with route type, payload type, path, and summary.
- Copy-all and Clear buttons in the app bar.

### App Debug Log
Structured log entries (Info / Warning / Error), with tag, message, and timestamp.
- Must be enabled first in App Settings → Debug
- Copy-all and Clear buttons

---

## About

Shows the standard Flutter about dialog with app name, version, and legal notice.
