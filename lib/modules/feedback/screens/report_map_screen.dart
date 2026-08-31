import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../models/fault_report.dart';
import '../viewmodels/feedback_viewmodel.dart';
import '../widgets/feedback_widgets.dart';
import 'report_details_screen.dart';

class ReportMapScreen extends StatelessWidget {
  const ReportMapScreen({super.key});

  static const _malaysiaCenter = LatLng(4.2105, 101.9758);

  DriverNavigationConfig _navConfig(BuildContext context) =>
      DriverNavigationConfig(
        currentTab: 'Feedback',
        onHomeTap: () => switchDriverTab(context, DriverTab.home),
        onChargingTap: () => switchDriverTab(context, DriverTab.charging),
        onFeedbackTap: () => Navigator.of(context).pop(),
        onPlanningTap: () => switchDriverTab(context, DriverTab.planning),
        onProfileTap: () => switchDriverTab(context, DriverTab.profile),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Nearby Issues', style: planningAppBarTitleStyle),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: DriverNavigationShell(
          config: _navConfig(context),
          child: SafeArea(
            child: Consumer<FeedbackViewModel>(
              builder: (context, vm, __) {
                if (vm.loading) {
                  return const PlanningLoadingState(
                    message: 'Loading nearby issues…',
                  );
                }
                if (vm.errorMessage != null) {
                  return Padding(
                    padding: planningPagePadding,
                    child: PlanningErrorState(
                      message: vm.errorMessage!,
                      onRetry: vm.load,
                    ),
                  );
                }

                final geolocated = vm.nearbyReports
                    .where((r) => r.latitude != null && r.longitude != null)
                    .toList();
                if (geolocated.isEmpty) {
                  return Padding(
                    padding: planningPagePadding,
                    child: PlanningEmptyState(
                      icon: Icons.map_outlined,
                      title: 'No reports to show',
                      message: 'Reports with a saved location will appear '
                          'here once drivers submit them.',
                      action: OutlinedButton.icon(
                        onPressed: vm.load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                      ),
                    ),
                  );
                }

                return Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: _malaysiaCenter,
                        zoom: 6,
                      ),
                      markers: _buildMarkers(context, geolocated),
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: true,
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _StatusLegend(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        bottomNavigationBar: _navConfig(context).bottomBarFor(context),
      );

  Set<Marker> _buildMarkers(BuildContext context, List<FaultReport> reports) {
    final markers = <Marker>{};
    for (final report in reports) {
      final latitude = report.latitude;
      final longitude = report.longitude;
      if (latitude == null || longitude == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId(report.id),
          position: LatLng(latitude, longitude),
          icon:
              BitmapDescriptor.defaultMarkerWithHue(_markerHue(report.status)),
          infoWindow: InfoWindow(
            title: report.category,
            snippet: '${feedbackStatusLabel(report.status)} · '
                'Tap for details',
            onTap: () => _openDetails(context, report),
          ),
        ),
      );
    }
    return markers;
  }

  double _markerHue(String status) {
    switch (status) {
      case 'Verified':
        return BitmapDescriptor.hueOrange;
      case 'In Progress':
        return BitmapDescriptor.hueAzure;
      case 'Resolved':
        return BitmapDescriptor.hueGreen;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  void _openDetails(BuildContext context, FaultReport report) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailsScreen(report: report),
      ),
    );
  }
}

class _StatusLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _LegendRow(color: red, label: 'Submitted'),
            SizedBox(height: 4),
            _LegendRow(color: orange, label: 'Verified'),
            SizedBox(height: 4),
            _LegendRow(color: blue, label: 'In Progress'),
            SizedBox(height: 4),
            _LegendRow(color: green, label: 'Resolved'),
          ],
        ),
      );
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
