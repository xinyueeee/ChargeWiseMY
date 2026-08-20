import 'package:flutter/foundation.dart';

import '../models/proposal.dart';
import '../services/analysis_profile.dart';
import '../services/planning_repository.dart';
import '../services/state_boundary_service.dart';

class PlanningViewModel extends ChangeNotifier {
  PlanningViewModel(this._repository) {
    debugPrint(
      'PlanningViewModel created: instance=${identityHashCode(this)}.',
    );
  }

  final PlanningRepository _repository;
  final StateBoundaryService _stateBoundaries = StateBoundaryService();

  List<Proposal> proposals = [];
  List<ChargingStation> stations = [];
  List<ChargingStation> _selectedStations = const [];
  List<Proposal> _selectedProposals = const [];
  List<GapArea> _priorityAreas = const [];
  List<StateRegion> _regions = const [];
  Map<String, String?> _stationStateById = const {};
  Map<String, String?> _proposalStateById = const {};
  Map<String, int> _stationCountByState = const {};
  Map<String, int> _proposalCountByState = const {};
  List<StateOverviewSummary> _stateOverviewSummaries = const [];
  final Map<String, List<GapArea>> _analysisByState = {};

  int stationCount = 0;
  bool loading = true;
  bool analyzingGaps = false;
  String? errorMessage;
  String? analysisErrorMessage;
  String? analysisStatusMessage;
  bool? lastAnalysisCacheHit;
  String _selectedState = malaysiaSelection;
  int _loadGeneration = 0;
  int _analysisGeneration = 0;
  int _notifyListenersCount = 0;

  String get selectedState => _selectedState;
  List<String> get stateOptions => _stateBoundaries.stateOptions;
  List<StateRegion> get stateRegions => _regions;
  List<StateOverviewSummary> get stateOverviewSummaries =>
      _stateOverviewSummaries;
  StateRegion? get selectedRegion =>
      _stateBoundaries.regionFor(_selectedState);
  GeoBounds? get selectedMapBounds =>
      selectedRegion?.bounds ?? _stateBoundaries.malaysiaBounds;
  AnalysisProfileDefinition get selectedAnalysisProfile =>
      AnalysisProfileConfig.definitionFor(_selectedState);

  String? stateForStation(String stationId) => _stationStateById[stationId];

  List<ChargingStation> get selectedStations => _selectedStations;
  List<Proposal> get selectedProposals => _selectedProposals;
  List<ChargingStation> get mapStations =>
      _selectedState == malaysiaSelection ? const [] : _selectedStations;
  List<Proposal> get mapProposals =>
      _selectedState == malaysiaSelection ? const [] : _selectedProposals;
  List<GapArea> get mapPriorityAreas =>
      _selectedState == malaysiaSelection ? const [] : _priorityAreas;

