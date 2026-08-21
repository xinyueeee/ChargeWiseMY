import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../models/proposal.dart';
import '../../widgets/planning_widgets.dart';

class AdminProposalLocationMapScreen extends StatefulWidget {
  AdminProposalLocationMapScreen({
    super.key,
    required this.proposal,
    required this.nearbyStations,
    this.relatedGap,
  }) : assert(
          proposal.latitude != null && proposal.longitude != null,
          'Admin proposal map requires valid proposal coordinates.',
        );

  final Proposal proposal;
  final List<ChargingStation> nearbyStations;
  final GapArea? relatedGap;

  @override
  State<AdminProposalLocationMapScreen> createState() =>
      _AdminProposalLocationMapScreenState();
}

class _AdminProposalLocationMapScreenState
    extends State<AdminProposalLocationMapScreen> {
  late final Set<Marker> _markers;
  late final Set<Circle> _circles;

  @override
  void initState() {
    super.initState();
    _markers = _buildMarkers();
    _circles = _buildCircles();
    debugPrint(
      'Admin proposal map prepared: proposal=${widget.proposal.id}, '
      'nearbyStationMarkers=${widget.nearbyStations.length}, '
      'totalMarkers=${_markers.length}, circles=${_circles.length}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final position = LatLng(proposal.latitude!, proposal.longitude!);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposed Location',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: position, zoom: 12.5),
            mapType: MapType.normal,
            markers: _markers,
            circles: _circles,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            zoomControlsEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            onMapCreated: (_) => debugPrint(
              'Admin proposal Google Map created: proposal=${proposal.id}, '
              'markers=${_markers.length}, circles=${_circles.length}.',
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 18,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proposal.city,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: planningTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${widget.nearbyStations.length} nearby station marker'
                        '${widget.nearbyStations.length == 1 ? '' : 's'} shown within 15 km '
                        '(maximum 80).',
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Set<Marker> _buildMarkers() {
    final proposal = widget.proposal;
    return Set<Marker>.unmodifiable({
      Marker(
        markerId: MarkerId('admin_proposal_${proposal.id}'),
        position: LatLng(proposal.latitude!, proposal.longitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        zIndexInt: 10,
        infoWindow: InfoWindow(
          title: proposal.city,
          snippet: 'Proposed charging-station location',
        ),
      ),
      for (final station in widget.nearbyStations)
        Marker(
          markerId: MarkerId('admin_station_${station.id}'),
          position: LatLng(station.latitude, station.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: station.name,
            snippet: station.planningInfoWindowSnippet,
          ),
        ),
    });
  }

  Set<Circle> _buildCircles() {
    final gap = widget.relatedGap;
    if (gap?.latitude == null || gap?.longitude == null) return const {};
    final validGap = gap!;
    return {
      Circle(
        circleId: CircleId('admin_gap_${validGap.id}'),
        center: LatLng(validGap.latitude!, validGap.longitude!),
        radius: 5000,
        strokeColor: const Color(0xFFE74C3C),
        strokeWidth: 2,
        fillColor: const Color(0x33E74C3C),
      ),
    };
  }
}
