import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'add_vehicle_screen.dart';

const _labelColor = Color(0xFF1F2937);
const _hintColor = Color(0xFF9AA5B1);
const _primaryGreen = Color(0xFF00B894);

class VehicleListScreen extends StatefulWidget {
  const VehicleListScreen({super.key});

  @override
  State<VehicleListScreen> createState() => _VehicleListScreenState();
}

class _VehicleListScreenState extends State<VehicleListScreen> {
  final _authService = AuthService();
  late Future<List<Map<String, dynamic>>> _vehiclesFuture;

  @override
  void initState() {
    super.initState();
    _vehiclesFuture = _authService.fetchVehicles();
  }

  void _reload() {
    setState(() {
      _vehiclesFuture = _authService.fetchVehicles();
    });
  }

  Future<void> _addVehicle() async {
    final added = await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const AddVehicleScreen()),
    );
    if (added == true) _reload();
  }

  Future<void> _deleteVehicle(String id, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove vehicle?'),
        content: Text('Remove $label from your vehicles.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _authService.deleteVehicle(id);
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove vehicle. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('My Vehicles'),
        backgroundColor: Colors.white,
        foregroundColor: _labelColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _vehiclesFuture,
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
                        'Unable to load vehicles. Check your connection and try again.',
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

            final vehicles = snapshot.data ?? const [];

            return Column(
              children: [
                Expanded(
                  child: vehicles.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.directions_car_outlined,
                                  size: 40,
                                  color: _hintColor,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No vehicles added yet.',
                                  style: TextStyle(color: _hintColor),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: vehicles.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final vehicle = vehicles[index];
                            final id = vehicle['id'] as String;
                            final make = vehicle['make'] as String? ?? '';
                            final model = vehicle['model'] as String? ?? '';
                            final label =
                                [make, model].where((s) => s.isNotEmpty).join(
                                      ' ',
                                    );

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE9EDF3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: _primaryGreen.withValues(
                                        alpha: 0.1,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.directions_car_outlined,
                                      color: _primaryGreen,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      label.isEmpty ? 'Vehicle' : label,
                                      style: const TextStyle(
                                        color: _labelColor,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _deleteVehicle(
                                      id,
                                      label.isEmpty ? 'this vehicle' : label,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: ElevatedButton.icon(
                    onPressed: _addVehicle,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Vehicle'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
