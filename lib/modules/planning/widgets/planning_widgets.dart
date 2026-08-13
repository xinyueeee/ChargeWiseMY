import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/proposal.dart';
import '../services/state_boundary_service.dart';

const green = Color(0xFF00B894);
const blue = Color(0xFF2F80ED);
const planningTextColor = Color(0xFF101B40);
const planningMutedTextColor = Color(0xFF5F6B82);
const planningPagePadding = EdgeInsets.symmetric(horizontal: 20, vertical: 16);
const planningSectionGap = SizedBox(height: 20);
const planningAppBarTitleStyle = TextStyle(
  color: planningTextColor,
  fontSize: 22,
  fontWeight: FontWeight.w700,
);

class PlanningSectionTitle extends StatelessWidget {
  const PlanningSectionTitle(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: planningTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: planningMutedTextColor,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      );
}

class PlanningLoadingState extends StatelessWidget {
  const PlanningLoadingState({
    super.key,
    this.message = 'Loading planning data…',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: planningMutedTextColor),
              ),
            ],
          ),
        ),
      );
}

class PlanningErrorState extends StatelessWidget {
  const PlanningErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: planningPagePadding,
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, color: Colors.red),
                const SizedBox(height: 10),
                Text(message, textAlign: TextAlign.center),
                if (onRetry != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class AnalysisStatusPanel extends StatelessWidget {
  const AnalysisStatusPanel({
    super.key,
    required this.message,
    required this.analyzing,
    required this.hasError,
    this.onRetry,
  });

  final String message;
  final bool analyzing;
  final bool hasError;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final color = hasError
        ? Colors.red
        : analyzing
            ? blue
            : green;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (analyzing)
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.3,
                color: color,
              ),
            )
          else
            Icon(
              hasError ? Icons.error_outline : Icons.check_circle_outline,
              color: color,
              size: 21,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: hasError ? Colors.red.shade700 : planningTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (hasError && onRetry != null)
            TextButton(
              onPressed: analyzing ? null : onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

class PlanningEmptyState extends StatelessWidget {
  const PlanningEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: planningMutedTextColor),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: planningMutedTextColor),
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                action!,
              ],
            ],
          ),
        ),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE9EDF3)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 8,
              offset: Offset(0, 3),
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
    this.width = 155,
  });
  final String value, label;
  final IconData icon;
  final Color color;
  final double width;
  @override
  Widget build(BuildContext c) => Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .14)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
}

/// A label/value row for a details-screen "information" card. Shared,
/// public version of the pattern `proposal_details_screen.dart` already
/// has privately — kept separate rather than reusing that private class
/// (which isn't importable) or editing Module 2's file for a Module 3 need.
class InformationRow extends StatelessWidget {
  const InformationRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

/// Two action buttons, side by side, that stack vertically on a narrow
/// screen or when text scaling is large. Same responsive rule as the
/// private version in `proposal_details_screen.dart`.
class ResponsiveButtonPair extends StatelessWidget {
  const ResponsiveButtonPair({
    super.key,
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final useVerticalLayout = constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.25;
          if (useVerticalLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 10), second],
            );
          }
          return Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          );
        },
      );
}

typedef StateSelectionCallback = void Function(String state, String source);

class MapPanel extends StatefulWidget {
  const MapPanel({
    super.key,
    this.height = 250,
    this.gaps = false,
    this.stations = const [],
    this.proposals = const [],
    this.priorityAreas = const [],
    this.stateRegions = const [],
    this.stateOverviews = const [],
    this.selectedState = malaysiaSelection,
    this.focusBounds,
    this.analysisCacheHit,
    this.initialTarget = const LatLng(4.2105, 101.9758),
    this.initialZoom = 6.5,
    this.mapPadding = const EdgeInsets.all(12),
    this.onTap,
    this.onStateSelected,
  });
  final double height;
  final bool gaps;
  final List<ChargingStation> stations;
  final List<Proposal> proposals;
  final List<GapArea> priorityAreas;
  final List<StateRegion> stateRegions;
  final List<StateOverviewSummary> stateOverviews;
  final String selectedState;
  final GeoBounds? focusBounds;
  final bool? analysisCacheHit;
  final LatLng initialTarget;
  final double initialZoom;
  final EdgeInsets mapPadding;
  final ValueChanged<LatLng>? onTap;
  final StateSelectionCallback? onStateSelected;

  @override
  State<MapPanel> createState() => _MapPanelState();
}

enum _StationPresentationTier { national, medium, individual }

class _MapPanelState extends State<MapPanel> {
  static int _mountedPanelCount = 0;
  static int _createdPlatformViewCount = 0;
  static const ClusterManagerId _existingStationsClusterId =
      ClusterManagerId('existing_stations');

  static final Set<ClusterManager> _clusterManagers = <ClusterManager>{
    ClusterManager(
      clusterManagerId: _existingStationsClusterId,
    ),
  };

  static List<Proposal>? _cachedProposalSource;
  static Set<Marker> _cachedProposalMarkers = const {};

  static const double _enterMediumZoom = 7.2;
  static const double _returnNationalZoom = 6.8;
  static const double _enterIndividualZoom = 11.2;
  static const double _returnMediumZoom = 10.8;
  static const double _nationalGridDegrees = 2;
  static const double _mediumGridDegrees = .35;
  static const int _nationalMarkerLimit = 80;
  static const int _mediumMarkerLimit = 250;
  static const int _closeMarkerLimit = 500;
  static const double _viewportPaddingRatio = .12;

