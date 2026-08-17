# Privacy Policy for MeshCore Open

**Last updated:** August 12, 2026

MeshCore Open is an open-source client for MeshCore LoRa radios. It has no account system, analytics SDK, advertising SDK, or developer-operated backend. The project maintainers do not automatically receive app data. Features you choose to use can nevertheless send requests to mesh nodes, public third-party services, a server you configure, or a folder managed by another synchronization provider.

## Data kept by the app

Depending on the features used, local app storage may contain:

- Companion identities and public keys, contacts, discovered nodes, channels, communities, groups, and channel secrets
- Direct/channel message history, reactions, replies, unread state, delivery status, and observed routing/path information
- Node locations and location-bearing messages received from the mesh
- App/device preferences, including saved repeater passwords and optional InfluxDB connection details/API token
- Optional debug logs, delivery observations, map tiles, downloaded translation models, GPX exports, and telemetry-log files
- Plaintext JSON state bundles written to a user-selected sync folder

Most conversation and configuration state is scoped to the connected companion's public identity. Core records use the platform's app preferences; larger assets and exports use files. MeshCore Open does not add application-level encryption to local storage, telemetry files, or sync bundles. Operating-system storage protections and the security of any chosen folder/provider therefore matter.

Uninstalling or clearing app data removes data in normal app-private storage according to the platform's behavior. Files explicitly exported or written to a sync/export folder must be removed there separately. Data imported into a user-configured InfluxDB server must be managed on that server.

## Network and external-service requests

The app can make these optional outbound requests:

| Feature | Recipient | Data sent or exposed |
|---|---|---|
| Online/offline-map download | OpenStreetMap tile servers | Requested tile coordinates, IP address, and normal HTTP metadata |
| Terrain line-of-sight analysis | Open-Meteo elevation API | Selected endpoint/sample coordinates, IP address, and normal HTTP metadata |
| GIF picker and GIF display | GIPHY API/CDN | Search terms when entered, requested GIF IDs/assets, IP address, and normal HTTP metadata |
| Translation-model download | Hugging Face for built-in presets, or a custom URL chosen by the user | Requested model URL, IP address, and normal HTTP metadata; chat text is translated on-device and is not sent for inference |
| Firmware-fork telemetry import | User-configured InfluxDB v2 server | Repeater full public key, telemetry channel metadata, sensor values/timestamps, and API token in the authorization header |
| External links in messages | The site opened after user confirmation | The requested URL, IP address, and normal browser/app metadata |

Third-party operators handle those requests under their own policies: [OpenStreetMap Foundation privacy statement](https://osmfoundation.org/wiki/GDPR_Privacy_Statement), [Open-Meteo terms and privacy information](https://open-meteo.com/en/terms), [GIPHY privacy policy](https://support.giphy.com/hc/en-us/articles/360032872931-GIPHY-Privacy-Policy), and [Hugging Face privacy policy](https://huggingface.co/privacy).

The InfluxDB destination is selected and controlled by the user, not the MeshCore Open project. Both HTTP and HTTPS URLs are accepted; use HTTPS unless the server is strictly local and the network is trusted. Telemetry-log download and its InfluxDB integration require the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore).

## State-sync folders

On Android and desktop, users can select a folder for automatic state handoff. MeshCore Open reads and writes an identity-scoped JSON file in that folder; it does not upload the file itself. If the folder belongs to a cloud drive, network share, backup product, or another app, that provider may copy or process the file under its own terms.

The bundle may include message history, contacts, discovered nodes, channels and secrets, groups, region/encoding preferences, and global app settings—including an InfluxDB token when configured. Communities, the standalone pending-send store, unread counts, repeater passwords, and sync configuration are excluded; conversation history can still contain entries whose stored status is pending. The file is readable JSON and is not encrypted by the app. See [State sync](../documentation/telemetry-and-sync.md#state-sync) before enabling it.

## Mesh communications and share links

Messages and management commands are passed to the connected MeshCore radio and transmitted over the mesh. Direct messages use the MeshCore private-message protocol; channels use a shared pre-shared key. Radio traffic can be received or relayed by other nodes, and the app cannot control the retention or behavior of remote devices.

Contact share links contain a node's public identity and metadata. Channel share links contain the channel's 16-byte secret and optional region scope. Anyone with a channel link can participate in and decrypt that channel, so private/community links should be treated as credentials. A full private identity imported under Settings is more sensitive still and should never be shared as a contact link.

The phone's own GPS is not used for map positioning. A connected radio's manually configured or hardware-GPS location can be stored, advertised over the mesh, included in messages/exports, or sent to Open-Meteo when selected for line-of-sight analysis.

## Permissions

- **Bluetooth / nearby devices:** Discover and communicate with a BLE companion. Older Android versions also require location permission for BLE scanning.
- **Location (older Android):** Satisfies the operating system's BLE-scan requirement; the app does not read the phone's GPS.
- **USB:** Discover, request access to, and communicate with USB serial companions on supported platforms.
- **Camera:** Scan community QR codes; camera access is optional and only used while scanning.
- **Files/folders:** Select sync/export folders, save telemetry logs and GPX exports, and download map/model files.
- **Internet:** Access the optional services described above or a user-entered TCP/Influx/custom-model endpoint.
- **Notifications / foreground service / wake lock:** Show message and operation-result notifications and keep an Android BLE session alive in the background.

## Children

The app has no account service through which the project knowingly collects personal information from children. Mesh operators, third-party services, and user-configured storage or servers remain outside the project's control; guardians should supervise their use where required.

## Open source, changes, and contact

The implementation can be reviewed in the [MeshCore Open repository](https://github.com/omeg/meshcore-open). This policy may change as features change; the date above will be updated. Questions or reports can be filed in the [issue tracker](https://github.com/omeg/meshcore-open/issues).
