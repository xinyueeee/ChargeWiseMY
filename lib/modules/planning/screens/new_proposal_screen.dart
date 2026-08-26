import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../services/proposal_location_service.dart';
import '../services/proposal_photo_service.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import '../widgets/proposal_photo_widgets.dart';
import 'proposal_location_map_screen.dart';

class NewProposalScreen extends StatefulWidget {
  const NewProposalScreen({
    super.key,
    this.proposal,
    this.sourceGap,
    this.sourceGapDisplayName,
  });

  final Proposal? proposal;
  final GapArea? sourceGap;
  final String? sourceGapDisplayName;

  @override
  State<NewProposalScreen> createState() => _NewProposalScreenState();
}

class _NewProposalScreenState extends State<NewProposalScreen> {
  final _formKey = GlobalKey<FormState>();
  final ProposalLocationService _locations = ProposalLocationService();
  final ImagePicker _imagePicker = ImagePicker();
  late final TextEditingController _nameController;
  late final TextEditingController _reasonController;
  late String _demand;
  late String _chargerType;
  ProposalLocationSelection? _selection;
  String? _locationError;
  bool _preparingLocation = false;
  bool _submitting = false;
  bool _uploadingPhoto = false;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoExtension;
  String? _selectedPhotoContentType;
  bool _removeExistingPhoto = false;
  String? _acknowledgedPlannedWarningKey;
  bool _formDirty = false;
  bool _allowPop = false;

  static const int _maximumPhotoBytes = 5 * 1024 * 1024;

  bool get _editing => widget.proposal != null;

