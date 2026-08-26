import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';

const _labelColor = Color(0xFF1F2937);
const _hintColor = Color(0xFF9AA5B1);
const _primaryGreen = Color(0xFF00B894);

class SavedStationsScreen extends StatefulWidget {
  const SavedStationsScreen({super.key});

  @override
  State<SavedStationsScreen> createState() => _SavedStationsScreenState();
}

class _SavedStationsScreenState extends State<SavedStationsScreen> {
  final _authService = AuthService();
  late Future<List<Map<String, dynamic>>> _savedFuture;

  @override
  void initState() {
    super.initState();
    _savedFuture = _authService.fetchSavedStationsWithDetails();
  }

  void _reload() {
    setState(() {
      _savedFuture = _authService.fetchSavedStationsWithDetails();
    });
  }

  Future<void> _unsave(String stationId, String label) async {
    try {
      await _authService.unsaveStation(stationId);
      _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove favourite. Please try again.'),
        ),
      );
    }
  }

  Future<void> _navigate(double latitude, double longitude) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude',
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Saved Stations'),
        backgroundColor: Colors.white,
        foregroundColor: _labelColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _savedFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      const Text(
                        'Unable to load saved stations. Check your connection '
                        'and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final saved = snapshot.data ?? const [];
            if (saved.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.favorite_border,
                        size: 40,
                        color: _hintColor,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No saved stations yet.',
                        style: TextStyle(color: _hintColor),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: saved.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final row = saved[index];
                final stationId = row['station_id'] as String;
                final station =
                    row['charging_stations'] as Map<String, dynamic>?;
                final name =
                    station?['station_name'] as String? ?? 'Charging station';
                final address = (station?['address'] as String?)?.trim();
                final chargerType = station?['charger_type'] as String? ?? '';
                final latitude = (station?['latitude'] as num?)?.toDouble();
                final longitude = (station?['longitude'] as num?)?.toDouble();

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE9EDF3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _primaryGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.ev_station_outlined,
                          color: _primaryGreen,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: _labelColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (chargerType.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                chargerType,
                                style: const TextStyle(
                                  color: _hintColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (address != null && address.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _hintColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (latitude != null && longitude != null)
                        IconButton(
                          onPressed: () => _navigate(latitude, longitude),
                          icon: const Icon(
                            Icons.directions_outlined,
                            color: _primaryGreen,
                          ),
                        ),
                      IconButton(
                        onPressed: () => _unsave(stationId, name),
                        icon: const Icon(
                          Icons.favorite,
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
