import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../planning/models/proposal.dart';
import '../../planning/screens/proposal_location_map_screen.dart';
import '../../planning/services/proposal_location_service.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../models/fault_report.dart';
import '../services/location_capture_service.dart';
import '../viewmodels/feedback_viewmodel.dart';
import '../widgets/feedback_widgets.dart';
import 'report_submitted_screen.dart';

/// "Report an Issue" (create) and "Edit Report" (`report` supplied) —
/// dual-purpose like `NewProposalScreen`. Create mode GPS auto-captures a
/// starting location (falling back to search or a map pin if that
/// fails/is denied); edit mode pre-fills everything from the existing
/// report instead of re-detecting. All four of the mockup's numbered
/// sections render on one scrollable page (see [ReportStepIndicator]'s doc
/// comment for why).
class NewReportScreen extends StatefulWidget {
  const NewReportScreen({super.key, this.report});

  final FaultReport? report;

  @override
  State<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends State<NewReportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationCapture = LocationCaptureService();
  final _proposalLocations = ProposalLocationService();
  final _imagePicker = ImagePicker();
  final _searchController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactController = TextEditingController();

  bool _preparingLocation = true;
  String? _locationError;
  bool _locationConfirmed = false;
  bool _autoDetected = false;

  double? _latitude;
  double? _longitude;
  String? _stationId;
  String _stationName = '';
  String _address = '';
  String _state = '';
  String _nearestTown = '';
  List<ChargingStation> _searchResults = const [];

  String? _category;

  /// Already-uploaded photo URLs kept from the existing report (edit mode
  /// only) — anything the driver removes comes out of this list.
  List<String> _existingPhotoUrls = [];

  /// Newly picked local files pending upload.
  final List<XFile> _photos = [];

  /// Whether the driver has touched the photo section at all (edit mode
  /// only) — lets a completely untouched edit skip re-uploading/replacing
  /// photos entirely, per `FeedbackRepository.updateReport`'s contract.
  bool _photosTouched = false;

  bool _submitting = false;

  bool get _editing => widget.report != null;
  int get _totalPhotoCount => _existingPhotoUrls.length + _photos.length;

  int get _currentStep {
    if (_submitting) return 2;
    return (_latitude != null && (_locationConfirmed || !_autoDetected))
        ? 1
        : 0;
  }

  @override
  void initState() {
    super.initState();
    final report = widget.report;
    if (report == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _detectLocation());
      return;
    }