  _MarkerIcons? _icons;
  Set<Marker> _markers = const {};
  Set<Marker> _renderedProposalMarkers = const {};
  Set<Circle> _priorityCircles = const {};
  Set<Polygon> _statePolygons = const {};
  Set<Marker> _nationalStateMarkers = const {};
  Map<String, Marker> _visibleStationMarkers = const {};
  Map<String, _StationAggregate> _nationalAggregates = const {};
  Map<String, _StationAggregate> _mediumAggregates = const {};
  Map<String, Marker> _aggregateMarkerCache = const {};
  List<Proposal>? _lightweightProposalSource;
  Set<Marker> _lightweightProposalMarkers = const {};
  GoogleMapController? _mapController;
  List<ChargingStation>? _lastProcessedStationSource;
  List<ChargingStation>? _aggregateStationSource;
  _StationPresentationTier _presentationTier =
      _StationPresentationTier.national;
  bool _visibleRefreshRunning = false;
  bool _visibleRefreshPending = false;
  bool _forceNextVisibleRefresh = false;
  int _stationDataGeneration = 0;
  int _lastVisibleStationCount = 0;
  int _lastSpatialBucketCount = 0;
  bool _preparingMarkers = true;
  bool _platformViewCreated = false;
  int _stateBadgeGeneration = 0;
  String? _mapError;
  int _buildCount = 0;
  late final int _instanceId;

  String get _mapMode => widget.gaps
      ? 'priority-focused'
      : widget.selectedState == malaysiaSelection
          ? 'national-state-overview'
          : widget.stations.isEmpty
              ? 'lightweight-proposal'
              : 'dashboard-clustered';

  @override
  void initState() {
    super.initState();
    _instanceId = identityHashCode(this);
    _mountedPanelCount++;
    _statePolygons = _buildStatePolygons();
    debugPrint(
      'MapPanel initState: instance=$_instanceId, '
      'mode=$_mapMode, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    if (widget.gaps) {
      _markers = const {};
      _priorityCircles = _buildPriorityCircles();
      _preparingMarkers = false;
      debugPrint(
        'Gap Analysis map overlay preparation: '
        'rawStations=${widget.stations.length}, '
        'finalMarkers=0, clusterAssignedMarkers=0, '
        'priorityCircles=${_priorityCircles.length}, '
        'markerGenerationDuration=0ms.',
      );
    } else {
      _loadIconsAndOverlays();
    }
  }