  int get selectedStationCount => _selectedStations.length;
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
    final moreThanTenKm =
        highAreas.where((area) => area.distance > 10).length;
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
    _notifyListenersCount++;
    debugPrint(
      'PlanningViewModel notifyListeners: '
      'instance=${identityHashCode(this)}, '
      'count=$_notifyListenersCount, selectedState=$_selectedState.',
    );
    super.notifyListeners();
  }

  Future<void> load() async {
    final initializationStopwatch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    _analysisGeneration++;
    loading = true;
    analyzingGaps = false;
    errorMessage = null;
    analysisErrorMessage = null;
    analysisStatusMessage = 'Loading infrastructure planning data…';
    lastAnalysisCacheHit = null;
    notifyListeners();
    try {
      final stationResults = await Future.wait([
        _repository.getStationCount(),
        _repository.getStations(),
        _stateBoundaries.load(),
      ]);
      if (generation != _loadGeneration) return;

      stationCount = stationResults[0] as int;
      final loadedStations = stationResults[1] as List<ChargingStation>;
      _regions = stationResults[2] as List<StateRegion>;
      final stationDataChanged = !_sameStationData(stations, loadedStations);
      var analysisCacheInvalidated = false;
      if (stationDataChanged) {
        _repository.invalidateStationDataCaches();
        stations = loadedStations;
        _analysisByState.clear();
        _priorityAreas = const [];
        analysisCacheInvalidated = true;
        debugPrint(
          'PlanningViewModel cleared state-analysis cache because the '
          'complete station dataset changed.',
        );
      }
      final rebuildStateCache =
          stationDataChanged || _stateOverviewSummaries.isEmpty;
      if (rebuildStateCache) {
        _cacheStationStates();
      }
      final stationFingerprint =
          _repository.prepareStationFingerprint(stations);
      debugPrint(
        'Station refresh audit: stationRowsFetched=${stations.length}, '
        'stationFingerprint=$stationFingerprint, '
        'stateCacheRebuilt=$rebuildStateCache, '
        'analysisCacheInvalidated=$analysisCacheInvalidated, '
        'markerCacheInvalidated=$stationDataChanged.',
      );
      _applySelectedStateFilters();

      final loadedProposals = await _repository.getProposals(stations);
      if (generation != _loadGeneration) return;
      if (!_sameProposalData(proposals, loadedProposals) ||
          _proposalCountByState.isEmpty) {
        proposals = loadedProposals;
        _cacheProposalStates();
      }
      _applySelectedStateFilters();

      analyzingGaps = true;
      analysisStatusMessage =
          'Analyzing $_selectedState infrastructure coverage…';
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
      analysisErrorMessage =
          'Unable to analyze $requestedState. Retry.';
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

  String _analysisReadyMessage(String state, List<GapArea> areas) =>
      areas.isEmpty
          ? 'No qualifying infrastructure gaps were detected in $state.'
          : '$state analysis ready';

  void _cacheStationStates() {
    final assignments = <String, String?>{};
    final counts = <String, int>{
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
      }
    }
    _stationStateById = Map<String, String?>.unmodifiable(assignments);
    _stationCountByState = Map<String, int>.unmodifiable(counts);
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

  void _rebuildStateOverviewSummaries() {
    _stateOverviewSummaries = List<StateOverviewSummary>.unmodifiable([
      for (final region in _regions)
        StateOverviewSummary(
          name: region.name,
          labelPoint: region.labelPoint,
          existingStationCount: _stationCountByState[region.name] ?? 0,
          proposedStationCount: _proposalCountByState[region.name] ?? 0,
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
      _selectedProposals = proposals;
      return;
    }
    _selectedStations = List<ChargingStation>.unmodifiable(
      stations.where(
        (station) => _stationStateById[station.id] == _selectedState,
      ),
    );
    _selectedProposals = List<Proposal>.unmodifiable(
      proposals.where(
        (proposal) => _proposalStateById[proposal.id] == _selectedState,
      ),
    );
  }

  void _logSelectedStateConsistency({required String source}) {
    final high =
        _priorityAreas.where((area) => area.priority == 'High').length;
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

  Future<void> react(Proposal proposal, bool like) async {
    if (proposal.reaction == 0) {
      await _repository.reactToProposal(proposal, like);
      proposal.reaction = like ? 1 : -1;
      notifyListeners();
    }
  }

  bool ownsProposal(Proposal proposal) => _repository.ownsProposal(proposal);

  String recommendation(Proposal proposal) =>
      proposal.demand == 'High' &&
              proposal.distance > 5 &&
              proposal.displayedSupports > 30
          ? 'Suitable Location'
          : 'Needs Further Review';

  Future<void> setStatus(Proposal proposal, String status) async {
    await _repository.updateStatus(proposal.id, status);
    proposal.status = status;
    notifyListeners();
  }

  Future<void> submitProposal(Proposal proposal) async {
    await _repository.submitProposal(proposal);
    await _refreshProposals();
  }

  Future<void> updateProposal(Proposal proposal) async {
    await _repository.updateProposal(proposal);
    await _refreshProposals();
  }

  Future<void> deleteProposal(String proposalId) async {
    await _repository.deleteProposal(proposalId);
    await _refreshProposals();
  }

  Future<void> _refreshProposals() async {
    final loadedProposals = await _repository.getProposals(stations);
    if (!_sameProposalData(proposals, loadedProposals)) {
      proposals = loadedProposals;
      _cacheProposalStates();
    }
    _applySelectedStateFilters();
    notifyListeners();
  }

  bool _sameStationData(
    List<ChargingStation> current,
    List<ChargingStation> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (a.id != b.id ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude ||
          a.name != b.name ||
          a.chargerType != b.chargerType) {
        return false;
      }
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
          a.supports != b.supports ||
          a.reaction != b.reaction ||
          a.reactionIncludedInSupports != b.reactionIncludedInSupports ||
          a.locationLabel != b.locationLabel ||
          a.state != b.state ||
          a.nearestTown != b.nearestTown ||
          a.createdAt != b.createdAt ||
           a.createdBy != b.createdBy ||
          a.ownerUserId != b.ownerUserId ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude) {
        return false;
      }
    }
    return true;
  }
}
