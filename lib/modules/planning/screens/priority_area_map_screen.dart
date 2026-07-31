import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/proposal.dart';
import '../widgets/planning_widgets.dart';

class PriorityAreaMapScreen extends StatefulWidget {
  const PriorityAreaMapScreen({
    super.key,
    required this.area,
  });

  final GapArea area;

  @override
  State<PriorityAreaMapScreen> createState() =>
      _PriorityAreaMapScreenState();
}

class _PriorityAreaMapScreenState extends State<PriorityAreaMapScreen> {
  late final List<GapArea> _focusedAreas;

  @override
  void initState() {
    super.initState();
    _focusedAreas = List<GapArea>.unmodifiable([widget.area]);
    debugPrint(
      'PriorityAreaMapScreen initState: '
      'instance=${identityHashCode(this)}, area=${widget.area.id}.',
    );
  }

  @override
  void dispose() {
    debugPrint(
      'PriorityAreaMapScreen dispose: '
      'instance=${identityHashCode(this)}, area=${widget.area.id}.',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final latitude = widget.area.latitude ?? 4.2105;
    final longitude = widget.area.longitude ?? 101.9758;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Priority Area Map',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: MapPanel(
                    height: constraints.maxHeight,
                    gaps: true,
                    priorityAreas: _focusedAreas,
                    initialTarget: LatLng(latitude, longitude),
                    initialZoom: 10,
                    mapPadding: const EdgeInsets.fromLTRB(12, 12, 12, 150),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.red,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.area.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: planningTextColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      widget.area.state,
                                      style: const TextStyle(
                                        color: planningMutedTextColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Score ${widget.area.priorityScore.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              _FocusedMapMetric(
                                icon: Icons.route_outlined,
                                value:
                                    '${widget.area.distance.toStringAsFixed(1)} km to nearest station',
                              ),
                              _FocusedMapMetric(
                                icon: Icons.ev_station_outlined,
                                value:
                                    '${widget.area.nearbyStationCount} stations within 25 km',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusedMapMetric extends StatelessWidget {
  const _FocusedMapMetric({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: planningMutedTextColor),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: planningMutedTextColor,
              fontSize: 12,
            ),
          ),
        ],
      );
}