  @override
  void dispose() {
    _stationDataGeneration++;
    final controller = _mapController;
    _mapController = null;
    controller?.dispose();
    if (_platformViewCreated) {
      _createdPlatformViewCount--;
    }
    _mountedPanelCount--;
    debugPrint(
      'MapPanel dispose: instance=$_instanceId, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MapPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged = oldWidget.selectedState != widget.selectedState;
    final stateOverviewDataChanged =
        !identical(oldWidget.stateOverviews, widget.stateOverviews);
    if (selectionChanged || stateOverviewDataChanged) {
      _stateBadgeGeneration++;
    }
    if (!identical(oldWidget.stateRegions, widget.stateRegions) ||
        selectionChanged) {
      _statePolygons = _buildStatePolygons();
    }
    if (selectionChanged ||
        oldWidget.focusBounds != widget.focusBounds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusSelectedRegion(reason: 'state-selection-change');
      });
    }
    if (widget.gaps) {
      _markers = const {};
      if (!identical(oldWidget.priorityAreas, widget.priorityAreas)) {
        _priorityCircles = _buildPriorityCircles();
      }
      return;
    }
    _prepareOverlays(
      selectionChanged: selectionChanged,
      stateOverviewDataChanged: stateOverviewDataChanged,
      stationDataChanged: !identical(oldWidget.stations, widget.stations),
      proposalDataChanged: !identical(oldWidget.proposals, widget.proposals),
      priorityDataChanged:
          !identical(oldWidget.priorityAreas, widget.priorityAreas),
    );
  }

  Future<void> _loadIconsAndOverlays() async {
    try {
      final icons = await _MarkerIcons.load();
      if (!mounted) return;
      _icons = icons;
      _prepareOverlays(force: true);
    } catch (error, stackTrace) {
      debugPrint('Map marker icon load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _mapError =
            'Some map symbols could not be prepared. The base map is still available.';
      }
    } finally {
      if (mounted &&
          (widget.selectedState != malaysiaSelection || _icons == null)) {
        setState(() => _preparingMarkers = false);
      }
    }
  }

  void _prepareOverlays({
    bool force = false,
    bool selectionChanged = false,
    bool stateOverviewDataChanged = false,
    bool stationDataChanged = false,
    bool proposalDataChanged = false,
    bool priorityDataChanged = false,
  }) {
    if (_icons == null) return;

    if (widget.selectedState == malaysiaSelection) {
      _visibleStationMarkers = const {};
      _renderedProposalMarkers = const {};
      _priorityCircles = const {};
      if (force || selectionChanged || stateOverviewDataChanged) {
        _markers = const {};
        _requestNationalStateMarkers();
      }
      return;
    }

    if (selectionChanged) {
      _nationalStateMarkers = const {};
      _visibleStationMarkers = const {};
      _markers = const {};
      _preparingMarkers = false;
    }

    if (widget.stations.isEmpty) {
      if (force || proposalDataChanged) {
        _markers = _buildLightweightProposalMarkers();
      }
    } else {
      if (force || proposalDataChanged) {
        _renderedProposalMarkers = _proposalMarkers();
        _markers = _combineRenderedMarkers();
      }
      if (force || stationDataChanged) {
        _stationDataGeneration++;
        _forceNextVisibleRefresh = true;
        _requestVisibleStationRefresh(
          reason: force ? 'initial-data' : 'station-data-change',
        );
      }
    }
    if (force || priorityDataChanged) {
      _priorityCircles = _buildPriorityCircles();
    }
  }

  void _requestNationalStateMarkers() {
    final icons = _icons;
    if (!mounted ||
        icons == null ||
        widget.selectedState != malaysiaSelection) {
      return;
    }
    final generation = ++_stateBadgeGeneration;
    final summaries = widget.stateOverviews;
    _preparingMarkers = true;
    Future.wait([
      for (final summary in summaries)
        icons.stateBadgeForCount(summary.existingStationCount).then(
              (icon) => Marker(
                markerId: MarkerId('state_count_${summary.name}'),
                position: LatLng(
                  summary.labelPoint.latitude,
                  summary.labelPoint.longitude,
                ),
                icon: icon,
                anchor: const Offset(.5, .5),
                zIndexInt: 5,
                infoWindow: InfoWindow(
                  title: summary.name,
                  snippet: '${summary.existingStationCount} existing stations · '
                      '${summary.proposedStationCount} proposed\n'
                      '${summary.priorityAreaCount == null ? 'Priority analysis not run' : '${summary.priorityAreaCount} priority areas'}\n'
                      'Tap to explore this state',
                ),
                onTap: () => widget.onStateSelected?.call(
                  summary.name,
                  'state-badge-tap',
                ),
              ),
            ),
    ]).then((markers) {
      if (!mounted ||
          generation != _stateBadgeGeneration ||
          widget.selectedState != malaysiaSelection ||
          !identical(summaries, widget.stateOverviews)) {
        return;
      }
      final markerSet = Set<Marker>.unmodifiable(markers);
      setState(() {
        _nationalStateMarkers = markerSet;
        _markers = markerSet;
        _preparingMarkers = false;
      });
      debugPrint(
        'National overview markers prepared: '
        'polygons=${_statePolygons.length}, '
        'stateBadges=${markerSet.length}, stationLevelMarkers=0, '
        'cachedStationTotal=${summaries.fold<int>(0, (sum, item) => sum + item.existingStationCount)}.',
      );
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('National state badge preparation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted && generation == _stateBadgeGeneration) {
        setState(() {
          _preparingMarkers = false;
          _mapError = 'State count badges could not be prepared.';
        });
      }
    });
  }

  Set<Marker> _combineRenderedMarkers() => Set<Marker>.unmodifiable({
        ..._visibleStationMarkers.values,
        ..._renderedProposalMarkers,
      });

  Set<Marker> _buildLightweightProposalMarkers() {
    if (identical(_lightweightProposalSource, widget.proposals)) {
      return _lightweightProposalMarkers;
    }
    final stopwatch = Stopwatch()..start();
    final markers = <Marker>{};
    for (final proposal in widget.proposals) {
      if (proposal.latitude == null || proposal.longitude == null) continue;
      markers.add(
        Marker(
          markerId: MarkerId('proposal_${proposal.id}'),
          position: LatLng(proposal.latitude!, proposal.longitude!),
          icon: _icons!.proposal,
          infoWindow: InfoWindow(
            title: proposal.city,
            snippet: proposal.state == null
                ? 'Proposed station · ${proposal.status}'
                : '${proposal.status} · ${proposal.state}',
          ),
        ),
      );
    }
    stopwatch.stop();
    _lightweightProposalSource = widget.proposals;
    _lightweightProposalMarkers = Set<Marker>.unmodifiable(markers);
    debugPrint(
      'Map diagnostics: lightweight proposal markers='
      '${markers.length}, duration=${stopwatch.elapsedMilliseconds}ms; '
      'dashboard marker cache preserved.',
    );
    return _lightweightProposalMarkers;
  }

  void _requestVisibleStationRefresh({required String reason}) {
    if (!mounted ||
        widget.gaps ||
        widget.stations.isEmpty ||
        _icons == null ||
        _mapController == null) {
      return;
    }
    if (_visibleRefreshRunning) {
      _visibleRefreshPending = true;
      return;
    }
    _refreshVisibleStationMarkers(reason: reason);
  }

  Future<void> _refreshVisibleStationMarkers({required String reason}) async {
    _visibleRefreshRunning = true;
    var refreshReason = reason;
    try {
      do {
        _visibleRefreshPending = false;
        final controller = _mapController;
        if (!mounted || controller == null || _icons == null) break;

        final stationSource = widget.stations;
        final generation = _stationDataGeneration;
        final stopwatch = Stopwatch()..start();
        try {
          final bounds = await controller.getVisibleRegion();
          final zoom = await controller.getZoomLevel();
          if (!mounted ||
              !identical(controller, _mapController) ||
              generation != _stationDataGeneration ||
              !identical(stationSource, widget.stations)) {
            _visibleRefreshPending = true;
            refreshReason = 'stale-result-retry';
            continue;
          }

          final paddedBounds = _PaddedMapBounds.fromVisibleRegion(
            bounds,
            paddingRatio: _viewportPaddingRatio,
          );
          final tier = _resolvePresentationTier(zoom);
          final forceRefresh = _forceNextVisibleRefresh;
          _forceNextVisibleRefresh = false;
          if (!identical(_aggregateStationSource, stationSource)) {
            _rebuildFixedAggregates(stationSource);
          }

          final selection = tier == _StationPresentationTier.national
              ? _selectAggregateMarkers(
                  tier: tier,
                  bounds: paddedBounds,
                  aggregates: _nationalAggregates,
                  markerLimit: _nationalMarkerLimit,
                )
              : tier == _StationPresentationTier.medium
                  ? _selectAggregateMarkers(
                      tier: tier,
                      bounds: paddedBounds,
                      aggregates: _mediumAggregates,
                      markerLimit: _mediumMarkerLimit,
                    )
                  : _selectIndividualMarkers(
                      stationSource,
                      paddedBounds,
                      _closeMarkerLimit,
                    );

          final sourceUnchanged =
              identical(_lastProcessedStationSource, stationSource);
          final tierUnchanged = tier == _presentationTier;
          final markerIdsUnchanged = setEquals(
            selection.markers.keys.toSet(),
            _visibleStationMarkers.keys.toSet(),
          );
          _lastProcessedStationSource = stationSource;
          _lastVisibleStationCount = selection.visibleBeforeLimit;
          _lastSpatialBucketCount = selection.spatialBuckets;

          if (sourceUnchanged &&
              tierUnchanged &&
              markerIdsUnchanged &&
              !forceRefresh) {
            stopwatch.stop();
            _logVisibleMarkerUpdate(
              reason: refreshReason,
              zoom: zoom,
              tier: tier,
              visibleBeforeLimit: selection.visibleBeforeLimit,
              stationMarkersAfterLimit: selection.markers.length,
              aggregateMarkers: selection.aggregateMarkers,
              clusterAssignedMarkers: selection.clusterAssignedMarkers,
              spatialBuckets: selection.spatialBuckets,
              durationMs: stopwatch.elapsedMilliseconds,
              applied: false,
              skipReason: 'fixed cells unchanged',
            );
            continue;
          }

          final combinedMarkers = Set<Marker>.unmodifiable({
            ...selection.markers.values,
            ..._renderedProposalMarkers,
          });
          if (!mounted ||
              generation != _stationDataGeneration ||
              !identical(stationSource, widget.stations)) {
            _visibleRefreshPending = true;
            refreshReason = 'post-calculation-retry';
            continue;
          }

          setState(() {
            _presentationTier = tier;
            _visibleStationMarkers = selection.markers;
            _markers = combinedMarkers;
          });
          stopwatch.stop();
          _logVisibleMarkerUpdate(
            reason: refreshReason,
            zoom: zoom,
            tier: tier,
            visibleBeforeLimit: selection.visibleBeforeLimit,
            stationMarkersAfterLimit: selection.markers.length,
            aggregateMarkers: selection.aggregateMarkers,
            clusterAssignedMarkers: selection.clusterAssignedMarkers,
            spatialBuckets: selection.spatialBuckets,
            durationMs: stopwatch.elapsedMilliseconds,
            applied: true,
          );
        } catch (error, stackTrace) {
          stopwatch.stop();
          debugPrint(
            'Visible marker refresh failed: reason=$refreshReason, '
            'duration=${stopwatch.elapsedMilliseconds}ms, error=$error.',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
      } while (_visibleRefreshPending && mounted);
    } finally {
      _visibleRefreshRunning = false;
      if (_visibleRefreshPending && mounted) {
        _visibleRefreshPending = false;
        _requestVisibleStationRefresh(reason: 'queued-refresh');
      }
    }
  }

  _StationPresentationTier _resolvePresentationTier(double zoom) {
    switch (_presentationTier) {
      case _StationPresentationTier.national:
        if (zoom > _enterIndividualZoom) {
          return _StationPresentationTier.individual;
        }
        if (zoom > _enterMediumZoom) {
          return _StationPresentationTier.medium;
        }
        return _StationPresentationTier.national;
      case _StationPresentationTier.medium:
        if (zoom < _returnNationalZoom) {
          return _StationPresentationTier.national;
        }
        if (zoom > _enterIndividualZoom) {
          return _StationPresentationTier.individual;
        }
        return _StationPresentationTier.medium;
      case _StationPresentationTier.individual:
        if (zoom < _returnNationalZoom) {
          return _StationPresentationTier.national;
        }
        if (zoom < _returnMediumZoom) {
          return _StationPresentationTier.medium;
        }
        return _StationPresentationTier.individual;
    }
  }

  void _rebuildFixedAggregates(List<ChargingStation> stations) {
    final stopwatch = Stopwatch()..start();
    _nationalAggregates = _buildFixedAggregates(
      stations,
      _nationalGridDegrees,
    );
    _mediumAggregates = _buildFixedAggregates(
      stations,
      _mediumGridDegrees,
    );
    _aggregateMarkerCache = const {};
    _aggregateStationSource = stations;
    stopwatch.stop();
    debugPrint(
      'Stable station aggregation rebuilt: rawStations=${stations.length}, '
      'nationalCells=${_nationalAggregates.length}, '
      'mediumCells=${_mediumAggregates.length}, '
      'duration=${stopwatch.elapsedMilliseconds}ms.',
    );
  }

  Map<String, _StationAggregate> _buildFixedAggregates(
    List<ChargingStation> stations,
    double cellSize,
  ) {
    final accumulators = <String, _StationAggregateAccumulator>{};
    for (final station in stations) {
      final cell = _fixedGridCell(
        station.latitude,
        station.longitude,
        cellSize,
      );
      accumulators
          .putIfAbsent(
            cell.key,
            () => _StationAggregateAccumulator(
              key: cell.key,
            ),
          )
          .add(station);
    }
    return Map<String, _StationAggregate>.unmodifiable({
      for (final entry in accumulators.entries)
        entry.key: entry.value.complete(),
    });
  }

  _RenderedStationSelection _selectAggregateMarkers({
    required _StationPresentationTier tier,
    required _PaddedMapBounds bounds,
    required Map<String, _StationAggregate> aggregates,
    required int markerLimit,
  }) {
    final visible = aggregates.values
        .where(
          (aggregate) =>
              bounds.contains(aggregate.latitude, aggregate.longitude),
        )
        .toList(growable: false);
    final limited = List<_StationAggregate>.of(visible);
    if (limited.length > markerLimit) {
      limited.sort((a, b) {
        final countComparison = b.count.compareTo(a.count);
        return countComparison != 0
            ? countComparison
            : a.key.compareTo(b.key);
      });
      limited.removeRange(markerLimit, limited.length);
    }
    limited.sort((a, b) => a.key.compareTo(b.key));

    final markerCache = Map<String, Marker>.of(_aggregateMarkerCache);
    final markers = <String, Marker>{};
    for (final aggregate in limited) {
      final markerKey = 'station_aggregate_${tier.name}_${aggregate.key}';
      markers[markerKey] = markerCache.putIfAbsent(
        markerKey,
        () => Marker(
          markerId: MarkerId(markerKey),
          position: LatLng(aggregate.latitude, aggregate.longitude),
          icon: _icons!.aggregateForCount(aggregate.count),
          infoWindow: InfoWindow(
            title: '${aggregate.count} existing stations',
            snippet: tier == _StationPresentationTier.national
                ? 'National overview'
                : 'Regional overview',
          ),
        ),
      );
    }
    _aggregateMarkerCache = Map<String, Marker>.unmodifiable(markerCache);
    return _RenderedStationSelection(
      markers: Map<String, Marker>.unmodifiable(markers),
      visibleBeforeLimit: visible.fold<int>(
        0,
        (total, aggregate) => total + aggregate.count,
      ),
      aggregateMarkers: markers.length,
      clusterAssignedMarkers: 0,
      spatialBuckets: aggregates.length,
    );
  }

  _RenderedStationSelection _selectIndividualMarkers(
    List<ChargingStation> stations,
    _PaddedMapBounds bounds,
    int markerLimit,
  ) {
    final visible = <ChargingStation>[];
    for (final station in stations) {
      if (bounds.contains(station.latitude, station.longitude)) {
        visible.add(station);
      }
    }
    final stableSample = _stableIndividualSample(visible, markerLimit);
    final sourceUnchanged =
        identical(_lastProcessedStationSource, stations);
    final markers = <String, Marker>{};
    for (final station in stableSample.stations) {
      final markerKey = 'station_${station.id}';
      markers[markerKey] = sourceUnchanged
          ? _visibleStationMarkers[markerKey] ??
              _createStationMarker(station)
          : _createStationMarker(station);
    }
    return _RenderedStationSelection(
      markers: Map<String, Marker>.unmodifiable(markers),
      visibleBeforeLimit: visible.length,
      aggregateMarkers: 0,
      clusterAssignedMarkers: markers.length,
      spatialBuckets: stableSample.spatialBuckets,
    );
  }

  _StableStationSample _stableIndividualSample(
    List<ChargingStation> visible,
    int markerLimit,
  ) {
    if (visible.length <= markerLimit) {
      return _StableStationSample(
        stations: List<ChargingStation>.unmodifiable(visible),
        spatialBuckets: 0,
      );
    }

    var cellSize = .02;
    while (true) {
      final representatives =
          <String, _StationBucketRepresentative>{};
      for (final station in visible) {
        final cell = _fixedGridCell(
          station.latitude,
          station.longitude,
          cellSize,
        );
        final latitudeDelta = station.latitude - cell.centerLatitude;
        final longitudeDelta = station.longitude - cell.centerLongitude;
        final distanceSquared = latitudeDelta * latitudeDelta +
            longitudeDelta * longitudeDelta;
        final current = representatives[cell.key];
        if (current == null ||
            distanceSquared < current.distanceSquared ||
            (distanceSquared == current.distanceSquared &&
                station.id.compareTo(current.station.id) < 0)) {
          representatives[cell.key] = _StationBucketRepresentative(
            station: station,
            distanceSquared: distanceSquared,
          );
        }
      }
      if (representatives.length <= markerLimit) {
        final selected = representatives.values
            .map((representative) => representative.station)
            .toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
        return _StableStationSample(
          stations: List<ChargingStation>.unmodifiable(selected),
          spatialBuckets: representatives.length,
        );
      }
      cellSize *= 2;
    }
  }

  _FixedGridCell _fixedGridCell(
    double latitude,
    double longitude,
    double cellSize,
  ) {
    final latitudeIndex = ((latitude + 90) / cellSize).floor();
    final longitudeIndex = ((longitude + 180) / cellSize).floor();
    return _FixedGridCell(
      key: '${latitudeIndex}_$longitudeIndex',
      centerLatitude: -90 + (latitudeIndex + .5) * cellSize,
      centerLongitude: -180 + (longitudeIndex + .5) * cellSize,
    );
  }

  Marker _createStationMarker(ChargingStation station) => Marker(
        markerId: MarkerId('station_${station.id}'),
        position: LatLng(station.latitude, station.longitude),
        icon: _icons!.station,
        clusterManagerId: _existingStationsClusterId,
        infoWindow: InfoWindow(
          title: station.name,
          snippet: station.chargerType,
        ),
      );

  void _logVisibleMarkerUpdate({
    required String reason,
    required double zoom,
    required _StationPresentationTier tier,
    required int visibleBeforeLimit,
    required int stationMarkersAfterLimit,
    required int aggregateMarkers,
    required int clusterAssignedMarkers,
    required int spatialBuckets,
    required int durationMs,
    required bool applied,
    String? skipReason,
  }) {
    final totalMarkers =
        stationMarkersAfterLimit + _renderedProposalMarkers.length;
    debugPrint(
      'Dashboard marker virtualization: reason=$reason, '
      'selectedState=${widget.selectedState}, '
      'zoom=${zoom.toStringAsFixed(2)}, tier=${tier.name}, '
      'rawStateStations=${widget.stations.length}, '
      'visibleBeforeLimit=$visibleBeforeLimit, '
      'stationMarkersAfterLimit=$stationMarkersAfterLimit, '
      'aggregateMarkers=$aggregateMarkers, '
      'clusterAssignedMarkers=$clusterAssignedMarkers, '
      'proposalMarkers=${_renderedProposalMarkers.length}, '
      'finalMarkers=$totalMarkers, spatialBuckets=$spatialBuckets, '
      'markerPreparationDurationMs=$durationMs, applied=$applied'
      '${skipReason == null ? '' : ', skipped=$skipReason'}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
  }

  Set<Marker> _proposalMarkers() {
    if (identical(_cachedProposalSource, widget.proposals)) {
      return _cachedProposalMarkers;
    }

    final stopwatch = Stopwatch()..start();
    final markers = <Marker>{};
    var invalidCoordinates = 0;
    for (final proposal in widget.proposals) {
      if (proposal.latitude == null || proposal.longitude == null) {
        invalidCoordinates++;
        continue;
      }
      markers.add(
        Marker(
          markerId: MarkerId('proposal_${proposal.id}'),
          position: LatLng(proposal.latitude!, proposal.longitude!),
          icon: _icons!.proposal,
          infoWindow: InfoWindow(
            title: proposal.city,
            snippet: proposal.state == null
                ? 'Proposed station · ${proposal.status}'
                : '${proposal.status} · ${proposal.state}',
          ),
        ),
      );
    }
    stopwatch.stop();
    _cachedProposalSource = widget.proposals;
    _cachedProposalMarkers = Set.unmodifiable(markers);
    debugPrint(
      'Map diagnostics: proposal marker creation='
      '${stopwatch.elapsedMilliseconds}ms, markers=${markers.length}, '
      'invalid=$invalidCoordinates.',
    );
    return _cachedProposalMarkers;
  }

  Set<Polygon> _buildStatePolygons() {
    final regions = widget.stateRegions;
    final isStateDetail = widget.selectedState != malaysiaSelection;
    final polygons = <Polygon>{};
    for (final region in regions) {
      for (var index = 0; index < region.displayPolygons.length; index++) {
        final rings = region.displayPolygons[index];
        if (rings.isEmpty) continue;
        final selected = widget.selectedState == region.name;
        final strokeColor = selected
            ? green
            : isStateDetail
                ? const Color(0xFF8B98A7)
                : blue;
        polygons.add(
          Polygon(
            polygonId: PolygonId('state_${region.name}_$index'),
            consumeTapEvents: widget.onStateSelected != null,
            onTap: widget.onStateSelected == null
                ? null
                : () => widget.onStateSelected!(
                      region.name,
                      'polygon-tap',
                    ),
            points: [
              for (final point in rings.first)
                LatLng(point.latitude, point.longitude),
            ],
            holes: [
              for (final hole in rings.skip(1))
                [
                  for (final point in hole)
                    LatLng(point.latitude, point.longitude),
                ],
            ],
            strokeColor: strokeColor,
            strokeWidth: selected ? 3 : 1,
            fillColor: (selected ? green : strokeColor).withValues(
              alpha: selected
                  ? .12
                  : isStateDetail
                      ? .012
                      : .035,
            ),
          ),
        );
      }
    }
    return Set<Polygon>.unmodifiable(polygons);
  }

  Future<void> _focusSelectedRegion({required String reason}) async {
    final controller = _mapController;
    final bounds = widget.focusBounds;
    if (!mounted || controller == null || bounds == null) return;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(bounds.south, bounds.west),
            northeast: LatLng(bounds.north, bounds.east),
          ),
          34,
        ),
      );
      debugPrint(
        'Map camera fitted: state=${widget.selectedState}, reason=$reason.',
      );
      debugPrint(
        'State selection applied: state=${widget.selectedState}, '
        'cameraFitted=true, stationCount=${widget.stations.length}, '
        'proposalCount=${widget.proposals.length}, '
        'analysisCacheHit=${widget.analysisCacheHit}.',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'Map camera fit failed: state=${widget.selectedState}, error=$error.',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Set<Circle> _buildPriorityCircles() {
    final stopwatch = Stopwatch()..start();
    final circles = <Circle>{};
    var invalidCoordinates = 0;
    for (final area in widget.priorityAreas) {
      if (area.latitude == null || area.longitude == null) {
        invalidCoordinates++;
        continue;
      }
      final color = area.priority == 'High'
          ? Colors.red
          : area.priority == 'Medium'
              ? Colors.orange
              : Colors.green;
      circles.add(
        Circle(
          circleId: CircleId('priority_${area.id}'),
          center: LatLng(area.latitude!, area.longitude!),
          radius: 4000,
          fillColor: color.withValues(alpha: .16),
          strokeColor: color.withValues(alpha: .9),
          strokeWidth: 2,
        ),
      );
    }
    stopwatch.stop();
    debugPrint(
      'Map diagnostics: priority-circle creation='
      '${stopwatch.elapsedMilliseconds}ms, circles=${circles.length}, '
      'invalid=$invalidCoordinates.',
    );
    return Set.unmodifiable(circles);
  }

  void _handleMapCreated(GoogleMapController controller) {
    _mapController = controller;
    if (!_platformViewCreated) {
      _platformViewCreated = true;
      _createdPlatformViewCount++;
    }
    debugPrint(
      'Google Map created successfully: instance=$_instanceId, '
      'mode=$_mapMode, '
      'controller=${identityHashCode(controller)}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount, '
      'rawStations=${widget.stations.length}, '
      'finalMarkers=${widget.gaps ? 0 : _markers.length}, '
      'priorityCircles=${_priorityCircles.length}.',
    );
    if (!widget.gaps && widget.stations.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestVisibleStationRefresh(reason: 'map-created');
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusSelectedRegion(reason: 'map-created');
    });
  }

  void _handleCameraIdle() {
    _requestVisibleStationRefresh(reason: 'camera-idle');
  }

  @override
  Widget build(BuildContext c) {
    _buildCount++;
    final markersPassedToGoogleMap =
        widget.gaps ? const <Marker>{} : _markers;
    final usesStationClustering = !widget.gaps &&
        widget.stations.isNotEmpty &&
        _presentationTier == _StationPresentationTier.individual;
    final clusterManagersPassedToGoogleMap = usesStationClustering
        ? _clusterManagers
        : const <ClusterManager>{};
    final clusterAssignedMarkerCount =
        usesStationClustering ? _visibleStationMarkers.length : 0;
    debugPrint(
      'MapPanel rebuild: instance=$_instanceId, '
      'mode=$_mapMode, '
      'tier=${_presentationTier.name}, '
      'count=$_buildCount, rawStations=${widget.stations.length}, '
      'finalMarkers=${markersPassedToGoogleMap.length}, '
      'clusterAssignedMarkers=$clusterAssignedMarkerCount, '
      'nationalStateBadges=${_nationalStateMarkers.length}, '
      'priorityCircles=${_priorityCircles.length}, '
      'mountedMapPanels=$_mountedPanelCount, '
      'createdGoogleMapViews=$_createdPlatformViewCount.',
    );
    return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: widget.initialTarget,
                  zoom: widget.initialZoom,
                ),
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                  ),
                },
                zoomControlsEnabled: true,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                padding: widget.mapPadding,
                onTap: widget.onTap,
                markers: markersPassedToGoogleMap,
                circles: _priorityCircles,
                polygons: _statePolygons,
                clusterManagers: clusterManagersPassedToGoogleMap,
                onMapCreated: _handleMapCreated,
                onCameraIdle: _handleCameraIdle,
              ),
              if (_preparingMarkers)
                Center(
                  child: Semantics(
                    label: 'Preparing map markers',
                    child: CircularProgressIndicator.adaptive(),
                  ),
                ),
              if (_mapError != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _mapError!,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
  }
}

