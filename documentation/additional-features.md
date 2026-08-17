# Additional Features

## GIF Picker (Giphy Integration)

### How to Access
In any chat screen (direct or channel), tap the GIF button in the message input bar.

### What the User Sees
A bottom sheet with a search field and a grid of GIF thumbnails.

### Key Interactions
- On open, loads trending GIFs (G-rated, 25 results)
- Type to search and press the keyboard submit button (search triggers on submit, not on each keystroke). Clearing the search field reloads trending GIFs
- On network/API errors, a "Retry" button is shown in-place
- Tap a GIF to select it — the chat input shows an inline preview with an X button to dismiss
- Send the message to transmit the GIF reference (`g:<giphy-id>`)
- Recipients see the GIF rendered inline via Giphy CDN
- "Powered by Giphy" attribution is always shown at the bottom of the picker
- The bottom sheet occupies 70% of screen height

---

## Localization / Multi-Language Support

### How to Access
App Settings → Appearance → Language

### Supported Languages (18)
English, French, Spanish, German, Polish, Slovenian, Portuguese, Italian, Chinese, Swedish, Dutch, Slovak, Bulgarian, Russian, Ukrainian, Hungarian, Japanese, Korean

### How It Works
- All UI strings go through Flutter's ARB localization system
- Language can follow the system locale or be explicitly overridden
- Changes take effect immediately

---

## Discovered Contacts Screen

### How to Access
From the Contacts, Channels, or Map overflow menu → "Discovered Contacts"

### What the User Sees
A list of nodes heard passively over the air but not yet added as contacts. Each shows:
- Color-coded avatar (by type)
- Name
- Short public key
- Last-seen time
- Route/hop state

### Key Interactions
- Search bar with debounced filtering
- Sort by last seen, name, or hops; filter by type
- **Tap**: Import the contact or show the action sheet, according to **App Settings → Messaging → Discovered contact tap**
- **Long-press**: Add Contact, Copy `meshcore://` URI to clipboard, or Delete
- Overflow menu → "Delete All" (with confirmation)
- Already-known contacts and your own node are filtered out

---

## Direct-Repeater SNR Indicator

The connected-screen app bar shows an SNR summary derived from raw received packets. It selects the directly heard repeater with the highest observed packet count and shows average SNR, its multibyte hash prefix, the number of observed direct repeaters, and the age of the latest sample.

Tap it to open the full list, ordered by packet count. Each row shows the matched repeater name when known, direct/observed path information, sample count, average SNR, last-seen age, and straight-line distance in kilometres when both self and repeater locations are known. **Reset** clears these observations.

This passive radio observation list is distinct from the active 15-second **Nearby Nodes** discovery screen.

---

## SMAZ Compression

### What It Is
An optional per-contact and per-channel text compression feature using the SMAZ algorithm (optimized for short English text).

### How to Enable
- **Per contact**: Direct chat overflow menu → Settings → toggle "SMAZ compression"
- **Per channel**: Long-press channel → Edit → toggle "SMAZ compression"

### How It Works
- When enabled, compression is applied using a "compress only if smaller" strategy — the message is only transmitted compressed if the encoded result is actually shorter than the original. Otherwise, the original text is sent uncompressed
- Compressed messages are transmitted with a `s:` prefix followed by base64-encoded data
- Recipients using MeshCore Open will decompress automatically. **Recipients using other software** that is not SMAZ-aware will see garbled `s:...` text
- The dictionary is optimized for short English/ASCII text, but arbitrary UTF-8 bytes are preserved verbatim. Non-English text usually does not compress well and may expand, in which case the original text is sent because of the size check
- Disabled by default

---

## Community QR Scanner

### How to Access
From Channels screen → "+" FAB → "Scan Community QR"

### What the User Sees
A live QR scanner view with instruction text overlay.

### Key Interactions
- Scan a community QR code shared by another member
- On valid scan: confirmation dialog showing community name and ID
- Option to "Add public channel to device" on join
- If already a member: shows an "Already a member" dialog
- Invalid QR: shows an orange error snackbar

---

## Channel Message Path Viewing

### How to Access
In a channel chat, long-press a message bubble, or right-click on desktop, and choose **Path**.

### What the User Sees
- Summary card: sender, time, repeat count, path type, observed hops
- "Other Observed Paths" section (if multiple paths detected)
- "Repeater Hops" section listing each hop with hex prefix, resolved name, and GPS coordinates

### Actions
- **Radar icon**: Opens path trace map for live trace
- **Map icon**: Opens a map with hop markers and polyline
- **Path dropdown**: Switch between observed path variants (if multiple)

---

## Debug Logging

### BLE Debug Log
**Access**: Settings → BLE Debug Log

Two views:
- **Frames**: Each BLE frame with direction, description, hex preview, timestamp. Long-press to copy hex.
- **Raw Log RX**: Decoded LoRa packets with route type, payload type, path bytes, and summary.

### App Debug Log
**Access**: Settings → App Debug Log (must be enabled first in App Settings → Debug)

Structured log entries with level (Info/Warning/Error), tag, message, and timestamp.

Both logs support copy-all and clear operations.

---

## Chrome Required Screen

### When It Appears
Automatically shown on web platforms when a non-Chromium browser is detected.

### What the User Sees
A full-screen informational page explaining that the web build requires a Chromium-based browser for Web Serial. Browser BLE is not supported. No interactive elements are provided.

---

## Path History Service

### What It Does (Background Service)
Maintains an in-memory LRU cache of up to 50 contacts, each with up to 100 route history entries, tracking:
- Hop count and trip time
- Success/failure counts and route weights
- Flood vs. direct discovery

