import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../connector/meshcore_connector.dart';
import '../connector/meshcore_protocol.dart';
import '../helpers/path_helper.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../models/contact.dart';
import 'signal_ui.dart';

Contact? _getRepeaterPrefixMatchNearLocation(
  List<Contact> contacts,
  List<int> hashPrefix, {
  LatLng? searchPoint,
  bool preferFavorites = false,
}) {
  const maxNearbyMatchDistanceMeters = 200000.0;
  if (hashPrefix.isEmpty) return null;
  final candidates = contacts
      .where(
        (c) =>
            c.publicKey.length >= hashPrefix.length &&
            listEquals(c.publicKey.sublist(0, hashPrefix.length), hashPrefix) &&
            (c.type == advTypeRepeater || c.type == advTypeRoom),
      )
      .toList();

  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    if (preferFavorites) {
      final favA = a.isFavorite ? 1 : 0;
      final favB = b.isFavorite ? 1 : 0;
      final favCompare = favB.compareTo(favA);
      if (favCompare != 0) return favCompare;
    }

    final seenCompare = b.lastSeen.compareTo(a.lastSeen);
    if (seenCompare != 0) return seenCompare;

    return a.publicKeyHex.compareTo(b.publicKeyHex);
  });

  if (searchPoint == null) {
    return candidates.first;
  }

  final distance = Distance();
  Contact? best;
  var bestDistance = double.infinity;

  for (final c in candidates) {
    if (c.hasLocation && c.latitude != null && c.longitude != null) {
      final d = distance(searchPoint, LatLng(c.latitude!, c.longitude!));
      if (d < bestDistance) {
        bestDistance = d;
        best = c;
      }
    }
  }

  if (best != null) {
    return bestDistance <= maxNearbyMatchDistanceMeters ? best : null;
  }
  return candidates.first;
}

class SNRUi {
  final IconData icon;
  final Color color;
  final String text;
  const SNRUi(this.icon, this.color, this.text);
}

List<double> getSNRfromSF(int spreadingFactor) {
  switch (spreadingFactor) {
    case 7:
      return [4.0, -2.0, -4.0, -6.0];
    case 8:
      return [4.0, -4.0, -6.0, -8.0];
    case 9:
      return [4.0, -6.0, -8.0, -10.0];
    case 10:
      return [4.0, -8.0, -10.0, -13.0];
    case 11:
      return [4.0, -10.0, -12.5, -15.0];
    case 12:
      return [4.0, -12.5, -15.0, -18.0];
    default:
      return []; // Or throw Exception('Invalid SF: $spreadingFactor');
  }
}

SNRUi snrUiFromSNR(double? snr, int? spreadingFactor) {
  if (snr == null ||
      spreadingFactor == null ||
      spreadingFactor < 7 ||
      spreadingFactor > 12) {
    return const SNRUi(Icons.signal_cellular_off, Colors.grey, '—');
  }

  final snrLevels = getSNRfromSF(spreadingFactor);

  String text = '${snr.toStringAsFixed(1)} dB';
  final tier = snr >= snrLevels[0]
      ? 0
      : snr >= snrLevels[1]
      ? 1
      : snr >= snrLevels[2]
      ? 2
      : snr >= snrLevels[3]
      ? 3
      : 4;
  final signalUi = signalUiForStrengthTier(tier);

  return SNRUi(signalUi.icon, signalUi.color, text);
}

class SNRIndicator extends StatefulWidget {
  final MeshCoreConnector connector;

  const SNRIndicator({super.key, required this.connector});

  @override
  State<SNRIndicator> createState() => _SNRIndicatorState();
}

class _SNRIndicatorState extends State<SNRIndicator> {
  bool _isValidSelfLocation(double lat, double lon) {
    const double epsilon = 1e-6;
    return (lat.abs() > epsilon || lon.abs() > epsilon) &&
        lat >= -90.0 &&
        lat <= 90.0 &&
        lon >= -180.0 &&
        lon <= 180.0;
  }