class _PaddedMapBounds {
  const _PaddedMapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  factory _PaddedMapBounds.fromVisibleRegion(
    LatLngBounds bounds, {
    required double paddingRatio,
  }) {
    final rawSouth = math.min(
      bounds.southwest.latitude,
      bounds.northeast.latitude,
    );
    final rawNorth = math.max(
      bounds.southwest.latitude,
      bounds.northeast.latitude,
    );
    final rawWest = bounds.southwest.longitude;
    final rawEast = bounds.northeast.longitude;
    final rawLongitudeSpan = _longitudeSpan(rawWest, rawEast);
    final latitudePadding = (rawNorth - rawSouth) * paddingRatio;
    final longitudePadding = rawLongitudeSpan * paddingRatio;
    return _PaddedMapBounds(
      south: (rawSouth - latitudePadding).clamp(-85.0, 85.0).toDouble(),
      west: _normalizeLongitude(rawWest - longitudePadding),
      north: (rawNorth + latitudePadding).clamp(-85.0, 85.0).toDouble(),
      east: _normalizeLongitude(rawEast + longitudePadding),
    );
  }

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(double latitude, double longitude) {
    if (latitude < south || latitude > north) return false;
    if (west <= east) return longitude >= west && longitude <= east;
    return longitude >= west || longitude <= east;
  }

