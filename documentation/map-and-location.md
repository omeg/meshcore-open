# Map & Location

## Overview

The Map feature is a full-featured node-location visualization and radio-planning tool built on OpenStreetMap tiles. It is one of the three primary views accessible from the QuickSwitchBar.

## How to Access

- **QuickSwitchBar tab 2** (rightmost) from Contacts or Channels
- **Deep-link from a chat message**: Tapping a shared location pin in a chat opens the map centered on that pin
- **Settings → App Settings → Map Display → Offline Map Cache**: Opens the tile cache management screen

## What the Map Displays

### Self Location
Your own node's position, obtained from the device firmware. It is displayed as a cyan-blue `person_pin_circle` icon inside a dark circular marker. It only appears after the companion reports a location, whether supplied by attached GPS hardware or set manually.

### Contact / Node Markers (Color-Coded)
Contacts and, when enabled, discovered contacts with known GPS coordinates are eligible to appear. Type, activity, time, and public-key-prefix filters can reduce the visible set.

| Type | Color | Icon |
|---|---|---|
| Chat user | Green when online, amber when recent, grey when stale | Person |
| Repeater | Blue | Router |
| Room | Purple | Meeting room |
| Sensor | Teal | Sensors |

Below zoom level 12.5, nearby confirmed-location nodes are grouped into numbered clusters; tapping a cluster zooms to its members. Individual labels appear automatically at zoom level 14 and above. A selected node remains individually visible and labeled even when it would otherwise be clustered or filtered out.

### Shared Map Pins (Flag Icons)
Location pins shared in chat messages are displayed as flags:
- **Blue flag**: From a direct message
- **Purple flag**: From a private channel
- **Orange flag**: From a public channel

Tap a pin to see its source, sender, timestamp, coordinates, and flags. **Hide** removes it for the current map session; **Remove** persists its marker ID in the app's removed-marker list. Repeated updates with the same marker identity are collapsed to the newest position, with older distinct positions connected as history.

### Predicted / Guessed Locations

Many contacts on the mesh don't have GPS hardware, so the map has no explicit coordinates for them. Instead of leaving these contacts invisible, the app **infers an approximate position** by analyzing the repeater path the contact's messages travel through. These inferred positions are displayed as markers with a `not_listed_location` icon and a muted grey or colored border, visually distinct from confirmed-location markers.

#### Why guessed locations exist

In a mesh network, every message hops through one or more repeaters on its way to the destination. For this estimate, the app deliberately indexes repeaters by the first byte of the public key and uses the final raw path byte as the contact-side anchor. If that byte unambiguously identifies a repeater with a known GPS location, the contact is likely within radio range of it. Combining several such observations gives the app a rough display position. This is a one-byte heuristic even when the active route format uses wider path hashes, so it is never presented as a GPS fix.

#### How the algorithm works

1. **Build a repeater index**: The app collects all known contacts of type Repeater that have a valid GPS position and indexes them by the first byte of their public key.

2. **Collect anchor points**: For each contact without GPS that was seen within the last 24 hours, the app looks at the **last byte** of the contact's current path and paths returned by `PathHistoryService`. Each byte that unambiguously matches a located repeater becomes an "anchor point" — a GPS coordinate the contact is likely near.

3. **Resolve ambiguity**: If multiple repeaters share the same first public-key byte (a hash collision), that byte is discarded as ambiguous. Only unambiguous one-to-one matches are kept.

4. **Filter geometric inconsistencies**: Two anchor points separated by more than `2 × maxRangeKm` (the estimated LoRa radio range, computed from the current frequency, bandwidth, spreading factor, and TX power using a free-space path loss model) cannot both be in range of the same node. Outlier anchors are removed to keep only a geometrically consistent set.