  @override
  void initState() {
    super.initState();
    final proposal = widget.proposal;
    final gap = widget.sourceGap;
    _nameController = TextEditingController(
      text: proposal?.city ??
          (gap == null
              ? null
              : '${widget.sourceGapDisplayName ?? gap.name} charging location'),
    );
    _reasonController = TextEditingController(
      text: proposal?.description ??
          (gap == null
              ? null
              : 'Coverage-gap analysis identified this as a ${gap.priority.toLowerCase()} priority area. '
                  'The nearest charging location is ${gap.distance.toStringAsFixed(1)} km away.'),
    );
    _demand = proposal?.demand ?? 'Medium';
    _chargerType = proposal?.charger ?? 'AC Charger';
    _nameController.addListener(_markDirty);
    _reasonController.addListener(_markDirty);
    if (proposal?.latitude != null && proposal?.longitude != null) {
      _preparingLocation = true;
      _resolveSavedLocation(proposal!.latitude!, proposal.longitude!);
    } else if (gap?.latitude != null && gap?.longitude != null) {
      _preparingLocation = true;
      _resolveSavedLocation(gap!.latitude!, gap.longitude!);
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
    _nameController.removeListener(_markDirty);
    _reasonController.removeListener(_markDirty);
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing && !widget.proposal!.canOwnerEdit) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Proposal', style: planningAppBarTitleStyle),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: const PlanningEmptyState(
          icon: Icons.lock_outline,
          title: 'This proposal is read-only',
          message:
              'Approved and rejected proposals can be viewed but cannot be edited.',
        ),
      );
    }
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope<bool>(
      canPop: _allowPop || !_formDirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _editing ? 'Cancel editing' : 'Close proposal form',
            onPressed: _submitting ? null : _requestClose,
            icon: const Icon(Icons.close),
          ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape =
                    MediaQuery.orientationOf(context) == Orientation.landscape;
                final wide = constraints.maxWidth >= 900 ||
                    (landscape && constraints.maxWidth >= 650);
                return ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProposalDetailsSection(),
                                planningSectionGap,
                                _buildLocationSection(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildUsageSection(),
                                planningSectionGap,
                                _buildPhotoPlaceholder(),
                                const SizedBox(height: 18),
                                _buildSubmitButton(),
                              ],
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildProposalDetailsSection(),
                      planningSectionGap,
                      _buildLocationSection(),
                      planningSectionGap,
                      _buildUsageSection(),
                      planningSectionGap,
                      _buildPhotoPlaceholder(),
                      const SizedBox(height: 20),
                      _buildSubmitButton(),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _markDirty() {
    _formDirty = true;
  }

  Future<void> _requestClose() async {
    if (_submitting) return;
    if (!_formDirty) {
      _allowPop = true;
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Discard unsaved changes?'),
            content: const Text(
              'Your proposal changes have not been saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep Editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
    if (!discard || !mounted) return;
    _allowPop = true;
    Navigator.of(context).pop();
  }

  Widget _buildProposalDetailsSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    if (name.length < 3) return 'Use at least 3 characters.';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _chargerType,
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
                      : (value) => setState(() {
                            _chargerType = value!;
                            _markDirty();
                          }),
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
        ],
      );

  Widget _buildLocationSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PlanningSectionTitle('Location'),
          const SizedBox(height: 10),
          AppCard(child: _buildLocationContent()),
        ],
      );

  Widget _buildUsageSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                        : (_) => setState(() {
                              _demand = value;
                              _markDirty();
                            }),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _buildPhotoPlaceholder() => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.photo_camera_outlined, color: green),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Site Photo',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Optional',
                  style: TextStyle(
                    color: planningMutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_selectedPhotoBytes != null)
              LocalProposalPhotoPreview(bytes: _selectedPhotoBytes!)
            else if (widget.proposal?.sitePhotoPath != null &&
                !_removeExistingPhoto)
              ProposalSitePhoto(
                storagePath: widget.proposal!.sitePhotoPath!,
                height: 150,
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE1E6EC)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: planningMutedTextColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _removeExistingPhoto
                            ? 'The existing photo will be removed when you save.'
                            : 'Add one clear photo of the proposed site.',
                        style: const TextStyle(
                          color: planningMutedTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _choosePhotoSource,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _selectedPhotoBytes != null ||
                            (widget.proposal?.sitePhotoPath != null &&
                                !_removeExistingPhoto)
                        ? 'Change Photo'
                        : 'Add Photo',
                  ),
                ),
                if (_selectedPhotoBytes != null ||
                    (widget.proposal?.sitePhotoPath != null &&
                        !_removeExistingPhoto))
                  TextButton.icon(
                    onPressed: _submitting ? null : _removePhotoSelection,
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
                if (_removeExistingPhoto && _selectedPhotoBytes == null)
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _removeExistingPhoto = false;
                              _markDirty();
                            }),
                    child: const Text('Undo'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'JPEG, PNG or WebP · maximum 5 MB',
              style: TextStyle(color: planningMutedTextColor, fontSize: 11),
            ),
          ],
        ),
      );

  Widget _buildSubmitButton() => ElevatedButton.icon(
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
          _uploadingPhoto
              ? 'Uploading site photo…'
              : _submitting
                  ? (_editing ? 'Saving changes…' : 'Creating proposal…')
                  : _editing
                      ? 'Save Changes'
                      : 'Submit Proposal',
        ),
      );

  Future<void> _choosePhotoSource() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
        requestFullMetadata: false,
      );
      if (file == null) return;
      final extension = _photoExtension(file.name);
      if (extension == null) {
        _showPhotoMessage('Please choose a JPEG, PNG or WebP image.');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || !_matchesImageSignature(bytes, extension)) {
        _showPhotoMessage('The selected file is not a supported image.');
        return;
      }
      if (bytes.length > _maximumPhotoBytes) {
        _showPhotoMessage('Please choose an image smaller than 5 MB.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _selectedPhotoBytes = bytes;
        _selectedPhotoExtension = extension;
        _selectedPhotoContentType = switch (extension) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        };
        _removeExistingPhoto = false;
        _markDirty();
      });
    } catch (error, stackTrace) {
      debugPrint('Proposal site photo selection failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showPhotoMessage(
          'Unable to access that photo. Check permission and try again.',
        );
      }
    }
  }

  String? _photoExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return null;
    final extension = fileName.substring(dot + 1).toLowerCase();
    if (extension == 'jpg' || extension == 'jpeg') return 'jpg';
    if (extension == 'png' || extension == 'webp') return extension;
    return null;
  }

  bool _matchesImageSignature(Uint8List bytes, String extension) {
    if (extension == 'jpg') {
      return bytes.length >= 3 &&
          bytes[0] == 0xFF &&
          bytes[1] == 0xD8 &&
          bytes[2] == 0xFF;
    }
    if (extension == 'png') {
      const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }
    return bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
  }

  void _removePhotoSelection() => setState(() {
        _selectedPhotoBytes = null;
        _selectedPhotoExtension = null;
        _selectedPhotoContentType = null;
        _removeExistingPhoto = widget.proposal?.sitePhotoPath != null;
        _markDirty();
      });

  void _showPhotoMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
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
        _markDirty();
      });
    }
  }

  Future<void> _submit() async {
    if (_editing && !widget.proposal!.canOwnerEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This proposal is read-only.')),
      );
      return;
    }
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

    final warningKey = '${selection.latitude.toStringAsFixed(5)}|'
        '${selection.longitude.toStringAsFixed(5)}';
    final planned = viewModel.plannedContextAt(
      selection.latitude,
      selection.longitude,
      radiusKm: 2,
    );
    if (_acknowledgedPlannedWarningKey != warningKey &&
        planned.nearestDistanceKm != null &&
        planned.nearestDistanceKm! <= 2) {
      final continueAnyway = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Planned infrastructure nearby'),
          content: Text(
            'MEVnet identifies “${planned.nearestLocation!.name}” as an '
            'official proposed charging location approximately '
            '${planned.nearestDistanceKm!.toStringAsFixed(1)} km from this '
            'site. It is not operational infrastructure. Review the planned '
            'location before submitting a potentially overlapping proposal.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Review Location'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue Anyway'),
            ),
          ],
        ),
      );
      if (continueAnyway != true || !mounted) return;
      _acknowledgedPlannedWarningKey = warningKey;
    }

    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    final existing = widget.proposal;
    final proposal = Proposal(
      id: existing?.id ?? '',
      city: _nameController.text.trim(),
      description: _reasonController.text.trim(),
      supports: existing?.supports ?? 0,
      opposes: existing?.opposes ?? 0,
      status: existing?.status ?? Proposal.statusPending,
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
      sitePhotoPath: existing?.sitePhotoPath,
      latitude: selection.latitude,
      longitude: selection.longitude,
      currentUserReaction: existing?.currentUserReaction,
    );

    try {
      late final String proposalId;
      if (_editing) {
        await viewModel.updateProposal(proposal);
        proposalId = proposal.id;
      } else {
        proposalId = await viewModel.submitProposal(proposal);
      }
      String? photoWarning;
      if (_selectedPhotoBytes != null ||
          (_removeExistingPhoto && existing?.sitePhotoPath != null)) {
        if (mounted) {
          setState(() => _uploadingPhoto = true);
        }
        try {
          if (_selectedPhotoBytes != null) {
            await viewModel.uploadProposalPhoto(
              proposalId: proposalId,
              upload: ProposalPhotoUpload(
                bytes: _selectedPhotoBytes!,
                extension: _selectedPhotoExtension!,
                contentType: _selectedPhotoContentType!,
              ),
              previousPath: existing?.sitePhotoPath,
            );
          } else {
            await viewModel.removeProposalPhoto(
              proposalId: proposalId,
              path: existing!.sitePhotoPath!,
            );
          }
        } catch (error, stackTrace) {
          debugPrint('Optional proposal site photo save failed: $error');
          debugPrintStack(stackTrace: stackTrace);
          photoWarning = _editing
              ? 'Proposal changes were saved, but the site photo could not be updated. Try again from Edit Proposal.'
              : 'Proposal created, but the optional site photo could not be uploaded. Add it later from Edit Proposal.';
        }
      }
      if (!mounted) return;
      _formDirty = false;
      _allowPop = true;
      setState(() {
        _submitting = false;
        _uploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            photoWarning ??
                (_editing
                    ? 'Proposal updated successfully.'
                    : 'Proposal submitted successfully.'),
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('Proposal save failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _uploadingPhoto = false;
      });
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