### Path Scoring
Paths are scored using a weighted formula: reliability (45%), route weight (20%), latency (25%), and freshness (10%). These weights are internal and not user-configurable. A failed path is deleted only when the new weight would be zero or lower and it has accumulated at least three failures. Until then its weight is kept at a 0.1 floor. Flood deliveries that receive an ACK give a weight boost (+0.5) to the specific return path.

Used internally for:
- **Auto route rotation**: Cycles through known paths using configurable weights on retries, with a diversity window to avoid re-using recently tried paths
- **Path selection**: Picks the best-scored path for each retry attempt
- **Flood statistics**: Tracks flood vs. direct discovery ratios

---

## Message Retry Service

### What It Does (Background Service)
Handles reliable delivery of outgoing direct messages:
1. Assigns a UUID and queues the send. Only one message per contact can be in-flight at a time, with a global cap of six active sends to leave headroom in the firmware's 8-entry ACK table
2. Listens for ACK frames matched via SHA-256 hash of `[timestamp][attempt][text][sender_pubkey]`
3. On timeout, retries with exponential backoff: `1000 × 2^retryCount` ms (1s, 2s, 4s, 8s...)
4. Each retry may use a different path (via path history diversity window)
5. After max retries: marks failed but keeps a **30-second grace window** during which a late ACK can still resolve the message to "delivered". Optionally clears the contact's path
6. Reports RTT and path data for quality learning
7. Maintains an ACK hash history (last 100 entries) to handle duplicate ACKs

### Configurable Settings (App Settings → Messaging)
- Max retries (2–10, default 5)
- Clear path on max retry (on/off)
- Auto route rotation with weight parameters

---

## Timeout Prediction (ML)

### What It Does (Background Service)
An ML-based service that predicts expected delivery timeouts:
- Collects delivery observations (path length, message size, time since last RX, delivery time) in a sliding window of up to 100 observations (oldest evicted first)
- Requires **10 minimum observations** before first training. After that, retrains every 5 new observations
- Applies a **1.5x safety margin** to raw predictions (the actual timeout issued is 1.5× the model's predicted delivery time)
- Features with zero variance are automatically excluded from training
- Blends per-contact statistics with ML predictions
- When no model prediction is available, the retry path prefers the firmware's estimated timeout and otherwise uses the LoRa-airtime physics calculation described in [Chat & Messaging](chat-and-messaging.md#retry-mechanism); all results are capped at 45 seconds
- Observations are persisted to storage via a 2-second debounced timer (observations within 2s of app termination may be lost)

---

## On-Device Message Translation

### What It Is
An optional translation service powered by an embedded LLM (llamadart, running GGUF models). Inference and message text stay on-device. Downloading a preset or custom model still makes a network request to its model host.

### How to Access
First download and select a GGUF model under **App Settings → Translation**, then enable translation. Long-press/right-click an eligible incoming message and choose **Translate**, or enable automatic incoming translation. The app does not automatically download a model when a message is translated.

### How It Works
- Model files are managed by `TranslationFileStore`; download progress is shown in-place
- Before translating, the source language is automatically detected using the `flutter_langdetect` package. If the detected language already matches the target language, translation is skipped
- Translation runs via `TranslationService` using the llamadart CPU backend (arm64 and x64 on Android)
- Translated text is shown in `TranslatedMessageContent` as an inline overlay on the original message bubble
- Each translation is cached; re-tapping shows the cached result without re-running inference

---

## Emoji Reactions

### How to Access
Long-press an incoming message bubble in a direct or channel chat, then select a reaction emoji. The app does not offer reactions on your own outgoing messages.

### What the User Sees
An emoji picker inline with common reactions. Selected reactions appear below the message bubble with a count.

### How It Works
- Implemented via `emoji_picker.dart` and `reaction_helper.dart`
- Reactions are transmitted as a special message type visible to all participants with MeshCore Open

---

## Linkification

### What It Does
URLs, structured `meshcore://` contact/channel URIs, legacy advert links, and compact contact links in messages are automatically detected and rendered as tappable links.

### How It Works
- Ordinary URLs require confirmation before the system browser opens
- MeshCore links open an in-app preview before adding the contact or channel
- Channel links contain their 16-byte PSK and optional region scope; treat private/community links as sensitive

---

## GPX Export

### How to Access
Settings → Export section (three options: Export Repeaters, Export Contacts, Export All).

### What It Does
Exports contacts with GPS coordinates to a `.gpx` file via the OS share sheet. Not available on web.

---

## Pinch-to-Zoom Chat Text

### What It Does
Users can pinch to scale all chat text up or down within a session.

### How It Works
- Implemented via `ChatTextScaleService` and `ChatZoomWrapper`
- Scale range: 0.8× to 1.8×
- The chosen scale is saved in app preferences and persists across launches

---

## Background Service (Android)

### What It Does
On Android, a foreground service (`background_service.dart`) keeps the BLE connection and message handling alive when the app is in the background. On other platforms this is a no-op.

### User Impact
- A persistent notification appears while the service is running
- Messages are received and retry logic continues even when the app is not in the foreground

---

## Desktop Interaction

- Chat, reply, login, CLI, and settings text fields request focus when opened where appropriate.
- Enter sends messages/commands; CLI Up/Down navigates persistent per-repeater command history.
- Escape performs the screen's Back action.
- The app remembers desktop window position between runs.
- Closing the desktop window disconnects an active BLE session cleanly before exit.
- Rows and message bubbles expose right-click menus, and contact/discovery lists support keyboard Delete where offered.
