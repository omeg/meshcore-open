# Notifications

## Overview

MeshCore Open provides both **system notifications** (push-style OS alerts) and **in-app unread badges** to inform users of new activity.

## Notification Types

### 1. Direct Message Notifications
- **Triggered when**: A new incoming message arrives from a Chat or Room contact
- **Title**: Contact's name
- **Body**: Message text (reactions show "Reacted [emoji]", GIFs show "Sent a GIF")
- **Priority**: High
- **Android channel**: `messages`

### 2. Channel Message Notifications
- **Triggered when**: A new message arrives on a non-muted channel
- **Title**: Channel name (or "Channel N" if unnamed)
- **Body**: `"<senderName>: <message text>"`
- **Priority**: High
- **Android channel**: `channel_messages`

### 3. Advertisement Notifications
- **Triggered when**: A new node is discovered on the mesh for the first time
- **Title**: "New [type] discovered" (e.g., "New Chat discovered")
- **Body**: Contact's name
- **Priority**: Default
- **Android channel**: `adverts`

### 4. Background Service Notification (Android Only)
- A persistent low-priority notification: "MeshCore running — Keeping BLE connected"
- Required by Android for foreground services to keep BLE alive in the background
- Tap to re-launch the app
- **Does not auto-start on reboot** — the user must re-open the app manually after a phone restart

### 5. Firmware-Fork Telemetry Results

Telemetry-log fetch and InfluxDB import completion/failure can generate notifications when their screen has been closed. These belong to the telemetry-log integration that requires the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore), not ordinary live telemetry. See [Telemetry Logs, InfluxDB, and State Sync](telemetry-and-sync.md#firmware-fork-telemetry-logs-and-influxdb).

### Notification Tap Behavior

Tapping a notification currently re-launches the app at the root route. It does **not** navigate directly to the relevant chat or channel.

## In-App Unread Badges

Red numeric badges appear throughout the UI:
- **Contacts list**: Each contact row shows a red pill badge (e.g., "3") for unread messages
- **Channels list**: Each channel row shows an unread badge
- **Chat screen subtitle**: Shows unread count inline
- Badges cap at "9999+" for display

### How Unread Counts Work

- Stored per contact (by public key) and per channel, **scoped to the connected device's identity** (first 10 hex characters of its public key). Switching between different radios gives each its own independent unread state
- **Suppressed when viewing**: Opening a chat resets the count to 0 and cancels the OS notification
- **Ignored for**: Outgoing messages, CLI messages, and repeater contacts
- Debounced writes (500ms) to avoid excessive storage I/O during message bursts

## Notification Settings

Access via **App Settings → Notifications**:

| Setting | Default | Description |
|---|---|---|
| Enable Notifications | On | Master toggle; requests OS permission when turned on |
| Message Notifications | On | DM alerts (greyed out if master is off) |
| Channel Message Notifications | On | Channel alerts (greyed out if master is off) |
| Advertisement Notifications | On | New node alerts (greyed out if master is off) |

### Per-Channel Muting

Long-press a channel in the channels list → "Mute channel" / "Unmute channel". Muted channels do not generate OS notifications.

There is no per-contact muting.

## Rate Limiting

The notification system prevents notification storms:
- **Minimum interval**: 3 seconds between individual notifications
- **Batch window**: An event arriving within that 3-second interval is queued for 5 seconds. If exactly one event is queued, it is then shown as its normal notification. If two or more are queued, Android shows one summary on the `batch_summary` channel with grouped counts (for example, "2 messages, 1 channel message, 3 new nodes"). The multi-event summary has Android notification details only, so that batched group is not displayed as an OS alert on other platforms

## Notification Clearing

- **Opening a contact chat**: Cancels the OS notification and resets unread count
- **Opening a channel**: Cancels the channel notification and resets unread count
- **Opening Contacts screen**: Cancels all advertisement notifications

## Platform Support

The Badge column below refers to an operating-system/app-icon badge. The Contacts and Channels unread badges are part of the app UI and are available on every platform.

| Platform | System Notifications | OS/App Badge | Background Service |
|---|---|---|---|
| Android | Yes | Via notification number | Yes (foreground service) |
| iOS | Yes | Yes (app badge) | No |
| macOS | Yes | Yes | No |
| Windows | Yes | No | No |
| Linux | Yes (if D-Bus available) | No | No |
| Web | No | No | No |