  static double _longitudeSpan(double west, double east) =>
      west <= east ? east - west : (180 - west) + (east + 180);

  static double _normalizeLongitude(double longitude) {
    var normalized = longitude;
    while (normalized > 180) normalized -= 360;
    while (normalized < -180) normalized += 360;
    return normalized;
  }
}

class _RenderedStationSelection {
  const _RenderedStationSelection({
    required this.markers,
    required this.visibleBeforeLimit,
    required this.aggregateMarkers,
    required this.clusterAssignedMarkers,
    required this.spatialBuckets,
  });

  final Map<String, Marker> markers;
  final int visibleBeforeLimit;
  final int aggregateMarkers;
  final int clusterAssignedMarkers;
  final int spatialBuckets;
}

class _StableStationSample {
  const _StableStationSample({
    required this.stations,
    required this.spatialBuckets,
  });

  final List<ChargingStation> stations;
  final int spatialBuckets;
}

class _FixedGridCell {
  const _FixedGridCell({
    required this.key,
    required this.centerLatitude,
    required this.centerLongitude,
  });

  final String key;
  final double centerLatitude;
  final double centerLongitude;
}

class _StationAggregateAccumulator {
  _StationAggregateAccumulator({
    required this.key,
  });

  final String key;
  var count = 0;
  var latitudeSum = 0.0;
  var longitudeSum = 0.0;
  final members = <ChargingStation>[];

