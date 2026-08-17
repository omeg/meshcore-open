# Development Notes

These notes capture implementation findings that are useful for future work but are too specific for the user-facing feature docs. `AGENTS.md` is still useful as a short agent runbook, but durable project findings should live in `documentation/`.

## Multibyte Path Support

Detailed protocol notes are in [Companion Protocol & Data Layer](ble-protocol.md#path-hashes-and-multibyte-paths). The short version:

- Path hashes are public-key prefixes and can be 1, 2, or 3 bytes. There are no 4-byte path hashes in the app path model.
- Do not guess the hash width from raw path length. Use device self-info for active width and packet `path_len` for packet-specific width.
- Treat path length as hop count. Raw byte count is `hopCount * pathHashByteWidth`.
- Reverse paths per hop with `reversePathByHop()`, not byte-by-byte.
- Store/render historical channel-message paths with their message-specific `pathHashByteWidth`; the active device width can change later.
- UI that formats or matches path IDs must use the active or message-specific width. This includes message path details, observed paths, custom path entry, path selection, nearby/direct repeaters, contact path tools, and map/path-trace views.

Capacity limits come from the 64-byte path field: 64 hops at 1 byte, 32 hops at 2 bytes, and 21 hops at 3 bytes.

## Path Trace Compatibility

Normal raw packet paths and path trace packets do not use exactly the same encoding. Current trace request flags support 1-byte and 2-byte trace paths. When the source path is 3-byte, the app currently down-converts trace chunks to 2 bytes because firmware has no 3-byte trace flag there; flag value `2` is a 4-byte trace mode in that path.

Keep this compatibility code local to `path_trace_map.dart`. Do not apply trace flag assumptions to normal packet path parsing.

## Channel Message Repeats

For outgoing channel messages, the first observed echo should promote the pending message to sent without incrementing the repeat counter. Later duplicate observations should increment repeats. This avoids showing an immediate extra repeat for the sender's own successful transmission.

## Discovered Contacts Persistence

Discovered contacts should be scoped by the connected device identity using `discovered_contacts<pubKey10>`. The old global `discovered_contacts` key is a legacy format and should migrate on first scoped load.

The connector must set the discovery store public key after self-info is parsed, then reload the discovered contact cache and notify listeners. Without this, discovered contacts can appear to reset between rebuilds or runs.

## Linux BLE Startup

Linux users can avoid scan delay by passing a BLE address at startup. Keep command-line argument handling compatible with Flutter's Linux invocation style:

```
flutter run -d linux -- --ble-address CF:DE:B5:89:55:F5
```

`--ble-addr` and the `--ble-address=<address>` / `--ble-addr=<address>` forms are also accepted. The app should continue to support scanning when no address is supplied.

## Desktop Keyboard Flow

Desktop/Linux workflows should not require a mouse click before typing. Channel chats, direct chats, and repeater CLI-style screens should request focus for the text field when opened or revisited after alt-tabbing. CLI command history should be reachable from the keyboard; arrow-up should trigger the same previous-command behavior as the UI button.

Unread/new-message markers on desktop should persist while the user remains on the screen. Do not clear the marker merely because the full message list has been rendered; clear it when the user leaves or otherwise acknowledges the screen according to the screen's unread-state contract.

## Telemetry Log Fetching

Telemetry-log request subtypes and their InfluxDB workflow target the [omeg MeshCore firmware fork](https://github.com/omeg/meshcore); do not present them as stock-firmware behavior. After a full fetch, the UI should still allow a later refresh for newly appended data without requiring an app restart. Cancellation should abort promptly instead of waiting for the current long fetch loop to drain. Future changes in this area should check cancellation between request chunks and before delayed retries.

## Debugging Raw Path Issues

When investigating suspicious observed paths, enable or add logs that include:

- raw packet bytes around the header/path area
- raw `path_len`
- decoded path hash width
- active device path hash width
- path byte count
- formatted path bytes grouped by decoded width

Byte-order bugs tend to show up as correctly sized but reversed hop chunks. Width bugs tend to show up as impossible hop counts or contact/repeater matches that only work for 1-byte IDs.
