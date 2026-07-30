import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/proposal.dart';

const green = Color(0xFF00B894);
const blue = Color(0xFF2F80ED);

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext c) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: child,
      );
}

class StatisticCard extends StatelessWidget {
  const StatisticCard({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext c) => Container(
        width: 155,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      );
}

class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    this.height = 250,
    this.gaps = false,
    this.stations = const [],
    this.proposals = const [],
    this.priorityAreas = const [],
  });
  final double height;
  final bool gaps;
  final List<ChargingStation> stations;
  final List<Proposal> proposals;
  final List<GapArea> priorityAreas;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  static const _existingStationsClusterId =
      ClusterManagerId('existing_stations');
  static const _clusterManagers = <ClusterManager>{
    ClusterManager(clusterManagerId: _existingStationsClusterId),
  };

  _MarkerIcons? _icons;
  Set<Marker> _markers = const {};
  Set<Circle> _priorityCircles = const {};
  int? _overlayDataHash;
  bool _preparingMarkers = true;

  @override
  void initState() {
    super.initState();
    _loadIconsAndOverlays();
  }

  @override
  void didUpdateWidget(covariant MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rebuildOverlaysIfNeeded();
  }

  Future<void> _loadIconsAndOverlays() async {
    try {
      _icons = await _MarkerIcons.load();
      _rebuildOverlaysIfNeeded(force: true);
    } catch (error, stackTrace) {
      debugPrint('Map marker icon load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _preparingMarkers = false);
    }
  }

  int get _currentDataHash => Object.hashAll([
        for (final station in widget.stations)
          Object.hash(station.id, station.latitude, station.longitude),
        for (final proposal in widget.proposals)
          Object.hash(proposal.id, proposal.latitude, proposal.longitude),
        for (final area in widget.priorityAreas)
          Object.hash(area.name, area.priority, area.latitude, area.longitude),
      ]);

  void _rebuildOverlaysIfNeeded({bool force = false}) {
    if (_icons == null) return;
    final dataHash = _currentDataHash;
    if (!force && dataHash == _overlayDataHash) return;

    final stopwatch = Stopwatch()..start();
    final markers = <Marker>{};
    for (final station in widget.stations) {
      markers.add(Marker(
        markerId: MarkerId('station_${station.id}'),
        position: LatLng(station.latitude, station.longitude),
        icon: _icons!.station,
        clusterManagerId: _existingStationsClusterId,
        infoWindow:
            InfoWindow(title: station.name, snippet: station.chargerType),
      ));
    }
    for (final proposal in widget.proposals) {
      if (proposal.latitude == null || proposal.longitude == null) continue;
      markers.add(Marker(
        markerId: MarkerId('proposal_${proposal.id}'),
        position: LatLng(proposal.latitude!, proposal.longitude!),
        icon: _icons!.proposal,
        infoWindow:
            InfoWindow(title: proposal.city, snippet: 'Proposed station'),
      ));
    }
    final priorityCircles = <Circle>{};
    for (final area
        in widget.priorityAreas.where((area) => area.priority == 'High')) {
      if (area.latitude == null || area.longitude == null) continue;
      priorityCircles.add(Circle(
        circleId: CircleId(
            'priority_${area.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_')}'),
        center: LatLng(area.latitude!, area.longitude!),
        radius: 4000,
        fillColor: Colors.red.withValues(alpha: .18),
        strokeColor: Colors.red.withValues(alpha: .9),
        strokeWidth: 2,
      ));
    }
    final validProposals = widget.proposals
        .where((proposal) =>
            proposal.latitude != null && proposal.longitude != null)
        .length;
    final validPriorityAreas = widget.priorityAreas
        .where((area) =>
            area.priority == 'High' &&
            area.latitude != null &&
            area.longitude != null)
        .length;
    stopwatch.stop();
    _markers = markers;
    _priorityCircles = priorityCircles;
    _overlayDataHash = dataHash;
    debugPrint(
      'Map diagnostics: marker creation ${stopwatch.elapsedMilliseconds}ms; '
      '${widget.stations.length} station markers assigned to clustering; '
      '$validProposals non-clustered proposal markers '
      '(${widget.proposals.length - validProposals} invalid coordinates); '
      '$validPriorityAreas priority circles '
      '(${widget.priorityAreas.where((area) => area.priority == 'High').length - validPriorityAreas} invalid coordinates); '
      '${markers.length} total markers.',
    );
  }

  @override
  Widget build(BuildContext c) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: const CameraPosition(
                    target: LatLng(4.2105, 101.9758), zoom: 6.5),
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                markers: _markers,
                circles: _priorityCircles,
                clusterManagers: _clusterManagers,
                onMapCreated: (_) => debugPrint('Google Map created successfully.'),
              ),
              if (_preparingMarkers)
                const Center(child: CircularProgressIndicator.adaptive()),
            ],
          ),
        ),
      );
}

class _MarkerIcons {
  const _MarkerIcons({required this.station, required this.proposal});

  final BitmapDescriptor station;
  final BitmapDescriptor proposal;

  static Future<_MarkerIcons>? _cache;

  static Future<_MarkerIcons> load() => _cache ??= _load();

  static Future<_MarkerIcons> _load() async {
    return _MarkerIcons(
      station: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(28, 28)),
        'assets/icons/station_lightning.png',
      ),
      proposal: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(32, 32)),
        'assets/icons/proposed_station.png',
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext c) {
    final color = status == 'Approved'
        ? green
        : status == 'Rejected'
            ? Colors.red
            : status == 'Pending'
                ? Colors.orange
                : blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class ProposalCard extends StatelessWidget {
  const ProposalCard({
    super.key,
    required this.proposal,
    required this.onDetails,
  });
  final Proposal proposal;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext c) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 88,
                  width: 88,
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bolt, color: green, size: 48),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proposal.city,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        proposal.description,
                        style: const TextStyle(
                          color: Color(0xFF5F6B82),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '👥  ${proposal.displayedSupports} Supports',
                        style: const TextStyle(color: green, fontSize: 16),
                      ),
                    ],
                  ),
                ),
                StatusChip(proposal.status),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(proposal.area),
                  backgroundColor: green.withValues(alpha: .08),
                ),
                Chip(
                  label: Text(proposal.charger),
                  backgroundColor: blue.withValues(alpha: .08),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: onDetails,
                child: const Text(
                  'View Details  ›',
                  style: TextStyle(color: green),
                ),
              ),
            ),
          ],
        ),
      );
}

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({super.key});
  @override
  Widget build(BuildContext c) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(24, 8, 24, 14),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(color: Color(0x18000000), blurRadius: 12)
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Nav(Icons.home_outlined, 'Home'),
              _Nav(Icons.bolt_outlined, 'Charging'),
              _Nav(Icons.map_outlined, 'Planning', selected: true),
              _Nav(Icons.warning_amber_outlined, 'Feedback'),
              _Nav(Icons.person_outline, 'Profile'),
            ],
          ),
        ),
      );
}

class _Nav extends StatelessWidget {
  const _Nav(this.icon, this.label, {this.selected = false});
  final IconData icon;
  final String label;
  final bool selected;
  @override
  Widget build(BuildContext c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: selected ? green : Colors.blueGrey),
          Text(label,
              style: TextStyle(color: selected ? green : Colors.blueGrey)),
        ],
      );
}
