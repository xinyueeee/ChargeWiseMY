import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/proposal.dart';
import '../services/analysis_profile.dart';
import '../services/infrastructure_cache_service.dart';
import '../services/planning_repository.dart';
import '../services/proposal_photo_service.dart';
import '../services/state_boundary_service.dart';

class PlanningViewModel extends ChangeNotifier {
  PlanningViewModel(this._repository) {
    _authSubscription = _repository.authenticatedUserChanges.listen(
      _handleAuthenticatedUserChanged,
    );
    debugPrint(
      'PlanningViewModel created: instance=${identityHashCode(this)}.',
    );
  }

  final PlanningRepository _repository;
  final StateBoundaryService _stateBoundaries = StateBoundaryService();

  List<Proposal> proposals = [];
  List<ChargingStation> allMevnetLocations = [];
  // Existing-only by design. Coverage analysis and teammate consumers that
  // depend on `stations` must never receive Newly Proposed locations.
  List<ChargingStation> stations = [];
  List<PlannedChargingLocation> plannedLocations = [];
  List<ChargingStation> _selectedStations = const [];
  List<PlannedChargingLocation> _selectedPlannedLocations = const [];
  List<ChargingStation> _selectedPlannedMapLocations = const [];
  List<Proposal> _selectedProposals = const [];
  List<Proposal> _selectedMapProposals = const [];
  List<GapArea> _priorityAreas = const [];
  List<StateRegion> _regions = const [];
  Map<String, String?> _stationStateById = const {};
  Map<String, String?> _proposalStateById = const {};
  Map<String, String?> _plannedStateById = const {};
  Map<String, int> _stationCountByState = const {};
  Map<String, int> _installedChargerCountByState = const {};
  Map<String, int> _acChargerCountByState = const {};
  Map<String, int> _dcChargerCountByState = const {};
  Map<String, int> _proposalCountByState = const {};
  Map<String, int> _plannedLocationCountByState = const {};
  Map<String, int> _plannedChargerCountByState = const {};
  List<StateOverviewSummary> _stateOverviewSummaries = const [];
  final Map<String, List<GapArea>> _analysisByState = {};
  final Map<String, PlannedInfrastructureContext> _plannedContextCache = {};

  int stationCount = 0;
  bool loading = true;
  bool homeInfrastructureReady = false;
  bool analyzingGaps = false;
  bool infrastructureRefreshing = false;
  bool usingCachedInfrastructure = false;
  DateTime? infrastructureCachedAt;
  String? infrastructureWarningMessage;
  String? errorMessage;
  String? analysisErrorMessage;
  String? analysisStatusMessage;
  bool? lastAnalysisCacheHit;
  String _selectedState = malaysiaSelection;
  int _loadGeneration = 0;
  int _analysisGeneration = 0;
  int _proposalFetchGeneration = 0;
  int _notifyListenersCount = 0;
  String? _proposalContextUserId;
  StreamSubscription<String?>? _authSubscription;
  bool _disposed = false;
  bool _loadInProgress = false;

  String get selectedState => _selectedState;
  List<String> get stateOptions => _stateBoundaries.stateOptions;
  List<StateRegion> get stateRegions => _regions;
  List<StateOverviewSummary> get stateOverviewSummaries =>
      _stateOverviewSummaries;
  StateRegion? get selectedRegion => _stateBoundaries.regionFor(_selectedState);
  GeoBounds? get selectedMapBounds =>
      selectedRegion?.bounds ?? _stateBoundaries.malaysiaBounds;
  AnalysisProfileDefinition get selectedAnalysisProfile =>
      AnalysisProfileConfig.definitionFor(_selectedState);

  String? stateForStation(String stationId) => _stationStateById[stationId];

  List<ChargingStation> get selectedStations => _selectedStations;
  List<PlannedChargingLocation> get selectedPlannedLocations =>
      _selectedPlannedLocations;
  List<Proposal> get selectedProposals => _selectedProposals;
  List<Proposal> get myProposals => List<Proposal>.unmodifiable(
        proposals.where(_repository.ownsProposal),
      );
  List<Proposal> get communityProposals => List<Proposal>.unmodifiable(
        proposals.where((proposal) => !_repository.ownsProposal(proposal)),
      );
  Proposal? proposalById(String id) {
    for (final proposal in proposals) {
      if (proposal.id == id) return proposal;
    }
    return null;
  }

  // Existing-only source. MapPanel decides whether national consumers render
  // these locations or replace them with Planning summary badges.
  List<ChargingStation> get mapStations => _selectedStations;
  List<Proposal> get mapProposals =>
      _selectedState == malaysiaSelection ? const [] : _selectedMapProposals;
  List<ChargingStation> get mapPlannedLocations =>
      _selectedState == malaysiaSelection
          ? const []
          : _selectedPlannedMapLocations;
  List<GapArea> get mapPriorityAreas =>
      _selectedState == malaysiaSelection ? const [] : _priorityAreas;

