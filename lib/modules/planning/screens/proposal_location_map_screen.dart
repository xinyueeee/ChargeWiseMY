import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../services/proposal_location_service.dart';
import '../widgets/planning_widgets.dart';

class ProposalLocationMapScreen extends StatefulWidget {
  const ProposalLocationMapScreen({
    super.key,
    this.initialSelection,
    this.readOnly = false,
  });

  final ProposalLocationSelection? initialSelection;
  final bool readOnly;

  @override
  State<ProposalLocationMapScreen> createState() =>
      _ProposalLocationMapScreenState();
}

class _ProposalLocationMapScreenState extends State<ProposalLocationMapScreen> {
  static const _malaysiaCamera = CameraPosition(
    target: LatLng(4.2105, 101.9758),
    zoom: 5.5,
  );

  ProposalLocationService _locations = ProposalLocationService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  GoogleMapController? _mapController;
  Timer? _searchDebounce;
  ProposalLocationSelection? _selection;
  LatLng? _markerPosition;
  Set<Polygon> _boundaries = const {};
  List<ProposalLocationSuggestion> _suggestions = const [];
  bool _loading = true;
  bool _resolving = false;
  bool _searching = false;
  bool _searchAttempted = false;
  String? _validationMessage;
  String? _searchError;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _selection = widget.initialSelection;
    if (_selection != null) {
      _markerPosition = LatLng(
        _selection!.latitude,
        _selection!.longitude,
      );
      _searchController.text = _selection!.locationLabel;
    }
    _prepareMap();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _prepareMap({bool retry = false}) async {
    if (retry) {
      _locations = ProposalLocationService();
      setState(() {
        _loading = true;
        _boundaries = const {};
        _validationMessage = null;
      });
    }
    try {
      await _locations.load();
      final polygons = <Polygon>{};
      for (final region in _locations.stateBoundaries.regions) {
        for (var index = 0; index < region.displayPolygons.length; index++) {
          final rings = region.displayPolygons[index];
          if (rings.isEmpty || rings.first.length < 3) continue;
          polygons.add(
            Polygon(
              polygonId: PolygonId('proposal_boundary_${region.name}_$index'),
              points: [
                for (final point in rings.first)
                  LatLng(point.latitude, point.longitude),
              ],
              strokeColor: green.withValues(alpha: .75),
              strokeWidth: 1,
              fillColor: green.withValues(alpha: .025),
              consumeTapEvents: false,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _boundaries = Set<Polygon>.unmodifiable(polygons);
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Proposal location map preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _validationMessage =
            'Unable to prepare the Malaysia boundary. Please try again.';
      });
    }
  }

  Set<Marker> get _markers {
    final position = _markerPosition;
    if (position == null) return const {};
    return {
      Marker(
        markerId: const MarkerId('proposal_selected_location'),
        position: position,
        draggable: !widget.readOnly,
        onDragEnd: widget.readOnly ? null : _selectLocation,
        infoWindow: InfoWindow(
          title: _selection?.locationLabel ?? 'Selected proposal location',
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final mapUnavailable =
        !_loading && _boundaries.isEmpty && _validationMessage != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.readOnly ? 'Proposal Location' : 'Choose Location',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final landscape = constraints.maxWidth >= 700 &&
                constraints.maxWidth > constraints.maxHeight;
            final map = _buildMap(mapUnavailable);
            final panel = _buildLocationPanel();
            if (landscape) {
              return Row(
                children: [
                  Expanded(flex: 3, child: map),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: (constraints.maxWidth * .4)
                        .clamp(300.0, 390.0)
                        .toDouble(),
                    child: Material(
                      color: Colors.white,
                      child: panel,
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: map),
                if (!mapUnavailable)
                  Material(
                    elevation: 8,
                    color: Colors.white,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .5,
                      ),
                      child: panel,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMap(bool mapUnavailable) {
    if (_loading) {
      return const PlanningLoadingState(
        message: 'Preparing proposal location map…',
      );
    }
    if (mapUnavailable) {
      return PlanningErrorState(
        message: _validationMessage!,
        onRetry: () => _prepareMap(retry: true),
      );
    }
    final initialTarget = _markerPosition;
    return GoogleMap(
      key: const ValueKey('proposal-location-google-map'),
      initialCameraPosition: initialTarget == null
          ? _malaysiaCamera
          : CameraPosition(target: initialTarget, zoom: 13),
      mapType: MapType.normal,
      polygons: _boundaries,
      markers: _markers,
      onTap: widget.readOnly || _resolving ? null : _selectLocation,
      zoomControlsEnabled: true,
      myLocationButtonEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onMapCreated: (controller) {
        _mapController = controller;
        debugPrint(
          'Proposal location map created: readOnly=${widget.readOnly}, '
          'boundaries=${_boundaries.length}.',
        );
      },
    );
  }

  Widget _buildLocationPanel() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        shrinkWrap: true,
        children: [
          if (!widget.readOnly) ...[
            TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                labelText: 'Search location',
                hintText: 'City, district or state in Malaysia',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear location search',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            if (_searching) ...[
              const SizedBox(height: 7),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_searchError != null) ...[
              const SizedBox(height: 7),
              Text(
                _searchError!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 5),
              for (final suggestion in _suggestions)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined, color: green),
                  title: Text(suggestion.name),
                  subtitle: Text(suggestion.state),
                  onTap: () => _applySuggestion(suggestion),
                ),
            ] else if (_searchAttempted &&
                !_searching &&
                _searchError == null) ...[
              const SizedBox(height: 8),
              const Text(
                'No matching Malaysian settlement was found.',
                style: TextStyle(color: planningMutedTextColor),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Select a result, tap the map, or drag the pin to refine the location.',
              style: TextStyle(color: planningMutedTextColor),
            ),
          ] else
            const Text(
              'Saved proposal location',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          if (_selection != null) ...[
            const SizedBox(height: 10),
            Text(
              _selection!.locationLabel,
              style: const TextStyle(
                color: planningTextColor,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${_selection!.latitude.toStringAsFixed(6)}, '
              '${_selection!.longitude.toStringAsFixed(6)}',
              style: const TextStyle(
                color: planningMutedTextColor,
                fontSize: 11,
              ),
            ),
            if (!widget.readOnly)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.edit_location_alt_outlined),
                  label: const Text('Change Location'),
                ),
              ),
          ],
          if (_resolving) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_validationMessage != null && _boundaries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _validationMessage!,
              semanticsLabel: _validationMessage,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (!widget.readOnly) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: green,
                minimumSize: const Size.fromHeight(50),
              ),
              onPressed: _selection == null || _resolving
                  ? null
                  : () => Navigator.pop(context, _selection),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Use This Location'),
            ),
          ],
        ],
      );

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    if (query.length < 2) {
      setState(() {
        _suggestions = const [];
        _searching = false;
        _searchAttempted = false;
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchAttempted = false;
      _searchError = null;
    });
    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      try {
        final results = await _locations.search(query);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _suggestions = results;
          _searching = false;
          _searchAttempted = true;
        });
      } catch (error, stackTrace) {
        debugPrint('Proposal location search failed: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _suggestions = const [];
          _searching = false;
          _searchAttempted = true;
          _searchError = 'Location search is unavailable. Please try again.';
        });
      }
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.clear();
    setState(() {
      _suggestions = const [];
      _searching = false;
      _searchAttempted = false;
      _searchError = null;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _applySuggestion(ProposalLocationSuggestion suggestion) async {
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.text = suggestion.label;
    setState(() {
      _suggestions = const [];
      _searching = false;
      _searchAttempted = false;
      _searchError = null;
    });
    _searchFocus.unfocus();
    final point = LatLng(suggestion.latitude, suggestion.longitude);
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: point, zoom: 14),
      ),
    );
    await _selectLocation(point);
  }

  Future<void> _selectLocation(LatLng point) async {
    if (_resolving) return;
    setState(() {
      _markerPosition = point;
      _selection = null;
      _resolving = true;
      _validationMessage = null;
    });
    try {
      final selection = await _locations.resolve(
        point.latitude,
        point.longitude,
      );
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _resolving = false;
        _validationMessage = selection == null
            ? 'This proposal must be located within Malaysia.'
            : null;
      });
    } catch (error, stackTrace) {
      debugPrint('Proposal location validation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _selection = null;
        _resolving = false;
        _validationMessage =
            'Unable to validate this location. Please try again.';
      });
    }
  }
}