  @override
  Widget build(BuildContext context) {
    final directRepeaters = widget.connector.directRepeaters;
    final directBestRepeaters = List.of(directRepeaters)
      ..sort(DirectRepeater.compareByPacketCount);
    final directRepeater = directBestRepeaters.isEmpty
        ? null
        : directBestRepeaters.first;

    final snrUi = snrUiFromSNR(
      directBestRepeaters.isNotEmpty ? directRepeater!.averageSnr : null,
      widget.connector.currentSf,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      child: InkWell(
        onTap: directRepeater != null
            ? () => _showFullPathDialog(context)
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(snrUi.icon, size: 18, color: snrUi.color),
              Text(
                snrUi.text,
                style: TextStyle(fontSize: 12, color: snrUi.color),
              ),
              if (directRepeater != null)
                Text(
                  '${directRepeaters.length}: ${directRepeater.hashPrefixHex}: ${_formatLastUpdated(directRepeater.lastUpdated)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatLastUpdated(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);
    if (diff.isNegative) {
      return "0s";
    }
    if (diff.inMinutes < 1) {
      return "${diff.inSeconds}s";
    }
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes}m";
    }
    if (diff.inHours < 24) {
      final hours = diff.inHours;
      return "${hours}h";
    }
    final days = diff.inDays;
    return "${days}d";
  }

  void _showFullPathDialog(BuildContext context) {
    final l10n = context.l10n;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    if (isCompact) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(l10n.snrIndicator_nearByRepeaters),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                IconButton(
                  tooltip: 'Reset',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: widget.connector.clearDirectRepeaters,
                ),
              ],
            ),
            body: SafeArea(
              child: AnimatedBuilder(
                animation: widget.connector,
                builder: (context, _) =>
                    _buildNearbyRepeatersList(context, shrinkWrap: false),
              ),
            ),
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.snrIndicator_nearByRepeaters),
        content: SizedBox(
          width: 560,
          child: AnimatedBuilder(
            animation: widget.connector,
            builder: (context, _) => _buildNearbyRepeatersList(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.connector.clearDirectRepeaters,
            child: const Text('Reset'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.common_close),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyRepeatersList(
    BuildContext context, {
    bool shrinkWrap = true,
  }) {
    final l10n = context.l10n;
    final directBestRepeaters = List.of(widget.connector.directRepeaters)
      ..sort(DirectRepeater.compareByPacketCount);

    if (directBestRepeaters.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No nearby repeaters yet'),
        ),
      );
    }

    return Scrollbar(
      child: ListView.separated(
        shrinkWrap: shrinkWrap,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: directBestRepeaters.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final repeater = directBestRepeaters[index];
          final snrUi = snrUiFromSNR(
            repeater.averageSnr,
            widget.connector.currentSf,
          );
          final allContacts = widget.connector.allContacts;

          final selfLat = widget.connector.selfLatitude;
          final selfLon = widget.connector.selfLongitude;

          LatLng? selfPoint;
          if (selfLat != null &&
              selfLon != null &&
              _isValidSelfLocation(selfLat, selfLon)) {
            selfPoint = LatLng(selfLat, selfLon);
          }

          final contact = _getRepeaterPrefixMatchNearLocation(
            allContacts,
            repeater.hashPrefix,
            searchPoint: selfPoint,
            preferFavorites: true,
          );
          final distanceKmLabel = _formatDistanceKm(selfPoint, contact);

          final name = contact?.name;
          final prefixHex = PathHelper.formatHopHex(repeater.hashPrefix);
          // Nearby repeaters are inferred from the RF previous hop, so
          // their route from this device is direct even if the stored
          // contact route is stale or still reports a legacy max path.
          final routeLabel = l10n.chat_direct;
          final observedPathLabel = _formatHopLabel(
            l10n,
            repeater.observedPathHops,
          );
          final distanceSegment = distanceKmLabel == null
              ? ''
              : ' • distance: $distanceKmLabel';
          final pathLine =
              '$prefixHex • route: $routeLabel • path: $observedPathLabel$distanceSegment';
          final signalLine =
              'Packets: ${repeater.snrSampleCount} • Avg SNR: ${repeater.averageSnr.toStringAsFixed(1)} dB • ${l10n.snrIndicator_lastSeen}: ${_formatLastUpdated(repeater.lastUpdated)}';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 28,
                  child: Icon(snrUi.icon, color: snrUi.color),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name ?? prefixHex,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        pathLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        signalLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatHopLabel(AppLocalizations l10n, int hops) {
    if (hops <= 0) return l10n.chat_direct;
    return l10n.chat_hopsCount(hops);
  }

  String? _formatDistanceKm(LatLng? selfPoint, Contact? contact) {
    if (selfPoint == null ||
        contact == null ||
        !contact.hasLocation ||
        contact.latitude == null ||
        contact.longitude == null) {
      return null;
    }

    final distanceMeters = const Distance()(
      selfPoint,
      LatLng(contact.latitude!, contact.longitude!),
    );
    return '${(distanceMeters / 1000).toStringAsFixed(2)} km';
  }
}
