import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/services/auth_service.dart';
import '../../planning/models/proposal.dart';
import '../../planning/widgets/planning_widgets.dart';

Future<void> showStationDetailsSheet(
  BuildContext context, {
  required ChargingStation station,
  required double? distanceKm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _StationDetailsSheet(station: station, distanceKm: distanceKm),
  );
}

class _StationDetailsSheet extends StatefulWidget {
  const _StationDetailsSheet({required this.station, required this.distanceKm});

  final ChargingStation station;
  final double? distanceKm;

  @override
  State<_StationDetailsSheet> createState() => _StationDetailsSheetState();
}

class _StationDetailsSheetState extends State<_StationDetailsSheet> {
  final _authService = AuthService();
  bool _loading = true;
  bool _saved = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final savedIds = await _authService.fetchSavedStationIds();
    if (!mounted) return;
    setState(() {
      _saved = savedIds.contains(widget.station.id);
      _loading = false;
    });
  }

  Future<void> _toggleSaved() async {
    setState(() => _updating = true);
    try {
      if (_saved) {
        await _authService.unsaveStation(widget.station.id);
      } else {
        await _authService.saveStation(widget.station.id);
      }
      if (!mounted) return;
      setState(() => _saved = !_saved);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update favourites. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _navigate() async {
    final station = widget.station;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${station.latitude},${station.longitude}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final address = station.address?.trim();
    final pbt = station.pbt?.trim();
    final state = station.state?.trim();
    final locationContext = <String>[
      if (pbt != null && pbt.isNotEmpty) pbt,
      if (state != null && state.isNotEmpty) state,
    ].join(', ');
    final hasAddress = address != null && address.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFDDE3EA),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              station.name,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: planningTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    station.chargerType,
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (widget.distanceKm != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 15,
                        color: planningMutedTextColor,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${widget.distanceKm!.toStringAsFixed(1)} km away',
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.location_on_outlined,
              label: hasAddress ? 'Address' : 'Location context',
              value: hasAddress
                  ? address
                  : locationContext.isEmpty
                      ? 'Not available'
                      : locationContext,
            ),
            _DetailRow(
              icon: Icons.power_outlined,
              label: 'Installed Chargers',
              value: station.chargerCount?.toString() ?? 'Not available',
            ),
            if (station.acChargerCount != null ||
                station.dcChargerCount != null)
              _DetailRow(
                icon: Icons.electrical_services_outlined,
                label: 'Charger mix',
                value:
                    'AC: ${station.acChargerCount ?? 0} · DC: ${station.dcChargerCount ?? 0}',
              ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _navigate,
              icon: const Icon(Icons.directions),
              label: const Text('Navigate with Google Maps'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50)),
              onPressed: _loading || _updating ? null : _toggleSaved,
              icon: Icon(_saved ? Icons.favorite : Icons.favorite_border),
              label:
                  Text(_saved ? 'Saved to Favourites' : 'Save to Favourites'),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: green.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: green),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Opens Google Maps for turn-by-turn directions to this station.',
                      style: TextStyle(
                          fontSize: 11, color: planningMutedTextColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: green),
                const SizedBox(width: 10),
                Text(label,
                    style: const TextStyle(color: planningMutedTextColor)),
                const Spacer(),
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: planningTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      );
}
