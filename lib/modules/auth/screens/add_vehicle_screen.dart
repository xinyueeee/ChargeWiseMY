import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/vehicle_catalog_service.dart';
import '../widgets/auth_widgets.dart';

const _labelColor = Color(0xFF1F2937);
const _primaryGreen = Color(0xFF00B894);

class AddVehicleScreen extends StatefulWidget {
  const AddVehicleScreen({super.key});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _vehicleCatalogService = VehicleCatalogService();
  final _customMakeController = TextEditingController();
  final _customModelController = TextEditingController();

  bool _loadingMakes = true;
  bool _submitting = false;
  List<VehicleMake> _makes = const [];
  String? _selectedMake;
  String? _selectedModel;

  @override
  void initState() {
    super.initState();
    _loadMakes();
  }

  Future<void> _loadMakes() async {
    final makes = await _vehicleCatalogService.loadMakes();
    if (!mounted) return;
    setState(() {
      _makes = makes;
      _loadingMakes = false;
    });
  }

  @override
  void dispose() {
    _customMakeController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  List<String> get _modelsForSelectedMake {
    final match = _makes.where((make) => make.name == _selectedMake);
    return match.isEmpty ? const [] : match.first.models;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final make = _selectedMake == 'Other'
        ? _customMakeController.text.trim()
        : _selectedMake!;
    final model = _selectedModel == 'Other'
        ? _customModelController.text.trim()
        : _selectedModel ?? '';

    setState(() => _submitting = true);
    try {
      await _authService.addVehicle(make: make, model: model);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add vehicle. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Vehicle'),
        backgroundColor: Colors.white,
        foregroundColor: _labelColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _loadingMakes
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Vehicle Make',
                        style: TextStyle(
                          color: _labelColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedMake,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          hintText: 'Select make',
                          prefixIcon: Icon(
                            Icons.directions_car_outlined,
                            color: _primaryGreen,
                            size: 20,
                          ),
                        ),
                        items: _makes
                            .map(
                              (make) => DropdownMenuItem(
                                value: make.name,
                                child: Text(make.name),
                              ),
                            )
                            .toList(),
                        validator: (value) =>
                            value == null ? 'Select a make' : null,
                        onChanged: (value) => setState(() {
                          _selectedMake = value;
                          _selectedModel = null;
                          _customModelController.clear();
                          if (value != 'Other') _customMakeController.clear();
                        }),
                      ),
                      if (_selectedMake == 'Other') ...[
                        const SizedBox(height: 16),
                        AuthLabeledField(
                          label: 'Specify Make',
                          controller: _customMakeController,
                          hintText: 'e.g. XPeng',
                          prefixIcon: Icons.edit_outlined,
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter the vehicle make';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_selectedMake != null && _selectedMake != 'Other') ...[
                        const SizedBox(height: 16),
                        const Text(
                          'Vehicle Model',
                          style: TextStyle(
                            color: _labelColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedModel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            hintText: 'Select model',
                            prefixIcon: Icon(
                              Icons.directions_car_filled_outlined,
                              color: _primaryGreen,
                              size: 20,
                            ),
                          ),
                          items: _modelsForSelectedMake
                              .map(
                                (model) => DropdownMenuItem(
                                  value: model,
                                  child: Text(model),
                                ),
                              )
                              .toList(),
                          validator: (value) =>
                              value == null ? 'Select a model' : null,
                          onChanged: (value) =>
                              setState(() => _selectedModel = value),
                        ),
                      ],
                      if (_selectedModel == 'Other') ...[
                        const SizedBox(height: 16),
                        AuthLabeledField(
                          label: 'Specify Model',
                          controller: _customModelController,
                          hintText: 'e.g. G6',
                          prefixIcon: Icons.edit_outlined,
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Enter the vehicle model';
                            }
                            return null;
                          },
                        ),
                      ],
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Add Vehicle'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