5. **Compute the estimated position**:
   - **Single anchor**: The contact is placed on a small circle (330m radius) around the repeater. The angle on the circle is deterministic — derived from an FNV-1a hash of the contact's public key — so the same contact always appears at the same offset, preventing markers from stacking on top of each other.
   - **Two or more anchors**: The first coordinate is taken at full value and subsequent coordinates are added with successively halved weights. The accumulated latitude and longitude are divided by the number of anchors, then a deterministic visual-separation offset is applied (120m for 2 anchors, 80m for 3+).

6. **Assign confidence level**:
   - **High confidence** (2+ anchors): The marker border uses the node's type color (brighter border).
   - **Low confidence** (1 anchor): The marker border is rendered in a muted grey.

7. **Cache the result**: The computation is cached using a key derived from the contact's paths, anchor positions, path-history version, and radio parameters. The cache is only invalidated when any of these inputs change, avoiding recomputation on every UI rebuild.

#### How to read guessed locations on the map

- **Marker with `not_listed_location` icon**: This is a guessed position, not a confirmed GPS fix.
- **Colored border** (type color): Higher confidence — the contact was seen through 2 or more repeaters with known positions.
- **Grey border**: Lower confidence — based on a single repeater anchor only.
- Coordinates shown in the marker info dialog are prefixed with `~` to indicate they are estimated.
- Guessed locations can be toggled on/off in the map filter sheet. They render only at zoom level 12 or closer, are limited to contacts seen within 24 hours, and are hidden while key-prefix-overlap highlighting is enabled.

## Map Interactions

### Zoom and Pan
Standard pinch-to-zoom (range 2–18) is supported. The initial camera is calculated from the statistical spread of filtered contacts with confirmed locations and shared pins, with two-standard-deviation outlier filtering when at least three points exist. Guessed locations and the self marker do not participate in that initial fit. Desktop also provides zoom, reset, and center-on-self controls plus keyboard map navigation.

### Tap on a Node Marker
Selects the node and opens a bottom summary card showing activity status, type, last-seen time, route, shortened public key, and confirmed or estimated coordinates. **Details** opens the full information sheet with the complete public key. Action buttons vary by type:
- **Users**: "Open Chat"
- **Repeaters**: "Manage Repeater"
- **Rooms**: "Join Room"

### Long-Press / Right-Click on Empty Map Area
Shows a bottom sheet with:
- **Share marker here**: Prompts for a label, then pick a DM contact or channel to send the location to. Wire format: `m:<lat>,<lon>|<label>|poi`
- **Set as my location**: Updates your device's advertised location

### Filter Dialog (FAB)
Toggle visibility of users, repeaters, other nodes, guessed locations, discovered contacts, shared map pins, and key-prefix-collision highlighting.
Additional filters:
- **Key prefix filter**: Show only contacts whose public key starts with a given prefix
- **Last-seen time slider**: Exponential scale from near-zero to 6 months, with "all time" at the top end

**Show overlaps** is not a geographic-overlap filter. It highlights repeaters and rooms whose first public-key byte collides, colors those markers red, prefixes their labels with the colliding byte, and prevents low-zoom clustering so every collision remains visible. Guessed markers are hidden in this mode.

The top overlay also provides name/public-key search and quick activity chips: **All**, **Online** (seen within 60 minutes), **Recent** (seen within 24 hours, including online), and **Stale** (older than 24 hours). Repeater and chat-node visibility can be toggled from the same row.

The map overflow menu contains **Path Trace** when self coordinates are known, **Line of Sight**, **Disconnect**, **Discovered Contacts**, and **Settings**. Starting Path Trace enters an in-map path builder: tap nodes to append hops, undo the last hop if needed, then run a one-way or return-path trace.

### Legend Card (Top-Right)
The compact pill shows the visible-node count. Tap it to expand counts for visible, online, repeater, hidden, and shared-pin markers plus a legend for node types, direct-message pins, and guessed locations. Private/public channel pin colors are visible on the map but are not separate legend rows.

---

## Path Trace Map

### How to Access
- From the main map's overflow menu → **Path Trace** (shown when self coordinates are known)
- From a contact's long-press menu → "Path Trace / Ping"
- From a message's path view → radar icon

