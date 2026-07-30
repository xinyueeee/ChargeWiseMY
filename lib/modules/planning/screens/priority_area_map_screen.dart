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
        title: Text(
          widget.area.name,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: LayoutBuilder(
                  builder: (context, constraints) => MapPanel(
                    height: constraints.maxHeight,
                    gaps: true,
                    priorityAreas: _focusedAreas,
                    initialTarget: LatLng(latitude, longitude),
                    initialZoom: 10,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.area.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Nearest station: '
                            '${widget.area.distance.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              color: Color(0xFF5F6B82),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