  void add(ChargingStation station) {
    count++;
    latitudeSum += station.latitude;
    longitudeSum += station.longitude;
    members.add(station);
  }

  _StationAggregate complete() {
    final centreLatitude = latitudeSum / count;
    final centreLongitude = longitudeSum / count;
    members.sort((a, b) {
      final aLatitude = a.latitude - centreLatitude;
      final aLongitude = a.longitude - centreLongitude;
      final bLatitude = b.latitude - centreLatitude;
      final bLongitude = b.longitude - centreLongitude;
      final distanceComparison =
          (aLatitude * aLatitude + aLongitude * aLongitude).compareTo(
        bLatitude * bLatitude + bLongitude * bLongitude,
      );
      return distanceComparison != 0
          ? distanceComparison
          : a.id.compareTo(b.id);
    });
    final representative = members.first;
    return _StationAggregate(
      key: key,
      count: count,
      latitude: representative.latitude,
      longitude: representative.longitude,
    );
  }
}

class _StationAggregate {
  const _StationAggregate({
    required this.key,
    required this.count,
    required this.latitude,
    required this.longitude,
  });

  final String key;
  final int count;
  final double latitude;
  final double longitude;
}

class _StationBucketRepresentative {
  const _StationBucketRepresentative({
    required this.station,
    required this.distanceSquared,
  });