  int get selectedStationCount => _selectedStations.length;
  int get selectedInstalledChargerCount => _selectedStations.fold(
        0,
        (sum, station) => sum + (station.chargerCount ?? 0),
      );
  int get selectedAcChargerCount => _selectedStations.fold(
        0,
        (sum, station) => sum + (station.acChargerCount ?? 0),
      );
  int get selectedDcChargerCount => _selectedStations.fold(
        0,
        (sum, station) => sum + (station.dcChargerCount ?? 0),
      );
  int get selectedPlannedLocationCount => _selectedPlannedLocations.length;
  int get selectedPlannedChargerCount => _selectedPlannedLocations.fold(
        0,
        (sum, location) => sum + location.proposedChargerCount,
      );

  PlannedInfrastructureContext plannedContextAt(
    double latitude,
    double longitude, {
    double radiusKm = 25,
  }) {
    final cacheKey = '${latitude.toStringAsFixed(6)}|'
        '${longitude.toStringAsFixed(6)}|${radiusKm.toStringAsFixed(3)}';
    final cached = _plannedContextCache[cacheKey];
    if (cached != null) return cached;
    PlannedChargingLocation? nearest;
    var nearestKm = double.infinity;
    var nearbyCount = 0;
    var nearbyChargers = 0;
    for (final location in plannedLocations) {
      final distance = _distanceKm(
        latitude,
        longitude,
        location.latitude,
        location.longitude,
      );
      if (distance < nearestKm) {
        nearestKm = distance;
        nearest = location;
      }
      if (distance <= radiusKm) {
        nearbyCount++;
        nearbyChargers += location.proposedChargerCount;
      }
    }
    final result = PlannedInfrastructureContext(
      nearestDistanceKm: nearest == null ? null : nearestKm,
      nearbyLocationCount: nearbyCount,
      nearbyProposedChargerCount: nearbyChargers,
      radiusKm: radiusKm,
      nearestLocation: nearest,
    );
    _plannedContextCache[cacheKey] = result;
    return result;
  }

  int get proposalCount => _selectedProposals.length;
  int get communitySupportCount => _selectedProposals.fold(
        0,
        (sum, proposal) => sum + proposal.displayedSupports,
      );
  List<GapArea> get priorityAreas => _priorityAreas;
  int get highPriorityAreaCount =>
      _priorityAreas.where((area) => area.priority == 'High').length;
  int get mediumPriorityAreaCount =>
      _priorityAreas.where((area) => area.priority == 'Medium').length;
  int get lowPriorityAreaCount =>
      _priorityAreas.where((area) => area.priority == 'Low').length;
  double get averageGapDistance => _priorityAreas.isEmpty
      ? 0
      : _priorityAreas.fold<double>(0, (sum, area) => sum + area.distance) /
          _priorityAreas.length;
  double get averageCoverageScore => _priorityAreas.isEmpty
      ? 0
      : _priorityAreas.fold<double>(
            0,
            (sum, area) => sum + area.coverageScore,
          ) /
          _priorityAreas.length;
  double get averageLocalStationLocationCount => _priorityAreas.isEmpty
      ? 0
      : _priorityAreas.fold<double>(
            0,
            (sum, area) => sum + area.localStationLocationCount,
          ) /
          _priorityAreas.length;
  bool get hasAnalysisForSelectedState =>
      _analysisByState.containsKey(_selectedState);
  bool get analysisReady =>
      !loading &&
      !analyzingGaps &&
      analysisErrorMessage == null &&
      hasAnalysisForSelectedState;

  String get analysisInsight {
    if (_priorityAreas.isEmpty) {
      return 'No grid cells in $_selectedState met the current '
          'charging-infrastructure gap criteria.';
    }
    final highAreas =
        _priorityAreas.where((area) => area.priority == 'High').toList();
    final moreThanTenKm = highAreas.where((area) => area.distance > 10).length;
    if (highAreas.isNotEmpty && moreThanTenKm * 2 >= highAreas.length) {
      return '$moreThanTenKm of ${highAreas.length} high-priority areas '
          'are more than 10 km from an existing charging station.';
    }
    final furthest = _priorityAreas.reduce(
      (a, b) => a.distance >= b.distance ? a : b,
    );
    return 'The largest detected coverage distance is '
        '${furthest.distance.toStringAsFixed(1)} km at ${furthest.name}.';
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    _notifyListenersCount++;
    debugPrint(
      'PlanningViewModel notifyListeners: '
      'instance=${identityHashCode(this)}, '
      'count=$_notifyListenersCount, selectedState=$_selectedState.',
    );
    super.notifyListeners();
  }

