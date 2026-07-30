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
    this.initialTarget = const LatLng(4.2105, 101.9758),
    this.initialZoom = 6.5,
  });
  final double height;
  final bool gaps;
  final List<ChargingStation> stations;
  final List<Proposal> proposals;
  final List<GapArea> priorityAreas;
  final LatLng initialTarget;
  final double initialZoom;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

class _MapPanelState extends State<MapPanel> {
  static int _mountedPanelCount = 0;
  static int _createdPlatformViewCount = 0;
  static const ClusterManagerId _existingStationsClusterId =
      ClusterManagerId('existing_stations');

  static final Set<ClusterManager> _clusterManagers = <ClusterManager>{
    ClusterManager(
      clusterManagerId: _existingStationsClusterId,
    ),
  };

  static List<ChargingStation>? _cachedStationSource;
  static Set<Marker> _cachedStationMarkers = const {};
  static List<Proposal>? _cachedProposalSource;
  static Set<Marker> _cachedProposalMarkers = const {};
  static List<ChargingStation>? _cachedCombinedStationSource;
  static List<Proposal>? _cachedCombinedProposalSource;
  static Set<Marker> _cachedCombinedMarkers = const {};

  _MarkerIcons? _icons;
  Set<Marker> _markers = const {};
  Set<Circle> _priorityCircles = const {};
  bool _preparingMarkers = true;
  bool _platformViewCreated = false;
  int _buildCount = 0;
  late final int _instanceId;

  @override
  void initState() {
    super.initState();
    _instanceId = identityHashCode(this);
    _mountedPanelCount++;
    debugPrint(
      'MapPanel initState: instance=$_instanceId, '
      'mode=${widget.gaps ? 'gap-circles-only' : 'dashboard-clustered'}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    if (widget.gaps) {
      _markers = const {};
      _priorityCircles = _buildPriorityCircles();
      _preparingMarkers = false;
      debugPrint(
        'Gap Analysis map overlay preparation: '
        'rawStations=${widget.stations.length}, '
        'finalMarkers=0, clusterAssignedMarkers=0, '
        'priorityCircles=${_priorityCircles.length}, '
        'markerGenerationDuration=0ms.',
      );
    } else {
      _loadIconsAndOverlays();
    }
  }

  @override
  void dispose() {
    if (_platformViewCreated) {
      _createdPlatformViewCount--;
    }
    _mountedPanelCount--;
    debugPrint(
      'MapPanel dispose: instance=$_instanceId, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.gaps) {
      _markers = const {};
      if (!identical(oldWidget.priorityAreas, widget.priorityAreas)) {
        _priorityCircles = _buildPriorityCircles();
      }
      return;
    }
    _prepareOverlays(
      stationDataChanged: !identical(oldWidget.stations, widget.stations),
      proposalDataChanged: !identical(oldWidget.proposals, widget.proposals),
      priorityDataChanged:
          !identical(oldWidget.priorityAreas, widget.priorityAreas),
    );
  }