  final ChargingStation station;
  final double distanceSquared;
}

class _MarkerIcons {
  const _MarkerIcons({
    required this.station,
    required this.proposal,
    required this.aggregateBadges,
  });

  static const _aggregateBuckets = <int>[
    1,
    10,
    25,
    50,
    100,
    250,
    500,
    1000,
  ];

  final BitmapDescriptor station;
  final BitmapDescriptor proposal;
  final Map<int, BitmapDescriptor> aggregateBadges;

  static Future<_MarkerIcons>? _cache;
  static final Map<int, Future<BitmapDescriptor>> _stateBadgeCache = {};

  BitmapDescriptor aggregateForCount(int count) {
    var bucket = _aggregateBuckets.first;
    for (final candidate in _aggregateBuckets) {
      if (count < candidate) break;
      bucket = candidate;
    }
    return aggregateBadges[bucket]!;
  }

  Future<BitmapDescriptor> stateBadgeForCount(int count) {
    final cached = _stateBadgeCache[count];
    if (cached != null) return cached;
    debugPrint('State count badge cache miss: count=$count.');
    return _stateBadgeCache[count] = _drawStateCountBadge(count);
  }

  static Future<_MarkerIcons> load() {
    if (_cache != null) {
      debugPrint('Map marker icon cache hit.');
      return _cache!;
    }
    debugPrint('Map marker icon cache miss.');
    return _cache = _load();
  }