  Future<void> load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    final initializationStopwatch = Stopwatch()..start();
    final homeReadyStopwatch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    _analysisGeneration++;
    loading = stations.isEmpty;
    homeInfrastructureReady = stations.isNotEmpty;
    infrastructureRefreshing = true;
    infrastructureWarningMessage = null;
    analyzingGaps = false;
    errorMessage = null;
    analysisErrorMessage = null;
    analysisStatusMessage = 'Loading infrastructure planning data…';
    lastAnalysisCacheHit = null;
    notifyListeners();
    try {
      final boundariesFuture = _stateBoundaries.load();
      var homeReadyLogged = homeInfrastructureReady;
      var initialCachedAnalysisStarted = false;
      await for (final update in _repository.synchronizeInfrastructure()) {
        if (generation != _loadGeneration) return;
        if (_regions.isEmpty) _regions = await boundariesFuture;
        if (generation != _loadGeneration) return;

        final snapshot = update.snapshot;
        final dataChanged =
            snapshot == null ? false : _applyInfrastructureSnapshot(snapshot);
        switch (update.phase) {
          case InfrastructureLoadPhase.cacheReady:
            usingCachedInfrastructure = true;
            infrastructureCachedAt = snapshot?.cachedAt;
            break;
          case InfrastructureLoadPhase.remoteExistingReady:
            break;
          case InfrastructureLoadPhase.remoteFresh:
            usingCachedInfrastructure = false;
            infrastructureCachedAt = snapshot?.cachedAt;
            infrastructureRefreshing = false;
            infrastructureWarningMessage = null;
            break;
          case InfrastructureLoadPhase.remoteFailed:
            infrastructureRefreshing = false;
            if (update.hasUsableInfrastructure) {
              infrastructureWarningMessage = usingCachedInfrastructure
                  ? 'Showing saved infrastructure data. Some information may '
                      'not be up to date.'
                  : 'Fresh infrastructure data could not be fully loaded. '
                      'Previously available data remains visible.';
            } else {
              throw update.error ??
                  StateError('No charging infrastructure is available.');
            }
            break;
        }

        if (stations.isNotEmpty) {
          homeInfrastructureReady = true;
          loading = false;
          if (!homeReadyLogged) {
            homeReadyLogged = true;
            homeReadyStopwatch.stop();
            debugPrint(
              'Home infrastructure ready: existing=${stations.length}, '
              'source=${usingCachedInfrastructure ? 'sqlite-cache' : 'supabase'}, '
              'duration=${homeReadyStopwatch.elapsedMilliseconds}ms, '
              'planningInitializationContinues=true.',
            );
          }
        }
        if (dataChanged ||
            update.phase == InfrastructureLoadPhase.cacheReady ||
            update.phase == InfrastructureLoadPhase.remoteFresh ||
            update.phase == InfrastructureLoadPhase.remoteFailed) {
          notifyListeners();
        }
        if (!initialCachedAnalysisStarted &&
            homeInfrastructureReady &&
            _priorityAreas.isEmpty) {
          initialCachedAnalysisStarted = true;
          // Coverage analysis is local and Existing-only, so cached physical
          // locations are safe to analyze while Supabase revalidates them.
          unawaited(runSelectedStateAnalysis());
        }
      }
      if (generation != _loadGeneration) return;
      if (stations.isEmpty) {
        throw StateError('No valid Existing charging locations were loaded.');
      }

      final proposalUserId = _repository.authenticatedUserId;
      final proposalFetchGeneration = ++_proposalFetchGeneration;
      try {
        final loadedProposals = await _repository.getProposals(
          stations,
          authenticatedUserId: proposalUserId,
        );
        if (generation != _loadGeneration) return;
        if (proposalFetchGeneration == _proposalFetchGeneration) {
          _proposalContextUserId = proposalUserId;
          if (!_sameProposalData(proposals, loadedProposals) ||
              _proposalCountByState.isEmpty) {
            proposals = loadedProposals;
            _cacheProposalStates();
          }
          _applySelectedStateFilters();
        }
      } catch (error, stackTrace) {
        if (generation != _loadGeneration) return;
        infrastructureWarningMessage ??=
            'Infrastructure is available, but proposal activity could not be '
            'refreshed.';
        debugPrint(
            'Proposal refresh failed without hiding infrastructure: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      final currentUserId = _repository.authenticatedUserId;
      if (currentUserId != _proposalContextUserId) {
        unawaited(_refreshProposalsAfterAuthChange(currentUserId));
      }

      analyzingGaps = true;
      analysisStatusMessage =
          'Analyzing $_selectedState infrastructure coverage…';
      try {
        final areas = await _repository.getGaps(
          stations,
          selectedState: _selectedState,
          stationCountsByState: _stationCountByState,
        );
        if (generation != _loadGeneration) return;
        _analysisByState[_selectedState] = areas;
        _priorityAreas = areas;
        analysisStatusMessage = _analysisReadyMessage(_selectedState, areas);
        lastAnalysisCacheHit = false;
        _rebuildStateOverviewSummaries();
        debugPrint(
          'PlanningViewModel state analysis stored: '
          'instance=${identityHashCode(this)}, state=$_selectedState, '
          'stationCount=${stations.length}, resultCount=${areas.length}.',
        );
      } catch (error, stackTrace) {
        if (generation != _loadGeneration) return;
        analysisErrorMessage =
            'Infrastructure is available, but coverage analysis could not be '
            'completed. Retry.';
        analysisStatusMessage = analysisErrorMessage;
        debugPrint('Initial coverage analysis failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    } catch (error, stackTrace) {
      if (generation != _loadGeneration) return;
      errorMessage =
          'Unable to load planning data. Check your connection and try again.';
      analysisStatusMessage = errorMessage;
      debugPrint(
        'PlanningViewModel load failed: instance=${identityHashCode(this)}, '
        'generation=$generation, error=$error.',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
    if (generation != _loadGeneration) return;
    _loadInProgress = false;
    infrastructureRefreshing = false;
    analyzingGaps = false;
    loading = false;
    notifyListeners();
    initializationStopwatch.stop();
    debugPrint(
      'PlanningViewModel initialization complete: '
      'duration=${initializationStopwatch.elapsedMilliseconds}ms, '
      'stations=${stations.length}, proposals=${proposals.length}, '
      'selectedState=$_selectedState, priorityAreas=${_priorityAreas.length}.',
    );
  }

  bool _applyInfrastructureSnapshot(InfrastructureCacheSnapshot snapshot) {
    final loadedStations = List<ChargingStation>.unmodifiable(
      snapshot.existingStations,
    );
    final loadedPlannedRows = List<ChargingStation>.unmodifiable(
      snapshot.proposedStations,
    );
    final loadedPlanned = List<PlannedChargingLocation>.unmodifiable(
      loadedPlannedRows.map(PlannedChargingLocation.fromStation),
    );
    stationCount = loadedStations.length;
    final stationDataChanged = !_sameStationData(stations, loadedStations);
    final stationSpatialDataChanged =
        !_sameStationSpatialData(stations, loadedStations);
    final plannedDataChanged =
        !_samePlannedData(plannedLocations, loadedPlanned);
    var analysisCacheInvalidated = false;
    if (stationSpatialDataChanged) {
      _analysisGeneration++;
      _repository.invalidateStationDataCaches();
      _analysisByState.clear();
      _priorityAreas = const [];
      analysisCacheInvalidated = true;
      debugPrint(
        'PlanningViewModel cleared state-analysis cache because the '
        'complete Existing location dataset changed.',
      );
    }
    if (stationDataChanged) stations = loadedStations;
    if (plannedDataChanged || _plannedStateById.isEmpty) {
      plannedLocations = loadedPlanned;
      _plannedContextCache.clear();
    }
    allMevnetLocations = snapshot.stations;

    final rebuildStationStateCache =
        stationDataChanged || _stateOverviewSummaries.isEmpty;
    if (rebuildStationStateCache) _cacheStationStates();
    if (plannedDataChanged || _plannedStateById.isEmpty) {
      _cachePlannedStates();
    }
    _applySelectedStateFilters();
    final stationFingerprint = _repository.prepareStationFingerprint(stations);
    debugPrint(
      'Infrastructure snapshot applied: total=${snapshot.stations.length}, '
      'existing=${loadedStations.length}, planned=${loadedPlanned.length}, '
      'stationFingerprint=$stationFingerprint, '
      'stateCacheRebuilt=$rebuildStationStateCache, '
      'analysisCacheInvalidated=$analysisCacheInvalidated, '
      'markerCacheInvalidated=$stationDataChanged.',
    );
    return stationDataChanged || plannedDataChanged;
  }

  Future<void> selectState(
    String state, {
    String source = 'unknown',
  }) async {
    if (!stateOptions.contains(state) || state == _selectedState) return;
    final previousState = _selectedState;
    debugPrint(
      'State selection requested: from=$previousState, to=$state, '
      'source=$source.',
    );
    final filteringStopwatch = Stopwatch()..start();
    _analysisGeneration++;
    _selectedState = state;
    _applySelectedStateFilters();
    final cacheLookupStopwatch = Stopwatch()..start();
    final cached = _analysisByState[state];
    cacheLookupStopwatch.stop();
    final cacheHit = cached != null;
    _priorityAreas = cached ?? const [];
    analyzingGaps = !cacheHit;
    analysisErrorMessage = null;
    lastAnalysisCacheHit = cacheHit;
    analysisStatusMessage = cached != null
        ? _analysisReadyMessage(state, cached)
        : 'Analyzing $state infrastructure coverage…';
    filteringStopwatch.stop();
    notifyListeners();
    debugPrint(
      'State filtering diagnostics: state=$state, '
      'stations=${_selectedStations.length}, '
      'proposals=${_selectedProposals.length}, '
      'filtering=${filteringStopwatch.elapsedMicroseconds}us, '
      'cacheLookup=${cacheLookupStopwatch.elapsedMicroseconds}us, '
      'analysisCacheHit=$cacheHit.',
    );
    if (cacheHit) {
      _logSelectedStateConsistency(source: 'state-cache-hit');
      debugPrint(
        'State selection applied: state=$state, cameraFitted=pending, '
        'stationCount=${_selectedStations.length}, '
        'proposalCount=${_selectedProposals.length}, '
        'analysisCacheHit=true.',
      );
      return;
    }
    await runSelectedStateAnalysis(loadingAlreadyVisible: true);
  }

  Future<void> runSelectedStateAnalysis({
    bool loadingAlreadyVisible = false,
    bool force = false,
  }) async {
    if (loading) return;
    final requestedState = _selectedState;
    if (force) {
      _repository.invalidateGapAnalysis(
        stations,
        selectedState: requestedState,
        stationCountsByState: _stationCountByState,
      );
      _analysisByState.remove(requestedState);
      _priorityAreas = const [];
      _rebuildStateOverviewSummaries();
      _logSelectedStateConsistency(source: 'analysis-cache-invalidated');
    }
    final cacheLookupStopwatch = Stopwatch()..start();
    final cached = _analysisByState[requestedState];
    cacheLookupStopwatch.stop();
    if (cached != null) {
      _priorityAreas = cached;
      analyzingGaps = false;
      analysisErrorMessage = null;
      analysisStatusMessage = _analysisReadyMessage(requestedState, cached);
      lastAnalysisCacheHit = true;
      notifyListeners();
      _logSelectedStateConsistency(source: 'analysis-cache-hit');
      debugPrint(
        'PlanningViewModel state analysis cache hit: '
        'state=$requestedState, resultCount=${cached.length}, '
        'lookup=${cacheLookupStopwatch.elapsedMicroseconds}us.',
      );
      return;
    }

    final generation = ++_analysisGeneration;
    analyzingGaps = true;
    analysisErrorMessage = null;
    analysisStatusMessage =
        'Analyzing $requestedState infrastructure coverage…';
    lastAnalysisCacheHit = false;
    if (!loadingAlreadyVisible) notifyListeners();
    final analysisStopwatch = Stopwatch()..start();
    try {
      final areas = await _repository.getGaps(
        stations,
        selectedState: requestedState,
        stationCountsByState: _stationCountByState,
      );
      if (generation != _analysisGeneration ||
          requestedState != _selectedState) {
        debugPrint(
          'PlanningViewModel ignored stale state analysis: '
          'requestedState=$requestedState, selectedState=$_selectedState.',
        );
        return;
      }
      _analysisByState[requestedState] = areas;
      _priorityAreas = areas;
      analysisStatusMessage = _analysisReadyMessage(requestedState, areas);
      _rebuildStateOverviewSummaries();
      analysisStopwatch.stop();
      debugPrint(
        'State analysis diagnostics: state=$requestedState, '
        'resultCount=${areas.length}, '
        'duration=${analysisStopwatch.elapsedMilliseconds}ms.',
      );
      debugPrint(
        'State selection applied: state=$requestedState, '
        'cameraFitted=pending, stationCount=${_selectedStations.length}, '
        'proposalCount=${_selectedProposals.length}, '
        'analysisCacheHit=false.',
      );
    } catch (error, stackTrace) {
      if (generation != _analysisGeneration ||
          requestedState != _selectedState) {
        return;
      }
      analysisErrorMessage = 'Unable to analyze $requestedState. Retry.';
      analysisStatusMessage = analysisErrorMessage;
      analysisStopwatch.stop();
      debugPrint(
        'PlanningViewModel state analysis failed: '
        'state=$requestedState, error=$error.',
      );
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (generation == _analysisGeneration &&
          requestedState == _selectedState) {
        analyzingGaps = false;
        _logSelectedStateConsistency(source: 'analysis-complete');
        notifyListeners();
      }
    }
  }

  Future<void> retrySelectedStateAnalysis() =>
      runSelectedStateAnalysis(force: true);

  /// Debug/support hook only. Infrastructure is public shared data, so logout
  /// does not clear this cache automatically.
  Future<void> clearInfrastructureCache() =>
      _repository.clearInfrastructureCache();

  String _analysisReadyMessage(String state, List<GapArea> areas) =>
      areas.isEmpty
          ? 'No qualifying infrastructure gaps were detected in $state.'
          : '$state analysis ready';

  void _cacheStationStates() {
    final assignments = <String, String?>{};
    final counts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    final installedChargerCounts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    final acChargerCounts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    final dcChargerCounts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    var unassigned = 0;
    final unassignedStations = <ChargingStation>[];
    for (final station in stations) {
      final state = _stateBoundaries.stateFor(
        station.latitude,
        station.longitude,
      );
      assignments[station.id] = state;
      if (state == null) {
        unassigned++;
        unassignedStations.add(station);
      } else {
        counts[state] = (counts[state] ?? 0) + 1;
        installedChargerCounts[state] =
            (installedChargerCounts[state] ?? 0) + (station.chargerCount ?? 0);
        acChargerCounts[state] =
            (acChargerCounts[state] ?? 0) + (station.acChargerCount ?? 0);
        dcChargerCounts[state] =
            (dcChargerCounts[state] ?? 0) + (station.dcChargerCount ?? 0);
      }
    }
    _stationStateById = Map<String, String?>.unmodifiable(assignments);
    _stationCountByState = Map<String, int>.unmodifiable(counts);
    _installedChargerCountByState =
        Map<String, int>.unmodifiable(installedChargerCounts);
    _acChargerCountByState = Map<String, int>.unmodifiable(acChargerCounts);
    _dcChargerCountByState = Map<String, int>.unmodifiable(dcChargerCounts);
    _rebuildStateOverviewSummaries();
    final sortedCounts = Map<String, int>.fromEntries(
      counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    debugPrint(
      'Station state assignment cached: '
      'boundaryDataset=$malaysiaStateBoundaryDatasetVersion, '
      'total=${stations.length}, '
      'assignedToState=${stations.length - unassigned}, '
      'unassignedToState=$unassigned, '
      'stateCountAudit=$sortedCounts.',
    );
    for (final station in unassignedStations.take(30)) {
      final boundaryProximity = _stateBoundaries.nearestStateBoundary(
        station.latitude,
        station.longitude,
      );
      debugPrint(
        'Unassigned station audit: stationId=${station.id}, '
        'latitude=${station.latitude.toStringAsFixed(6)}, '
        'longitude=${station.longitude.toStringAsFixed(6)}, '
        'currentAssignedState=none, '
        'nearbyState=${boundaryProximity?.state ?? 'undetermined'}, '
        'nearStateBoundary=${boundaryProximity?.nearBoundary ?? false}, '
        'boundaryDistanceKm=${boundaryProximity?.distanceKm.toStringAsFixed(2) ?? 'unknown'}, '
        'coordinateValid=true, '
        'possibleCause=outside-current-GeoJSON-polygons-or-offshore.',
      );
    }
  }

  void _cacheProposalStates() {
    final assignments = <String, String?>{};
    final counts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    var unassigned = 0;
    for (final proposal in proposals) {
      final latitude = proposal.latitude;
      final longitude = proposal.longitude;
      final state = latitude == null || longitude == null
          ? null
          : _stateBoundaries.stateFor(latitude, longitude);
      assignments[proposal.id] = state;
      if (state == null) {
        unassigned++;
      } else {
        counts[state] = (counts[state] ?? 0) + 1;
      }
    }
    _proposalStateById = Map<String, String?>.unmodifiable(assignments);
    _proposalCountByState = Map<String, int>.unmodifiable(counts);
    _rebuildStateOverviewSummaries();
    debugPrint(
      'Proposal state assignment cached: total=${proposals.length}, '
      'assigned=${proposals.length - unassigned}, unassigned=$unassigned.',
    );
  }

  void _cachePlannedStates() {
    final assignments = <String, String?>{};
    final locationCounts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    final chargerCounts = <String, int>{
      for (final region in _regions) region.name: 0,
    };
    var unassigned = 0;
    var sourceStateDifferences = 0;
    for (final location in plannedLocations) {
      final state = _stateBoundaries.stateFor(
        location.latitude,
        location.longitude,
      );
      assignments[location.id] = state;
      if (state == null) {
        unassigned++;
      } else {
        locationCounts[state] = (locationCounts[state] ?? 0) + 1;
        chargerCounts[state] =
            (chargerCounts[state] ?? 0) + location.proposedChargerCount;
        if (location.state != null && location.state != state) {
          sourceStateDifferences++;
        }
      }
    }
    _plannedStateById = Map.unmodifiable(assignments);
    _plannedLocationCountByState = Map.unmodifiable(locationCounts);
    _plannedChargerCountByState = Map.unmodifiable(chargerCounts);
    _rebuildStateOverviewSummaries();
    debugPrint('MEVnet proposed state reconciliation: '
        'total=${plannedLocations.length}, assigned='
        '${plannedLocations.length - unassigned}, unassigned=$unassigned, '
        'sourceVsGeoJsonDifferences=$sourceStateDifferences.');
  }

  void _rebuildStateOverviewSummaries() {
    _stateOverviewSummaries = List<StateOverviewSummary>.unmodifiable([
      for (final region in _regions)
        StateOverviewSummary(
          name: region.name,
          labelPoint: region.labelPoint,
          existingStationCount: _stationCountByState[region.name] ?? 0,
          installedChargerCount:
              _installedChargerCountByState[region.name] ?? 0,
          acChargerCount: _acChargerCountByState[region.name] ?? 0,
          dcChargerCount: _dcChargerCountByState[region.name] ?? 0,
          proposedStationCount: _proposalCountByState[region.name] ?? 0,
          mevnetProposedLocationCount:
              _plannedLocationCountByState[region.name] ?? 0,
          mevnetProposedChargerCount:
              _plannedChargerCountByState[region.name] ?? 0,
          priorityAreaCount: _analysisByState[region.name]?.length,
        ),
    ]);
    debugPrint(
      'State overview cache rebuilt: states=${_stateOverviewSummaries.length}, '
      'assignedStations=${_stationCountByState.values.fold<int>(0, (a, b) => a + b)}, '
      'assignedProposals=${_proposalCountByState.values.fold<int>(0, (a, b) => a + b)}.',
    );
  }

  void _applySelectedStateFilters() {
    if (_selectedState == malaysiaSelection) {
      _selectedStations = stations;
      _selectedPlannedLocations = plannedLocations;
      _selectedPlannedMapLocations = List.unmodifiable(
        plannedLocations.map((item) => item.mapLocation),
      );
      _selectedProposals = proposals;
      _selectedMapProposals = const [];
      return;
    }
    _selectedStations = List<ChargingStation>.unmodifiable(
      stations.where(
        (station) => _stationStateById[station.id] == _selectedState,
      ),
    );
    _selectedPlannedLocations = List<PlannedChargingLocation>.unmodifiable(
      plannedLocations.where(
        (location) => _plannedStateById[location.id] == _selectedState,
      ),
    );
    _selectedPlannedMapLocations = List.unmodifiable(
      _selectedPlannedLocations.map((item) => item.mapLocation),
    );
    _selectedProposals = List<Proposal>.unmodifiable(
      proposals.where(
        (proposal) => _proposalStateById[proposal.id] == _selectedState,
      ),
    );
    _selectedMapProposals = List<Proposal>.unmodifiable(
      _selectedProposals.where((proposal) => !proposal.isRejected),
    );
  }

  void _logSelectedStateConsistency({required String source}) {
    final high = _priorityAreas.where((area) => area.priority == 'High').length;
    final medium =
        _priorityAreas.where((area) => area.priority == 'Medium').length;
    final low = _priorityAreas.where((area) => area.priority == 'Low').length;
    debugPrint(
      'Selected-state consistency audit: source=$source, '
      'state=$_selectedState, stationCount=${_selectedStations.length}, '
      'cachedStationCount=${_selectedState == malaysiaSelection ? stations.length : _stationCountByState[_selectedState] ?? 0}, '
      'proposalCount=${_selectedProposals.length}, '
      'gapCount=${_priorityAreas.length}, high=$high, medium=$medium, low=$low, '
      'analyzing=$analyzingGaps.',
    );
  }

  Future<void> setReaction(
    Proposal proposal,
    ProposalReaction? reaction,
  ) async {
    await _repository.setProposalReaction(proposal, reaction);
    _replaceProposalLocally(proposal.withReaction(reaction));
    await _refreshAfterPersistedMutation('reaction update');
  }

  bool ownsProposal(Proposal proposal) => _repository.ownsProposal(proposal);
  bool canOwnerEdit(Proposal proposal) =>
      ownsProposal(proposal) && proposal.canOwnerEdit;
  bool canOwnerDelete(Proposal proposal) =>
      ownsProposal(proposal) && proposal.canOwnerDelete;

  Future<void> setStatus(Proposal proposal, String status) async {
    await _repository.updateStatus(proposal.id, status);
    proposal.status = status;
    notifyListeners();
    await _refreshAfterPersistedMutation('status update');
  }

  Future<String> submitProposal(Proposal proposal) async {
    final proposalId = await _repository.submitProposal(proposal);
    await _refreshAfterPersistedMutation(
      'creation (proposalId=$proposalId)',
    );
    return proposalId;
  }

  Future<void> updateProposal(Proposal proposal) async {
    await _repository.updateProposal(proposal);
    _replaceProposalLocally(proposal);
    await _refreshAfterPersistedMutation('edit');
  }

  Future<void> uploadProposalPhoto({
    required String proposalId,
    required ProposalPhotoUpload upload,
    String? previousPath,
  }) async {
    final path = await _repository.uploadProposalPhoto(
      proposalId: proposalId,
      upload: upload,
      previousPath: previousPath,
    );
    final proposal = proposalById(proposalId);
    if (proposal != null) {
      _replaceProposalLocally(proposal.withSitePhotoPath(path));
    }
    await _refreshAfterPersistedMutation('photo upload');
  }

  Future<void> removeProposalPhoto({
    required String proposalId,
    required String path,
  }) async {
    await _repository.removeProposalPhoto(
      proposalId: proposalId,
      path: path,
    );
    final proposal = proposalById(proposalId);
    if (proposal != null) {
      _replaceProposalLocally(proposal.withSitePhotoPath(null));
    }
    await _refreshAfterPersistedMutation('photo removal');
  }

  Future<void> deleteProposal(Proposal proposal) async {
    await _repository.deleteProposal(proposal);
    proposals = List<Proposal>.unmodifiable(
      proposals.where((item) => item.id != proposal.id),
    );
    _cacheProposalStates();
    _applySelectedStateFilters();
    notifyListeners();
    await _refreshAfterPersistedMutation('deletion');
  }

  void _replaceProposalLocally(Proposal proposal) {
    final index = proposals.indexWhere((item) => item.id == proposal.id);
    if (index < 0) return;
    final updated = List<Proposal>.of(proposals)..[index] = proposal;
    proposals = List<Proposal>.unmodifiable(updated);
    _cacheProposalStates();
    _applySelectedStateFilters();
    notifyListeners();
  }

  Future<void> _refreshAfterPersistedMutation(String operation) async {
    try {
      await _refreshProposals();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Proposal $operation persisted, but the follow-up refresh failed: '
          'error=$error. Local state remains updated and the shared '
          'collection will reconcile on the next refresh.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  Future<void> _refreshProposals() async {
    await _refreshProposalsForUser(_repository.authenticatedUserId);
  }

  void _handleAuthenticatedUserChanged(String? userId) {
    if (_disposed || stations.isEmpty || userId == _proposalContextUserId) {
      return;
    }
    unawaited(_refreshProposalsAfterAuthChange(userId));
  }

  Future<void> _refreshProposalsAfterAuthChange(String? userId) async {
    try {
      await _refreshProposalsForUser(userId);
    } catch (_) {
      // The detailed, sanitized failure is logged by the shared refresh path.
      // Infrastructure remains usable and the next authenticated refresh can
      // reconcile the user's reaction selection.
    }
  }

  Future<void> _refreshProposalsForUser(String? userId) async {
    final generation = ++_proposalFetchGeneration;
    try {
      final loadedProposals = await _repository.getProposals(
        stations,
        authenticatedUserId: userId,
      );
      if (_disposed ||
          generation != _proposalFetchGeneration ||
          userId != _repository.authenticatedUserId) {
        return;
      }
      _proposalContextUserId = userId;
      if (_sameProposalData(proposals, loadedProposals)) return;
      proposals = loadedProposals;
      _cacheProposalStates();
      _applySelectedStateFilters();
      notifyListeners();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Proposal refresh failed for the current authenticated context: '
          'error=$error.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  bool _sameStationData(
    List<ChargingStation> current,
    List<ChargingStation> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (!a.hasSameRuntimeDataAs(b)) return false;
    }
    return true;
  }

  bool _sameStationSpatialData(
    List<ChargingStation> current,
    List<ChargingStation> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (!a.hasSameSpatialIdentityAs(b)) return false;
    }
    return true;
  }

  bool _sameProposalData(
    List<Proposal> current,
    List<Proposal> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (a.id != b.id ||
          a.city != b.city ||
          a.description != b.description ||
          a.status != b.status ||
          a.area != b.area ||
          a.charger != b.charger ||
          a.demand != b.demand ||
          a.distance != b.distance ||
          a.supports != b.supports ||
          a.opposes != b.opposes ||
          a.currentUserReaction != b.currentUserReaction ||
          a.locationLabel != b.locationLabel ||
          a.state != b.state ||
          a.nearestTown != b.nearestTown ||
          a.createdAt != b.createdAt ||
          a.createdBy != b.createdBy ||
          a.ownerUserId != b.ownerUserId ||
          a.sitePhotoPath != b.sitePhotoPath ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude) {
        return false;
      }
    }
    return true;
  }

  bool _samePlannedData(
    List<PlannedChargingLocation> current,
    List<PlannedChargingLocation> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (!a.hasSameRuntimeDataAs(b)) return false;
    }
    return true;
  }

  static double _distanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    _analysisGeneration++;
    _proposalFetchGeneration++;
    _authSubscription?.cancel();
    super.dispose();
  }
}