    _category = report.category;
    _descriptionController.text = report.description;
    _contactController.text = report.contactInfo ?? '';
    _existingPhotoUrls = List.of(report.photoUrls);
    _stationId = report.stationId;
    _address = report.locationLabel;
    _state = report.state ?? '';
    _nearestTown = report.nearestTown ?? '';
    _latitude = report.latitude;
    _longitude = report.longitude;
    _autoDetected = false;
    _locationConfirmed = true;
    _preparingLocation = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolveStationName());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _descriptionController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _resolveStationName() {
    final stationId = _stationId;
    if (stationId == null || !mounted) return;
    final stations = context.read<PlanningViewModel>().stations;
    final match = stations.where((station) => station.id == stationId);
    if (match.isNotEmpty) {
      setState(() => _stationName = match.first.name);
    }
  }

  Future<void> _detectLocation() async {
    setState(() {
      _preparingLocation = true;
      _locationError = null;
    });
    try {
      final position = await _locationCapture.getCurrentPosition();
      await _applyCoordinates(
        position.latitude,
        position.longitude,
        autoDetected: true,
      );
    } on LocationCaptureException catch (error) {
      if (!mounted) return;
      setState(() {
        _preparingLocation = false;
        _locationError =
            '${error.message} Search or choose a location on the map instead.';
      });
    } catch (error, stackTrace) {
      debugPrint('GPS auto-capture failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _preparingLocation = false;
        _locationError = 'Could not detect your location. Search or choose '
            'a location on the map instead.';
      });
    }
  }

  Future<void> _applyCoordinates(
    double latitude,
    double longitude, {
    required bool autoDetected,
    String? knownStationId,
    String? knownStationName,
  }) async {
    setState(() => _preparingLocation = true);
    final stations = context.read<PlanningViewModel>().stations;
    final nearby = knownStationId != null
        ? null
        : _locationCapture.nearestStation(latitude, longitude, stations);
    ProposalLocationSelection? selection;
    try {
      selection = await _proposalLocations.resolve(latitude, longitude);
    } catch (error, stackTrace) {
      debugPrint('Report location resolution failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _latitude = latitude;
      _longitude = longitude;
      _stationId = knownStationId ?? nearby?.id;
      _stationName = knownStationName ?? nearby?.name ?? '';
      _address = selection?.locationLabel ?? 'Selected location';
      _state = selection?.state ?? '';
      _nearestTown = selection?.nearestTown ?? '';
      _autoDetected = autoDetected;
      _locationConfirmed = false;
      _preparingLocation = false;
      _locationError = selection == null
          ? 'This location is outside the supported Malaysia boundary. '
              'Choose another one.'
          : null;
    });
  }

  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _searchResults = const []);
      return;
    }
    final stations = context.read<PlanningViewModel>().stations;
    setState(() {
      _searchResults = stations
          .where((station) => station.name.toLowerCase().contains(query))
          .take(5)
          .toList();
    });
  }

  Future<void> _selectSearchResult(ChargingStation station) async {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() => _searchResults = const []);
    await _applyCoordinates(
      station.latitude,
      station.longitude,
      autoDetected: false,
      knownStationId: station.id,
      knownStationName: station.name,
    );
  }

  Future<void> _openChangeLocationMap() async {
    final initial = (_latitude != null && _longitude != null)
        ? ProposalLocationSelection(
            latitude: _latitude!,
            longitude: _longitude!,
            state: _state,
            nearestTown: _nearestTown,
            locationLabel: _address,
          )
        : null;
    final selected = await Navigator.push<ProposalLocationSelection>(
      context,
      MaterialPageRoute<ProposalLocationSelection>(
        builder: (_) => ProposalLocationMapScreen(initialSelection: initial),
      ),
    );
    if (selected == null) return;
    await _applyCoordinates(
      selected.latitude,
      selected.longitude,
      autoDetected: false,
    );
  }

  Future<void> _pickPhotos() async {
    final remaining = kFaultReportMaxPhotos - _totalPhotoCount;
    if (remaining <= 0) return;
    try {
      final picked = await _imagePicker.pickMultiImage(
        limit: remaining,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _photos.addAll(picked.take(remaining));
        _photosTouched = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Photo picking failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not select photos. Please try again.'),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      setState(() => _locationError ??=
          'Please set a location for this report before submitting.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please set a location first.')),
      );
      return;
    }

    setState(() => _submitting = true);
    final contact = _contactController.text.trim();
    try {
      if (_editing) {
        final updated = FaultReport(
          id: widget.report!.id,
          category: _category!,
          description: _descriptionController.text.trim(),
          status: widget.report!.status,
          stationId: _stationId,
          contactInfo: contact.isEmpty ? null : contact,
          locationLabel: _address,
          state: _state,
          nearestTown: _nearestTown,
          latitude: _latitude,
          longitude: _longitude,
          userId: widget.report!.userId,
          createdAt: widget.report!.createdAt,
        );
        await context.read<FeedbackViewModel>().updateReport(
              updated,
              _photosTouched ? _photos : null,
              keepPhotoUrls: _existingPhotoUrls,
            );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final draft = FaultReport(
          id: '',
          category: _category!,
          description: _descriptionController.text.trim(),
          status: 'Submitted',
          stationId: _stationId,
          contactInfo: contact.isEmpty ? null : contact,
          locationLabel: _address,
          state: _state,
          nearestTown: _nearestTown,
          latitude: _latitude,
          longitude: _longitude,
        );
        await context.read<FeedbackViewModel>().submitReport(draft, _photos);
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const ReportSubmittedScreen(),
          ),
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Fault report ${_editing ? 'update' : 'submission'} failed: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _editing
                ? 'Could not update report. Please try again.'
                : 'Could not submit report. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _editing ? 'Edit Report' : 'Report an Issue',
                style: planningAppBarTitleStyle,
              ),
              const SizedBox(height: 2),
              Text(
                _editing
                    ? 'Update the details of your report.'
                    : 'Help us keep charging stations reliable for everyone.',
                style: const TextStyle(
                  fontSize: 12,
                  color: planningMutedTextColor,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: planningPagePadding,
              children: [
                ReportStepIndicator(currentStep: _currentStep),
                planningSectionGap,
                _NumberedSectionHeader(
                  number: '1',
                  title: 'Confirm Location',
                  subtitle: _editing
                      ? 'Adjust the location if needed.'
                      : 'We detected your location. Please confirm or '
                          'adjust if needed.',
                ),
                const SizedBox(height: 12),
                _buildLocationCard(),
                planningSectionGap,
                _NumberedSectionHeader(number: '2', title: 'Issue Details'),
                const SizedBox(height: 12),
                _buildFieldLabel('Issue Category', required: true),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.error_outline, color: green),
                    hintText: 'Select issue type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in kFaultReportCategories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  validator: (value) =>
                      value == null ? 'Select an issue category.' : null,
                  onChanged: (value) => setState(() => _category = value),
                ),
                const SizedBox(height: 16),
                _buildFieldLabel('Description', required: true),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    hintText: 'Please describe the issue in detail...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Describe the issue.'
                      : null,
                ),
                planningSectionGap,
                _NumberedSectionHeader(
                  number: '3',
                  title: 'Add Photo',
                  suffix: ' (Optional)',
                  subtitle:
                      'Photos help us understand and resolve the issue faster.',
                  trailing: Text(
                    '$_totalPhotoCount/$kFaultReportMaxPhotos',
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildPhotoPicker(),
                planningSectionGap,
                _NumberedSectionHeader(
                  number: '4',
                  title: 'Contact Information',
                  suffix: ' (Optional)',
                ),
                const SizedBox(height: 8),
                _buildFieldLabel('Phone Number or Email'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _contactController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Enter your contact (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'We may contact you if more information is needed.',
                  style: TextStyle(color: planningMutedTextColor, fontSize: 12),
                ),
                planningSectionGap,
                ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(_editing ? Icons.save_outlined : Icons.send_outlined),
                  label: Text(
                    _submitting
                        ? (_editing ? 'Updating…' : 'Submitting…')
                        : (_editing ? 'Update Report' : 'Submit Report'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );

  Widget _buildFieldLabel(String label, {bool required = false}) => RichText(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: planningTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          children: required
              ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))]
              : null,
        ),
      );

  Widget _buildLocationCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F7F1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_preparingLocation)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                    SizedBox(width: 10),
                    Text('Detecting your location…'),
                  ],
                ),
              )
            else if (_latitude != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 110,
                  child: IgnorePointer(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_latitude!, _longitude!),
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('report_location'),
                          position: LatLng(_latitude!, _longitude!),
                        ),
                      },
                      zoomControlsEnabled: false,
                      myLocationButtonEnabled: false,
                      scrollGesturesEnabled: false,
                      zoomGesturesEnabled: false,
                      rotateGesturesEnabled: false,
                      tiltGesturesEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _autoDetected ? Icons.gps_fixed : Icons.edit_location_alt,
                      size: 13,
                      color: green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _autoDetected ? 'Auto-detected' : 'Selected location',
                      style: const TextStyle(
                        color: green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _stationName.isNotEmpty ? _stationName : _address,
                style: const TextStyle(
                  color: planningTextColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (_stationName.isNotEmpty && _address.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  _address,
                  style: const TextStyle(
                    color: planningMutedTextColor,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 13,
                    color: planningMutedTextColor,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${_latitude!.toStringAsFixed(4)}, '
                    '${_longitude!.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_autoDetected && !_locationConfirmed) ...[
                const Text(
                  'Is this the correct charging station?',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            setState(() => _locationConfirmed = true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Yes, Confirm'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openChangeLocationMap,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('No, Change'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'or',
                        style: TextStyle(color: planningMutedTextColor),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 10),
              ] else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _openChangeLocationMap,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Change Location'),
                  ),
                ),
            ],
            if (_locationError != null) ...[
              const SizedBox(height: 4),
              Text(
                _locationError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
              const SizedBox(height: 10),
            ],
            const Text(
              'Search or enter manually',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search station name, address or place',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: _onSearchChanged,
            ),
            if (_searchResults.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (final station in _searchResults)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.ev_station, color: green),
                        title: Text(station.name),
                        onTap: () => _selectSearchResult(station),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _buildPhotoPicker() {
    if (_totalPhotoCount == 0) {
      return InkWell(
        onTap: _pickPhotos,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: green.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_outlined, color: green),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tap to upload photos',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: planningTextColor,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'You can add up to 3 photos',
                      style: TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 12,
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

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var index = 0; index < _existingPhotoUrls.length; index++)
          _PhotoThumb(
            image: NetworkImage(_existingPhotoUrls[index]),
            onRemove: () => setState(() {
              _existingPhotoUrls.removeAt(index);
              _photosTouched = true;
            }),
          ),
        for (var index = 0; index < _photos.length; index++)
          _PhotoThumb(
            image: FileImage(File(_photos[index].path)),
            onRemove: () => setState(() {
              _photos.removeAt(index);
              _photosTouched = true;
            }),
          ),
        if (_totalPhotoCount < kFaultReportMaxPhotos)
          InkWell(
            onTap: _pickPhotos,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFCBD5E1)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_a_photo_outlined, color: green),
            ),
          ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.image, required this.onRemove});

  final ImageProvider image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image(
              image: image,
              width: 84,
              height: 84,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 84,
                height: 84,
                color: green.withValues(alpha: .1),
                child: const Icon(Icons.broken_image_outlined, color: green),
              ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
}

class _NumberedSectionHeader extends StatelessWidget {
  const _NumberedSectionHeader({
    required this.number,
    required this.title,
    this.suffix,
    this.subtitle,
    this.trailing,
  });

  final String number, title;
  final String? suffix;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: '$number. $title',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    children: suffix == null
                        ? null
                        : [
                            TextSpan(
                              text: suffix,
                              style: const TextStyle(
                                color: planningMutedTextColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(
                color: planningMutedTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ],
      );
}