  static Future<_MarkerIcons> _load() async {
    final stopwatch = Stopwatch()..start();
    final aggregateBadges = <int, BitmapDescriptor>{};
    for (final bucket in _aggregateBuckets) {
      aggregateBadges[bucket] = await _drawAggregateBadge(bucket);
    }
    final icons = _MarkerIcons(
      station: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(28, 28)),
        'assets/icons/station_lightning.png',
      ),
      proposal: await BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(32, 32)),
        'assets/icons/proposed_station.png',
      ),
      aggregateBadges:
          Map<int, BitmapDescriptor>.unmodifiable(aggregateBadges),
    );
    stopwatch.stop();
    debugPrint(
      'Map marker icon loading and resizing='
      '${stopwatch.elapsedMilliseconds}ms; '
      'cachedAggregateBadgeStyles=${aggregateBadges.length}.',
    );
    return icons;
  }

  static Future<BitmapDescriptor> _drawAggregateBadge(int bucket) async {
    const logicalSize = 46.0;
    const pixelRatio = 2.0;
    const pixelSize = logicalSize * pixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centre = const Offset(pixelSize / 2, pixelSize / 2);
    final radius = pixelSize / 2 - 3;

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = const Color(0xFF00A884),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final label = bucket >= 1000 ? '1K+' : '$bucket+';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: bucket >= 100 ? 21 : 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pixelSize - 12);
    textPainter.paint(
      canvas,
      Offset(
        (pixelSize - textPainter.width) / 2,
        (pixelSize - textPainter.height) / 2,
      ),
    );

    final image = await recorder.endRecording().toImage(
          pixelSize.toInt(),
          pixelSize.toInt(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }
    return BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: logicalSize,
      height: logicalSize,
      imagePixelRatio: pixelRatio,
    );
  }

  static Future<BitmapDescriptor> _drawStateCountBadge(int count) async {
    const logicalSize = 42.0;
    const pixelRatio = 2.0;
    const pixelSize = logicalSize * pixelRatio;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final centre = const Offset(pixelSize / 2, pixelSize / 2);
    final radius = pixelSize / 2 - 3;

    canvas.drawCircle(
      centre,
      radius,
      Paint()..color = const Color(0xFF087F6A),
    );
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );

    final label = '$count';
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white,
          fontSize: label.length >= 5
              ? 15
              : label.length == 4
                  ? 18
                  : label.length == 3
                      ? 21
                      : 24,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pixelSize - 10);
    textPainter.paint(
      canvas,
      Offset(
        (pixelSize - textPainter.width) / 2,
        (pixelSize - textPainter.height) / 2,
      ),
    );

    final image = await recorder.endRecording().toImage(
          pixelSize.toInt(),
          pixelSize.toInt(),
        );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      return BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueGreen,
      );
    }
    return BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: logicalSize,
      height: logicalSize,
      imagePixelRatio: pixelRatio,
    );
  }
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
    return Semantics(
      label: 'Proposal status: $status',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Text(
          status,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.ev_station, color: green, size: 27),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    proposal.city,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: planningTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: StatusChip(proposal.status)),
              ],
            ),
            if (proposal.description.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                proposal.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: planningMutedTextColor,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _CompactInfo(
                  icon: Icons.group_outlined,
                  label: '${proposal.displayedSupports} supports',
                  color: green,
                ),
                _CompactInfo(
                  icon: Icons.category_outlined,
                  label: proposal.area,
                  color: green,
                ),
                _CompactInfo(
                  icon: Icons.electrical_services_outlined,
                  label: proposal.charger,
                  color: blue,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onDetails,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('View details'),
              ),
            ),
          ],
        ),
      );
}

class FloatingBottomNav extends StatelessWidget {
  const FloatingBottomNav({
    super.key,
    this.currentTab = 'Planning',
    this.onProfileTap,
    this.onPlanningTap,
    this.onFeedbackTap,
  });

  final String currentTab;

  /// Home/Charging don't have screens yet, so they stay inert; Planning,
  /// Feedback and Profile become tappable once a caller opts in.
  final VoidCallback? onProfileTap;
  final VoidCallback? onPlanningTap;
  final VoidCallback? onFeedbackTap;

  @override
  Widget build(BuildContext c) => SafeArea(
      child: Container(
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE9EDF3)),
            boxShadow: const [
              BoxShadow(color: Color(0x10000000), blurRadius: 8)
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _Nav(
                  Icons.home_outlined,
                  'Home',
                  selected: currentTab == 'Home',
                ),
              ),
              Expanded(
                child: _Nav(
                  Icons.bolt_outlined,
                  'Charging',
                  selected: currentTab == 'Charging',
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onPlanningTap,
                  child: _Nav(
                    Icons.map_outlined,
                    'Planning',
                    selected: currentTab == 'Planning',
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onFeedbackTap,
                  child: _Nav(
                    Icons.warning_amber_outlined,
                    'Feedback',
                    selected: currentTab == 'Feedback',
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: onProfileTap,
                  child: _Nav(
                    Icons.person_outline,
                    'Profile',
                    selected: currentTab == 'Profile',
                  ),
                ),
              ),
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
  Widget build(BuildContext c) => Semantics(
        selected: selected,
        label: label,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? green : Colors.blueGrey,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: selected ? green : Colors.blueGrey,
              ),
            ),
          ],
        ),
      );
}

class _CompactInfo extends StatelessWidget {
  const _CompactInfo({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
}