  Future<void> _loadIconsAndOverlays() async {
    try {
      final icons = await _MarkerIcons.load();
      if (!mounted) return;
      _icons = icons;
      _prepareOverlays(force: true);
    } catch (error, stackTrace) {
      debugPrint('Map marker icon load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _preparingMarkers = false);
    }
  }

  void _prepareOverlays({
    bool force = false,
    bool stationDataChanged = false,
    bool proposalDataChanged = false,
    bool priorityDataChanged = false,
  }) {
    if (_icons == null) return;

    final markerDataChanged =
        force || stationDataChanged || proposalDataChanged;
    if (markerDataChanged) {
      _markers = _combinedMarkers();
    }
    if (force || priorityDataChanged) {
      _priorityCircles = _buildPriorityCircles();
    }
  }

  Set<Marker> _combinedMarkers() {
    if (identical(_cachedCombinedStationSource, widget.stations) &&
        identical(_cachedCombinedProposalSource, widget.proposals)) {
      debugPrint(
        'Map overlay cache hit: combined markers=${_cachedCombinedMarkers.length}.',
      );
      return _cachedCombinedMarkers;
    }

    final stationMarkers = _stationMarkers();
    final proposalMarkers = _proposalMarkers();
    final stopwatch = Stopwatch()..start();
    final markers = Set<Marker>.unmodifiable({
      ...stationMarkers,
      ...proposalMarkers,
    });
    stopwatch.stop();
    _cachedCombinedStationSource = widget.stations;
    _cachedCombinedProposalSource = widget.proposals;
    _cachedCombinedMarkers = markers;
    debugPrint(
      'Map diagnostics: combined marker set preparation='
      '${stopwatch.elapsedMilliseconds}ms, total=${markers.length}.',
    );
    return markers;
  }

  Set<Marker> _stationMarkers() {
    if (identical(_cachedStationSource, widget.stations)) {
      debugPrint(
        'Map overlay cache hit: station markers=${_cachedStationMarkers.length}.',
      );
      return _cachedStationMarkers;
    }

    final stopwatch = Stopwatch()..start();
    final markers = <Marker>{
      for (final station in widget.stations)
        Marker(
          markerId: MarkerId('station_${station.id}'),
          position: LatLng(station.latitude, station.longitude),
          icon: _icons!.station,
          clusterManagerId: _existingStationsClusterId,
          infoWindow:
              InfoWindow(title: station.name, snippet: station.chargerType),
        ),
    };
    stopwatch.stop();
    _cachedStationSource = widget.stations;
    _cachedStationMarkers = Set.unmodifiable(markers);
    debugPrint(
      'Map diagnostics: station marker creation and cluster preparation='
      '${stopwatch.elapsedMilliseconds}ms, '
      'clusteredMarkers=${markers.length}.',
    );
    return _cachedStationMarkers;
  }

  Set<Marker> _proposalMarkers() {
    if (identical(_cachedProposalSource, widget.proposals)) {
      return _cachedProposalMarkers;
    }

    final stopwatch = Stopwatch()..start();
    final markers = <Marker>{};
    var invalidCoordinates = 0;
    for (final proposal in widget.proposals) {
      if (proposal.latitude == null || proposal.longitude == null) {
        invalidCoordinates++;
        continue;
      }
      markers.add(
        Marker(
          markerId: MarkerId('proposal_${proposal.id}'),
          position: LatLng(proposal.latitude!, proposal.longitude!),
          icon: _icons!.proposal,
          infoWindow:
              InfoWindow(title: proposal.city, snippet: 'Proposed station'),
        ),
      );
    }
    stopwatch.stop();
    _cachedProposalSource = widget.proposals;
    _cachedProposalMarkers = Set.unmodifiable(markers);
    debugPrint(
      'Map diagnostics: proposal marker creation='
      '${stopwatch.elapsedMilliseconds}ms, markers=${markers.length}, '
      'invalid=$invalidCoordinates.',
    );
    return _cachedProposalMarkers;
  }

  Set<Circle> _buildPriorityCircles() {
    final stopwatch = Stopwatch()..start();
    final circles = <Circle>{};
    var invalidCoordinates = 0;
    for (final area
        in widget.priorityAreas.where((area) => area.priority == 'High')) {
      if (area.latitude == null || area.longitude == null) {
        invalidCoordinates++;
        continue;
      }
      circles.add(
        Circle(
          circleId: CircleId('priority_${area.id}'),
          center: LatLng(area.latitude!, area.longitude!),
          radius: 4000,
          fillColor: Colors.red.withValues(alpha: .18),
          strokeColor: Colors.red.withValues(alpha: .9),
          strokeWidth: 2,
        ),
      );
    }
    stopwatch.stop();
    debugPrint(
      'Map diagnostics: priority-circle creation='
      '${stopwatch.elapsedMilliseconds}ms, circles=${circles.length}, '
      'invalid=$invalidCoordinates.',
    );
    return Set.unmodifiable(circles);
  }

  void _handleMapCreated(GoogleMapController controller) {
    if (!_platformViewCreated) {
      _platformViewCreated = true;
      _createdPlatformViewCount++;
    }
    debugPrint(
      'Google Map created successfully: instance=$_instanceId, '
      'mode=${widget.gaps ? 'gap-circles-only' : 'dashboard-clustered'}, '
      'controller=${identityHashCode(controller)}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount, '
      'rawStations=${widget.stations.length}, '
      'finalMarkers=${widget.gaps ? 0 : _markers.length}, '
      'priorityCircles=${_priorityCircles.length}.',
    );
  }

  @override
  Widget build(BuildContext c) {
    _buildCount++;
    final markersPassedToGoogleMap =
        widget.gaps ? const <Marker>{} : _markers;
    final clusterManagersPassedToGoogleMap =
        widget.gaps ? const <ClusterManager>{} : _clusterManagers;
    final clusterAssignedMarkerCount =
        widget.gaps ? 0 : _cachedStationMarkers.length;
    debugPrint(
      'MapPanel rebuild: instance=$_instanceId, '
      'mode=${widget.gaps ? 'gap-circles-only' : 'dashboard-clustered'}, '
      'count=$_buildCount, rawStations=${widget.stations.length}, '
      'finalMarkers=${markersPassedToGoogleMap.length}, '
      'clusterAssignedMarkers=$clusterAssignedMarkerCount, '
      'priorityCircles=${_priorityCircles.length}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: widget.initialTarget,
                  zoom: widget.initialZoom,
                ),
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                zoomControlsEnabled: false,
                myLocationButtonEnabled: false,
                markers: markersPassedToGoogleMap,
                circles: _priorityCircles,
                clusterManagers: clusterManagersPassedToGoogleMap,
                onMapCreated: _handleMapCreated,
              ),
              if (_preparingMarkers)
                const Center(child: CircularProgressIndicator.adaptive()),
            ],
          ),
        ),
      );
  }
}

class _MarkerIcons {
  const _MarkerIcons({required this.station, required this.proposal});

  final BitmapDescriptor station;
  final BitmapDescriptor proposal;

  static Future<_MarkerIcons>? _cache;

  static Future<_MarkerIcons> load() {
    if (_cache != null) {
      debugPrint('Map marker icon cache hit.');
      return _cache!;
    }
    debugPrint('Map marker icon cache miss.');
    return _cache = _load();
  }

  static Future<_MarkerIcons> _load() async {
    final stopwatch = Stopwatch()..start();
    final icons = _MarkerIcons(
      station: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(28, 28)),
        'assets/icons/station_lightning.png',
      ),
      proposal: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(32, 32)),
        'assets/icons/proposed_station.png',
      ),
    );
    stopwatch.stop();
    debugPrint(
      'Map marker icon loading and resizing='
      '${stopwatch.elapsedMilliseconds}ms.',
    );
    return icons;
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
