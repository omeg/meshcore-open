# Telemetry Logs, InfluxDB, and State Sync

This page covers two file-oriented workflows. Telemetry-log download and InfluxDB import are a single firmware-fork integration. State sync is an independent app feature.

## Firmware-fork telemetry logs and InfluxDB

> **Firmware requirement:** Everything in this section requires the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore). It is not part of the ordinary live Telemetry screen or the companion Radio Stats screen, and stock firmware may not answer telemetry-log requests.

The app can download a repeater's recorded sensor history, keep resumable `.telemetry` files, and optionally import the completed log into InfluxDB v2.

### Access and permissions

Authenticate to a repeater as an administrator, open its Repeater Hub, then choose **Telemetry Log**. The tile is admin-only. Fetching is a deliberate mesh operation and does not start merely by opening the screen.

### Fetch workflow

- **Fetch telemetry log** starts or resumes the current recording session.
- **Refresh** retrieves data appended since the last completed fetch.
- **Re-fetch from start** ignores saved progress and starts at byte zero.
- **Chunk size** controls the bytes requested per mesh round trip, from 1 to 136. Smaller chunks may be more reliable on weak routes.
- **Restart log after completed fetch** asks an actively logging repeater to discard the fetched device-side log and begin a fresh one only after a complete pull.
- **Status** sends `tlog status` and displays the repeater's raw status response without beginning a download.
- **Cancel** stops the fetch promptly. Completed record boundaries are persisted so a later fetch can resume cleanly.

Only one telemetry-log fetch can run at a time, but it continues if the screen is closed. The app posts a completion/failure notification when no telemetry-log screen is observing it. A non-response can mean the repeater is offline, out of range, or lacks the firmware-fork support.

After decoding, the screen shows the session interval, time range, current value per recorded channel/type, and up to the 100 most recent sample rows. Saved sessions can be shared/exported, imported to InfluxDB, or deleted.

### Files and export

Completed and partial sessions are stored in the app's telemetry-log directory as `.telemetry` data with resume/import metadata. Platform behavior differs:

- **Android:** App Settings can remember a Storage Access Framework folder. Successful fetches are copied there automatically, making cross-device resume possible when the folder is shared.
- **Desktop:** App Settings shows and opens the app's telemetry-log storage folder. Individual logs can also be exported to another folder.
- **iOS:** Logs can be handed to the system share sheet.
- **Web:** Telemetry-log file management is unavailable.

### InfluxDB v2

Configure **App Settings → Telemetry Log → InfluxDB** with a base URL, API token, organization, bucket, and optional retention duration, then use **Test connection**. HTTP and HTTPS URLs are accepted; HTTPS is strongly recommended whenever the server is not strictly local.

When configured:

- Every successful fetch automatically imports new records.
- A saved log can be imported manually from its menu.
- Import progress is incremental; an unchanged session reports that InfluxDB is already up to date.
- The app creates the configured bucket when it does not exist. The retention value applies during that creation; it does not rewrite an existing bucket's policy.
- Points use the `telemetry` measurement and identify the repeater by its full public key.
- Import success/failure can generate a system notification when the telemetry-log screen is closed.

The API token is stored in app settings. If State Sync is enabled, those settings—including the token—are present in the sync JSON. Protect both the selected folder and any backups of it.

## State sync

State sync is supported on Android, Linux, Windows, and macOS. It is unavailable on iOS and web.

Choose a folder under **App Settings → Sync**. The app imports a compatible bundle for the current companion identity, merges it with local state, and then automatically exports changes after a two-second debounce. It flushes pending work during normal app lifecycle/desktop exit handling. The filename is:

```text
meshcore-open-state-<first-10-public-key-hex>.json
```

The bundle contains app settings, contacts, discovered contacts, direct and channel messages, channels and their order, contact groups, and per-contact/channel SMAZ, Cyr2Lat, and region preferences. Merge logic preserves local unread counts and reconciles conversations instead of blindly replacing the entire local store.

It deliberately excludes communities, the standalone `pending_messages` store, unread-count storage, repeater passwords, per-repeater auto-clock-sync settings, and the sync configuration itself. Conversation records retain their stored status fields, so a pending entry already in direct or channel history can still be present in the bundle.

MeshCore Open reads and writes the chosen folder but does not provide a cloud backend. To hand state between devices, select a folder managed by your own filesystem or synchronization provider. The bundle is readable JSON and is not encrypted by the app; anyone or any provider with access to that folder may see message history, channel secrets, public identities, location-bearing records, and app settings such as an InfluxDB token.

**Forget sync folder** disables the feature and forgets access in the app. It leaves existing files in the folder.
