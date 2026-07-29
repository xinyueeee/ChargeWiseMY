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

class MapPanel extends StatelessWidget {
  const MapPanel({super.key, this.height = 250, this.gaps = false});
  final double height;
  final bool gaps;
  @override
  Widget build(BuildContext c) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: height,
          child: GoogleMap(
            initialCameraPosition: const CameraPosition(
                target: LatLng(3.1390, 101.6869), zoom: 10.5),
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            markers: {
              Marker(
                  markerId: MarkerId('existing_kl'),
                  position: LatLng(3.1390, 101.6869),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                  infoWindow: InfoWindow(title: 'Existing station')),
              Marker(
                  markerId: MarkerId('proposal_ampang'),
                  position: LatLng(3.1480, 101.7610),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  infoWindow: InfoWindow(title: 'Proposed station')),
              Marker(
                  markerId: const MarkerId('priority_kajang'),
                  position: const LatLng(2.9935, 101.7874),
                  icon: BitmapDescriptor.defaultMarkerWithHue(gaps
                      ? BitmapDescriptor.hueRed
                      : BitmapDescriptor.hueOrange),
                  infoWindow: const InfoWindow(title: 'High priority area')),
            },
          ),
        ),
      );
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
