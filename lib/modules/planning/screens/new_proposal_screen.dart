import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class NewProposalScreen extends StatefulWidget {
  const NewProposalScreen({
    super.key,
    this.proposal,
  });

  final Proposal? proposal;

  @override
  State<NewProposalScreen> createState() => _NewProposalScreenState();
}

class _NewProposalScreenState extends State<NewProposalScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _reasonController;
  late final TextEditingController _addressController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late List<Proposal> _previewProposals;
  late String _demand;
  late String _chargerType;
  bool _submitting = false;

  bool get _editing => widget.proposal != null;

  @override
  void initState() {
    super.initState();
    final proposal = widget.proposal;
    _reasonController = TextEditingController(text: proposal?.description);
    _addressController = TextEditingController(text: proposal?.city);
    _latitudeController = TextEditingController(
      text: proposal?.latitude?.toStringAsFixed(6) ?? '',
    );
    _longitudeController = TextEditingController(
      text: proposal?.longitude?.toStringAsFixed(6) ?? '',
    );
    _demand = proposal?.demand ?? 'Medium';
    _chargerType = proposal?.charger ?? 'AC Charger';
    _previewProposals = proposal == null
        ? const <Proposal>[]
        : List<Proposal>.unmodifiable([proposal]);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proposal = widget.proposal;
    final initialLatitude = proposal?.latitude ?? 4.2105;
    final initialLongitude = proposal?.longitude ?? 101.9758;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Edit Proposal' : 'New Proposal',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 24),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + keyboardInset),
            children: [
              Text(
                _editing
                    ? 'Update the proposed charging-station information.'
                    : 'Submit a charging-station proposal for community review.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: planningMutedTextColor),
              ),
              planningSectionGap,
              const PlanningSectionTitle(
                'Location',
                subtitle: 'Required fields are marked with *',
              ),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: MapPanel(
                        height: 190,
                        proposals: _previewProposals,
                        onTap: _selectMapLocation,
                        initialTarget: LatLng(
                          initialLatitude,
                          initialLongitude,
                        ),
                        initialZoom: proposal == null ? 5.5 : 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap the map to choose coordinates, or enter them below.',
                      style: TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addressController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Address or area *',
                        hintText: 'Example: Kampar, Perak',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter the proposed address or area.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final latitudeField = _coordinateField(
                          controller: _latitudeController,
                          label: 'Latitude *',
                          minimum: -90,
                          maximum: 90,
                        );
                        final longitudeField = _coordinateField(
                          controller: _longitudeController,
                          label: 'Longitude *',
                          minimum: -180,
                          maximum: 180,
                        );
                        if (constraints.maxWidth < 420) {
                          return Column(
                            children: [
                              latitudeField,
                              const SizedBox(height: 12),
                              longitudeField,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: latitudeField),
                            const SizedBox(width: 12),
                            Expanded(child: longitudeField),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Coordinates are stored to six decimal places for a readable, precise location.',
                      style: TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              planningSectionGap,
              const PlanningSectionTitle('Proposal details'),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      value: _chargerType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Charger type *',
                        prefixIcon: Icon(Icons.electrical_services_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'AC Charger',
                          child: Text('AC Charger'),
                        ),
                        DropdownMenuItem(
                          value: 'DC Fast Charger',
                          child: Text('DC Fast Charger'),
                        ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) =>
                              setState(() => _chargerType = value!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Reason for proposal *',
                        hintText:
                            'Explain the infrastructure limitation at this location.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final reason = value?.trim() ?? '';
                        if (reason.isEmpty) {
                          return 'Explain why this location needs a station.';
                        }
                        if (reason.length < 20) {
                          return 'Provide at least 20 characters of context.';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              planningSectionGap,
              const PlanningSectionTitle(
                'Expected usage',
                subtitle: 'Choose the expected charging usage level',
              ),
              const SizedBox(height: 10),
              AppCard(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in const ['Low', 'Medium', 'High'])
                      ChoiceChip(
                        label: Text(value),
                        selected: _demand == value,
                        selectedColor: green.withValues(alpha: .18),
                        onSelected: _submitting
                            ? null
                            : (_) => setState(() => _demand = value),
                      ),
                  ],
                ),
              ),
              planningSectionGap,
              AppCard(
                child: const Row(
                  children: [
                    Icon(Icons.photo_outlined, color: planningMutedTextColor),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Photo upload is not available yet. You can submit the proposal without a photo.',
                        style: TextStyle(color: planningMutedTextColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_editing ? Icons.save_outlined : Icons.send_outlined),
                label: Text(
                  _submitting
                      ? 'Saving…'
                      : _editing
                          ? 'Save Changes'
                          : 'Submit Proposal',
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Widget _coordinateField({
    required TextEditingController controller,
    required String label,
    required double minimum,
    required double maximum,
  }) =>
      TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d{0,6}')),
        ],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          final coordinate = double.tryParse(value?.trim() ?? '');
          if (coordinate == null) return 'Enter a valid number.';
          if (coordinate < minimum || coordinate > maximum) {
            return 'Must be $minimum to $maximum.';
          }
          return null;
        },
      );

  void _selectMapLocation(LatLng location) {
    if (_submitting) return;
    _latitudeController.text = location.latitude.toStringAsFixed(6);
    _longitudeController.text = location.longitude.toStringAsFixed(6);
    final existing = widget.proposal;
    final preview = Proposal(
      id: existing?.id ?? 'draft_selection',
      city: _addressController.text.trim().isEmpty
          ? 'Selected proposal location'
          : _addressController.text.trim(),
      description: _reasonController.text.trim(),
      supports: existing?.supports ?? 0,
      status: existing?.status ?? 'Pending',
      area: existing?.area ?? 'Residential Area',
      charger: _chargerType,
      distance: existing?.distance ?? 0,
      demand: _demand,
      latitude: location.latitude,
      longitude: location.longitude,
      reaction: existing?.reaction ?? 0,
    );
    setState(() {
      _previewProposals = List<Proposal>.unmodifiable([preview]);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);

    final existing = widget.proposal;
    final proposal = Proposal(
      id: existing?.id ?? '',
      city: _addressController.text.trim(),
      description: _reasonController.text.trim(),
      supports: existing?.supports ?? 0,
      status: existing?.status ?? 'Pending',
      area: existing?.area ?? 'Residential Area',
      charger: _chargerType,
      distance: existing?.distance ?? 0,
      demand: _demand,
      latitude: double.parse(_latitudeController.text.trim()),
      longitude: double.parse(_longitudeController.text.trim()),
      reaction: existing?.reaction ?? 0,
    );

    try {
      final viewModel = context.read<PlanningViewModel>();
      if (_editing) {
        await viewModel.updateProposal(proposal);
      } else {
        await viewModel.submitProposal(proposal);
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? 'Proposal updated successfully.'
                : 'Proposal submitted successfully.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Proposal save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save the proposal. Check your connection and try again.',
          ),
        ),
      );
    }
  }
}
