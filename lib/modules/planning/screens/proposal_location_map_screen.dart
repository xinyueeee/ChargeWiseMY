import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/proposal_location_service.dart';
import '../widgets/planning_widgets.dart';

class ProposalLocationMapScreen extends StatefulWidget {
  const ProposalLocationMapScreen({
    super.key,
    this.initialSelection,
    this.readOnly = false,
  });

  final ProposalLocationSelection? initialSelection;
  final bool readOnly;

  @override
  State<ProposalLocationMapScreen> createState() =>
      _ProposalLocationMapScreenState();
}

class _ProposalLocationMapScreenState
    extends State<ProposalLocationMapScreen> {
  static const _malaysiaCamera = CameraPosition(
    target: LatLng(4.2105, 101.9758),
    zoom: 5.5,
  );

  final ProposalLocationService _locations = ProposalLocationService();
  ProposalLocationSelection? _selection;
  LatLng? _markerPosition;
  Set<Polygon> _boundaries = const {};
  bool _loading = true;
  bool _resolving = false;
  String? _validationMessage;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
    if (_selection != null) {
      _markerPosition = LatLng(
        _selection!.latitude,
        _selection!.longitude,
      );
    }
    _prepareMap();
  }

  Future<void> _prepareMap() async {
    try {
      await _locations.load();
      final polygons = <Polygon>{};
      for (final region in _locations.stateBoundaries.regions) {
        for (var index = 0; index < region.displayPolygons.length; index++) {
          final rings = region.displayPolygons[index];
          if (rings.isEmpty || rings.first.length < 3) continue;
          polygons.add(
            Polygon(
              polygonId: PolygonId('proposal_boundary_${region.name}_$index'),
              points: [
                for (final point in rings.first)
                  LatLng(point.latitude, point.longitude),
              ],
              strokeColor: green.withValues(alpha: .75),
              strokeWidth: 1,
              fillColor: green.withValues(alpha: .025),
              consumeTapEvents: false,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _boundaries = Set<Polygon>.unmodifiable(polygons);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Proposal location map preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _validationMessage =
            'Unable to prepare the Malaysia boundary. Please try again.';
      });
    }
  }

  Set<Marker> get _markers {
    final position = _markerPosition;
    if (position == null) return const {};
    return {
      Marker(
        markerId: const MarkerId('proposal_selected_location'),
        position: position,
        draggable: !widget.readOnly,
        onDragEnd: widget.readOnly ? null : _selectLocation,
        infoWindow: InfoWindow(
          title: _selection?.locationLabel ?? 'Selected proposal location',
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = _markerPosition;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'Proposal Location' : 'Choose Location'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const PlanningLoadingState(
                      message: 'Preparing Malaysia map…',
                    )
                  : GoogleMap(
                      initialCameraPosition: initialTarget == null
                          ? _malaysiaCamera
                          : CameraPosition(target: initialTarget, zoom: 13),
                      mapType: MapType.normal,
                      polygons: _boundaries,
                      markers: _markers,
                      onTap: widget.readOnly || _resolving
                          ? null
                          : _selectLocation,
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      compassEnabled: true,
                      mapToolbarEnabled: false,
                      onMapCreated: (_) => debugPrint(
                        'Proposal location map created: '
                        'readOnly=${widget.readOnly}, boundaries=${_boundaries.length}.',
                      ),
                    ),
            ),
            Material(
              elevation: 8,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.readOnly)
                      const Text(
                        'Saved proposal location',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      )
                    else
                      const Text(
                        'Tap the map to place the marker, then drag it to refine the location.',
                        style: TextStyle(color: planningMutedTextColor),
                      ),
                    if (_selection != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _selection!.locationLabel,
                        style: const TextStyle(
                          color: planningTextColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (_resolving) ...[
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (_validationMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _validationMessage!,
                        semanticsLabel: _validationMessage,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (!widget.readOnly) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: green,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed:
                            _selection == null || _resolving
                                ? null
                                : () => Navigator.pop(context, _selection),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Use This Location'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectLocation(LatLng point) async {
    if (_resolving) return;
    setState(() {
      _markerPosition = point;
      _selection = null;
      _resolving = true;
      _validationMessage = null;
    });
    try {
      final selection = await _locations.resolve(
        point.latitude,
        point.longitude,
      );
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _resolving = false;
        _validationMessage = selection == null
            ? 'This proposal must be located within Malaysia.'
            : null;
      });
    } catch (error, stackTrace) {
      debugPrint('Proposal location validation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _selection = null;
        _resolving = false;
        _validationMessage =
            'Unable to validate this location. Please try again.';
      });
    }
  }
}
