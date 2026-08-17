# MeshCore Open

Open-source Flutter client for MeshCore LoRa mesh networking devices.

MeshCore Open connects to a companion radio over Bluetooth Low Energy, USB serial, or TCP and provides direct messaging, channels, maps, repeater administration, device configuration, and local message history. The app does not require an account or a developer-operated cloud service.

**Website:** [meshcoreopen.org](https://meshcoreopen.org/)

<a href="http://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://github.com/omeg/meshcore-open">
  <img src="assets/badges/badge_obtainium.png" height="80" align="center" alt="Get it on Obtainium"/>
</a>

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/contacts.jpg" width="200" alt="Contacts"/><br/><p align="center"><b>Contacts</b></p></td>
    <td><img src="docs/screenshots/chat1.jpg" width="200" alt="Chat"/><br/><p align="center"><b>Chat</b></p></td>
    <td><img src="docs/screenshots/chat2.jpg" width="200" alt="Reactions"/><br/><p align="center"><b>Reactions</b></p></td>
    <td><img src="docs/screenshots/map.jpg" width="200" alt="Map"/><br/><p align="center"><b>Map</b></p></td>
    <td><img src="docs/screenshots/channels.jpg" width="200" alt="Channels"/><br/><p align="center"><b>Channels</b></p></td>
  </tr>
</table>

## Features

- Encrypted direct messages with delivery tracking, reactions, resend/retry controls, route history, and automatic route rotation
- Broadcast channels, private channels, communities, region-scoped flooding, channel replies, and share links
- Persistent contacts and discovered nodes, groups, favorites, nearby-repeater discovery, and structured contact sharing
- Interactive maps, offline tile downloads, path traces, message-path inspection, and terrain line-of-sight profiles
- Companion settings for radio parameters, identity import, 1/2/3-byte path hashes, regions, telemetry, radio statistics, and GPS-capable hardware
- Repeater and room-server status, live telemetry, CLI, neighbor discovery, and remote settings
- Telemetry-log download and optional InfluxDB v2 import when used with the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore)
- Optional folder-based state synchronization between app installations
- 18 interface languages, on-device translation, Cyrillic-to-Latin profiles, GPX export, notifications, and debug tools

See the [feature documentation](documentation/README.md) for behavior, platform limits, and user instructions. The canonical companion-protocol reference is [documentation/ble-protocol.md](documentation/ble-protocol.md), and data handling is described in the [privacy policy](docs/PRIVACY_POLICY.md).

## Platform support

| Transport or feature | Android | iOS | Linux | Windows | macOS | Web |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| BLE companion | Yes | Yes | Yes | Yes | Yes | No |
| USB serial companion | Yes | No | Yes | Yes | Yes | Chrome only |
| TCP companion | Yes | Yes | Yes | Yes | Yes | No |
| Core messaging, channels, map, and settings | Yes | Yes | Yes | Yes | Yes | Yes* |
| Repeater management | Yes | Yes | Yes | Yes | Yes | Yes* |
| State-sync folders | Yes | No | Yes | Yes | Yes | No |

\* The web build requires a Chromium-based browser and a connected Web Serial companion. Browser BLE is intentionally unsupported.

The current mobile deployment targets are Android API 24+ and iOS 16.4+.

## Architecture

- Flutter 3.44+ and Dart 3.12+
- `Provider`/`ChangeNotifier` state management
- Nordic UART Service for BLE; the same binary command protocol over framed USB serial and TCP transports
- Identity-scoped JSON data in `SharedPreferences`, plus files for map tiles, translation models, synchronization snapshots, and telemetry logs
- MeshCore protocol encryption for private messages; shared pre-shared keys for channels

## Getting started

### Prerequisites

- Flutter 3.44 or later
- Android Studio, Xcode, or the desktop platform toolchain needed for your target
- A MeshCore-compatible companion radio

### Build and run

```bash
git clone https://github.com/omeg/meshcore-open.git
cd meshcore-open
flutter pub get
flutter run
```

Run the checks used for changes:

```bash
flutter analyze
flutter test
```

Release examples:

```bash
flutter build apk --release
flutter build ios --release
```

For Linux BLE development, a device can be selected without scanning:

```bash
flutter run -d linux -- --ble-address AA:BB:CC:DD:EE:FF
```

`--ble-addr` and `--ble-address=<address>` are also accepted.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), keep protocol changes synchronized with the canonical protocol guide, and run formatting, analysis, and tests before opening a pull request.

For issues, questions, or feature requests, use the [GitHub issue tracker](https://github.com/omeg/meshcore-open/issues).

## Donate

If you find MeshCore Open useful and would like to support development, you can donate Solana or other Solana tokens:

**Solana Address:** `F15YanjZj96YTBtKJYgNa8RLQLCZkx5CEwogPWkqXeoQ`

**Monero Address:** `453TxnpUqjkJtXxzdjMsrgERNkBRXEGamPbpC45ENrvKAk9tH7kZbxWF82Hz66etgDZyXFPEBU2JUEqhLeJyWt9kBvTVy5m`

**Bitcoin Address:** `bc1qh45x28v8dslcg4v4upmqd9g0mvc3lnyffmyzr5`

## Acknowledgments

- Built with [Flutter](https://flutter.dev/)
- Map data and tiles from [OpenStreetMap](https://www.openstreetmap.org/)