### What the User Sees
A map with a polyline showing the route from your node through repeater hops to the target:
- **Green circles**: Hops with known GPS coordinates
- **Orange circles** (`~HH`): Inferred positions (no GPS but deducible from contacts)
- **Red endpoint**: Target contact with known GPS
- **Magenta endpoint**: Target with guessed position

A bottom panel shows each hop pair with SNR quality icons and total path distance. When multiple observed paths are available, a **Single / Combined** toggle appears at the top of the map. In Combined view, all paths are overlaid; shared segments are highlighted with a white halo and a path count badge appears on shared nodes.

The bottom panel also provides **packet animation controls**:
- **Animation toggle** (on/off)
- **Step back / Play / Step forward / Replay** buttons
- **Follow packet lock** — keeps the map camera centered on the moving packet dot
- **Speed selector** (0.5×, 1×, 2×)
- A live **"Hop x of y · from → to"** label that tracks the active segment

### How It Works
Sends a trace request frame over the mesh. The repeater network traces the path hop-by-hop and returns per-hop SNR data. For hops without GPS, positions are inferred by averaging GPS coordinates of contacts sharing that last-hop byte.

---

## Line-of-Sight (LOS) Analysis

### How to Access
From the main map, tap the terrain/antenna icon.

### What the User Sees
A full-screen map with a draggable bottom sheet containing:
- **Elevation profile chart**: Terrain fill (green), LOS beam line (cyan), radio horizon line (yellow); obstruction points are marked as clickable dots on the chart
- **Status summary**: Clear (green), Marginal (amber, within 5 m of obstruction), or Blocked (red) with distance and clearance/obstruction amount
- **Options section** (collapsible): Node toggles, endpoint dropdowns, antenna height sliders (0–400 ft), Run LOS button

### Key Interactions
- **Long-press the map** to add custom endpoints (pushpin markers, renameable/deleteable)
- **Tap a marker** to select it as Point A or B; LOS runs automatically when both are set
- **Antenna heights** are adjustable for both endpoints
- **Map line** between endpoints is colored green (clear), amber (marginal), or red (blocked)
- Terrain elevation is fetched from the Open-Meteo API (21, 41, or 81 sample points depending on link distance, cached 24 hours)
- K-factor is adjusted per radio frequency from a baseline of 4/3 at 915 MHz

---

## Offline Map Cache

### How to Access
Settings → App Settings → Map Display → Offline Map Cache

### What the User Sees
- Map with a blue polygon overlay showing previously selected cache bounds
- Bounding box coordinates card
- **Cache Area** controls: "Use Current View" and Clear buttons
- **Zoom Range** range slider (3–18, dual-handle for min and max) with estimated tile count
- **Download progress** bar (when downloading)
- **Download Tiles** and **Clear Cache** buttons

### Key Interactions
1. Pan/zoom the map to the desired area
2. Tap "Use Current View" to capture the viewport as cache bounds
3. Adjust the zoom range slider
4. Tap "Download Tiles" (confirmation dialog shows estimated count)
5. Tiles are downloaded with up to 8 concurrent connections
6. Once cached, tiles are served from disk without internet (365-day stale period)

---

## GPX Export

### How to Access
Settings → Export section

### What It Does
On non-web platforms, exports contacts with GPS coordinates to a `.gpx` file via the OS share sheet. Three export options:
- **Export Repeaters**: Repeater and Room contacts with locations
- **Export Contacts**: Chat contacts with locations
- **Export All**: All contacts with locations

Each waypoint includes: name, lat/lon, type label, and public key hex.

---

## Location Data Sources

The phone's own GPS is **never used**. All location data comes from the mesh:

1. **Device self-location**: Read from firmware device-info response. Set manually in Settings → Location, or updated automatically if the device has a GPS module.
2. **Remote node locations**: Extracted from advertisement packets received over the mesh. Encoded as integer lat/lon × 1,000,000.
