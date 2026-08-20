import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../services/proposal_location_service.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'proposal_location_map_screen.dart';

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
  final ProposalLocationService _locations = ProposalLocationService();
  late final TextEditingController _nameController;
  late final TextEditingController _reasonController;
  late String _demand;
  late String _chargerType;
  ProposalLocationSelection? _selection;
  String? _locationError;
  bool _preparingLocation = false;
  bool _submitting = false;

  bool get _editing => widget.proposal != null;

  @override
  void initState() {
    super.initState();
    final proposal = widget.proposal;
    _nameController = TextEditingController(text: proposal?.city);
    _reasonController = TextEditingController(text: proposal?.description);
    _demand = proposal?.demand ?? 'Medium';
    _chargerType = proposal?.charger ?? 'AC Charger';
    if (proposal?.latitude != null && proposal?.longitude != null) {
      _preparingLocation = true;
      _resolveSavedLocation(proposal!.latitude!, proposal.longitude!);
    }
  }

  Future<void> _resolveSavedLocation(double latitude, double longitude) async {
    try {
      final selection = await _locations.resolve(latitude, longitude);
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _locationError = selection == null
            ? 'The saved location is outside the supported Malaysia boundary. Choose a new location.'
            : null;
        _preparingLocation = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Saved proposal location preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _preparingLocation = false;
        _locationError =
            'Unable to prepare the saved location. Choose the location again.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? 'Edit Proposal' : 'New Proposal',
          style: planningAppBarTitleStyle,
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
                'Proposal details',
                subtitle: 'Required fields are marked with *',
              ),
              const SizedBox(height: 10),
              AppCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        labelText: 'Proposal name *',
                        hintText: 'Example: Kampar community charger',
                        prefixIcon: Icon(Icons.edit_location_alt_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final name = value?.trim() ?? '';
                        if (name.isEmpty) return 'Enter a proposal name.';
                        if (name.length < 3) {
                          return 'Use at least 3 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _chargerType,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Proposal category *',
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
                          : (value) => setState(() => _chargerType = value!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _reasonController,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 6,
                      maxLength: 300,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText:
                            'Explain the infrastructure limitation at this location.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final reason = value?.trim() ?? '';
                        if (reason.isEmpty) {
                          return 'Describe why this location needs a station.';
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
              const PlanningSectionTitle('Location'),
              const SizedBox(height: 10),
              AppCard(child: _buildLocationContent()),
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

  Widget _buildLocationContent() {
    if (_preparingLocation) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Preparing saved location…')),
          ],
        ),
      );
    }
    final selection = _selection;
    if (selection == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.location_on_outlined, color: green),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Choose a point within Malaysia. The state and nearest town will be identified automatically.',
                  style: TextStyle(color: planningMutedTextColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_locationError != null) ...[
            Text(
              _locationError!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
          ],
          OutlinedButton.icon(
            onPressed: _submitting ? null : _chooseLocation,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Choose Location on Map'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          selection.locationLabel,
          style: const TextStyle(
            color: planningTextColor,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _LocationReviewRow(label: 'State', value: selection.state),
        const Divider(height: 1),
        _LocationReviewRow(
          label: 'Nearest town',
          value: selection.nearestTown,
        ),
        const SizedBox(height: 8),
        const Text(
          'Coordinates recorded internally.',
          style: TextStyle(
            color: planningMutedTextColor,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _chooseLocation,
          icon: const Icon(Icons.edit_location_alt_outlined),
          label: const Text('Change Location'),
        ),
      ],
    );
  }

  Future<void> _chooseLocation() async {
    final selected = await Navigator.push<ProposalLocationSelection>(
      context,
      MaterialPageRoute<ProposalLocationSelection>(
        builder: (_) => ProposalLocationMapScreen(
          initialSelection: _selection,
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selection = selected;
        _locationError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final selection = _selection;
    if (selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Choose a valid location within Malaysia.'),
        ),
      );
      return;
    }
    final viewModel = context.read<PlanningViewModel>();
    if (_locations.isDuplicate(
      selection,
      _nameController.text,
      viewModel.proposals,
      excludedProposalId: widget.proposal?.id,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'A proposal with this name already exists at this location.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final existing = widget.proposal;
    final proposal = Proposal(
      id: existing?.id ?? '',
      city: _nameController.text.trim(),
      description: _reasonController.text.trim(),
      supports: existing?.supports ?? 0,
      status: existing?.status ?? 'Pending',
      area: existing?.area ?? 'Residential Area',
      charger: _chargerType,
      distance: existing?.distance ?? 0,
      demand: _demand,
      locationLabel: selection.locationLabel,
      state: selection.state,
      nearestTown: selection.nearestTown,
      createdAt: existing?.createdAt,
      createdBy: existing?.createdBy ?? 'Current user',
      ownerUserId: existing?.ownerUserId,
      latitude: selection.latitude,
      longitude: selection.longitude,
      reaction: existing?.reaction ?? 0,
    );

    try {
      if (_editing) {
        await viewModel.updateProposal(proposal);
      } else {
        await viewModel.submitProposal(proposal);
      }
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
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
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Unable to save the proposal. Check your connection and try again.',
          ),
        ),
      );
    }
  }
}

class _LocationReviewRow extends StatelessWidget {
  const _LocationReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: planningMutedTextColor),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
