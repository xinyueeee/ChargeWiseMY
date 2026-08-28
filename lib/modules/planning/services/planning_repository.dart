import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../services/supabase_service.dart';
import '../models/proposal.dart';
import 'analysis_profile.dart';
import 'coverage_gap_analyzer.dart';
import 'infrastructure_cache_service.dart';
import 'mevnet_api_service.dart';
import 'proposal_location_service.dart';
import 'proposal_photo_service.dart';
import 'state_boundary_service.dart';

class PlanningRepository {
  PlanningRepository({
    SupabaseService? supabaseService,
    ProposalPhotoService? photoService,
    InfrastructureCacheStore? infrastructureCache,
    MEVnetApiService? mevnetApiService,
    bool? useMevnetApiSource,
  })  : _supabase = supabaseService ?? SupabaseService(),
        _photoService = photoService ?? ProposalPhotoService(),
        _infrastructureCache =
            infrastructureCache ?? SqliteInfrastructureCacheService(),
        _mevnetApi = mevnetApiService ?? MEVnetApiService(),
        _useMevnetApi = useMevnetApiSource ?? useMevnetApi {
    _infrastructureSync = InfrastructureSyncCoordinator(
      cache: _infrastructureCache,
      remoteLoader: _loadRemoteStations,
    );
    debugPrint(
      'Infrastructure remote source selected: '
      '${_useMevnetApi ? 'MEVnet ArcGIS REST API' : 'Supabase charging_stations'}.',
    );
  }
  final SupabaseService _supabase;
  final ProposalPhotoService _photoService;
  final InfrastructureCacheStore _infrastructureCache;
  final MEVnetApiService _mevnetApi;
  final bool _useMevnetApi;
  late final InfrastructureSyncCoordinator _infrastructureSync;
  final CoverageGapAnalyzer _gapAnalyzer = const CoverageGapAnalyzer();
  final ProposalLocationService _proposalLocations = ProposalLocationService();
  final Map<String, Future<List<GapArea>>> _gapCache = {};
  List<ChargingStation>? _fingerprintSource;
  List<ChargingStation> _fingerprintSortedStations = const [];
  String _cachedStationFingerprint = '';
  int _analyzerExecutionCount = 0;

  String get stationFingerprint => _cachedStationFingerprint;
  String? get authenticatedUserId => _supabase.authenticatedUserId;
  Stream<String?> get authenticatedUserChanges =>
      _supabase.authenticatedUserChanges;

  Stream<InfrastructureLoadUpdate> synchronizeInfrastructure() =>
      _infrastructureSync.synchronize();

  Future<void> clearInfrastructureCache() =>
      _infrastructureCache.clearInfrastructureCache();

  String prepareStationFingerprint(List<ChargingStation> stations) {
    _prepareStationFingerprint(stations);
    return _cachedStationFingerprint;
  }

  void invalidateStationDataCaches() {
    final previousAnalysisCount = _gapCache.length;
    _gapCache.clear();
    _fingerprintSource = null;
    _fingerprintSortedStations = const [];
    _cachedStationFingerprint = '';
    debugPrint(
      'Station-data repository caches invalidated: '
      'analysisEntries=$previousAnalysisCount, fingerprintCleared=true.',
    );
  }

  Future<List<Proposal>> getProposals(List<ChargingStation> stations,
      {String? authenticatedUserId}) async {
    final rows = await _supabase.getProposalsWithReactions();
    final proposals = rows.map((row) {
      final reactions = List<Map<String, dynamic>>.from(
          row['proposal_reactions'] as List? ?? []);
      final likes = reactions
          .where((item) =>
              ProposalReaction.fromDatabase(item['reaction']) ==
              ProposalReaction.support)
          .length;
      final dislikes = reactions
          .where((item) =>
              ProposalReaction.fromDatabase(item['reaction']) ==
              ProposalReaction.oppose)
          .length;
      final myReactions = authenticatedUserId == null
          ? const <Map<String, dynamic>>[]
          : reactions
              .where((item) => item['user_id'] == authenticatedUserId)
              .toList();
      final mine = myReactions.isEmpty ? null : myReactions.first;
      final reaction =
          mine == null ? null : ProposalReaction.fromDatabase(mine['reaction']);
      return Proposal.fromSupabase(
        row,
        nearestStationKm: _nearestStationKm(row, stations),
        supportCount: likes,
        opposeCount: dislikes,
        currentUserReaction: reaction,
      );
    }).toList();
    await _proposalLocations.load();
    return Future.wait(proposals.map(_proposalLocations.enrich));
  }

  Future<List<GapArea>> getGaps(
    List<ChargingStation> stations, {
    String selectedState = malaysiaSelection,
    Map<String, int> stationCountsByState = const {},
  }) {
    final cacheStopwatch = Stopwatch()..start();
    _prepareStationFingerprint(stations);
    final profile = AnalysisProfileConfig.resolve(
      selectedState,
      stationCountsByState,
    );
    final cacheKey = '$selectedState|${profile.cacheToken}|'
        '${CoverageGapAnalyzer.stationSiteDeduplicationCacheToken}|'
        '$_cachedStationFingerprint';
    final cached = _gapCache[cacheKey];
    cacheStopwatch.stop();
    if (cached != null) {
      debugPrint(
        'Coverage-gap cache hit: state=$selectedState, '
        'stationCount=${_fingerprintSortedStations.length}, '
        'profile=${profile.definition.id}, '
        'siteDedup='
        '${CoverageGapAnalyzer.stationSiteDeduplicationCacheToken}, '
        'lookup=${cacheStopwatch.elapsedMicroseconds}us, '
        'analyzerExecutionCount=$_analyzerExecutionCount.',
      );
      return cached;
    }

    _analyzerExecutionCount++;
    debugPrint(
      'Coverage-gap cache miss: state=$selectedState, '
      'stationCount=${_fingerprintSortedStations.length}, '
      'profile=${profile.definition.id}, '
      'siteDedup=${CoverageGapAnalyzer.stationSiteDeduplicationCacheToken}, '
      'lookup=${cacheStopwatch.elapsedMicroseconds}us, '
      'analyzerExecutionCount=$_analyzerExecutionCount.',
    );
    final analysis = _gapAnalyzer
        .analyze(
          _fingerprintSortedStations,
          selectedState: selectedState,
          stationCountsByState: stationCountsByState,
        )
        .then((areas) => List<GapArea>.unmodifiable(areas));
    _gapCache[cacheKey] = analysis;
    return analysis;
  }

  void invalidateGapAnalysis(
    List<ChargingStation> stations, {
    required String selectedState,
    Map<String, int> stationCountsByState = const {},
  }) {
    _prepareStationFingerprint(stations);
    final profile = AnalysisProfileConfig.resolve(
      selectedState,
      stationCountsByState,
    );
    final cacheKey = '$selectedState|${profile.cacheToken}|'
        '${CoverageGapAnalyzer.stationSiteDeduplicationCacheToken}|'
        '$_cachedStationFingerprint';
    _gapCache.remove(cacheKey);
    debugPrint('Coverage-gap cache invalidated: state=$selectedState.');
  }

  void _prepareStationFingerprint(List<ChargingStation> stations) {
    if (identical(_fingerprintSource, stations)) return;
    final stopwatch = Stopwatch()..start();
    final sortedStations = List<ChargingStation>.of(stations)
      ..sort(_compareStations);
    _fingerprintSource = stations;
    _fingerprintSortedStations = List<ChargingStation>.unmodifiable(
      sortedStations,
    );
    _cachedStationFingerprint = _stationFingerprint(sortedStations);
    stopwatch.stop();
    debugPrint(
      'Station fingerprint refreshed: count=${stations.length}, '
      'stationFingerprint=$_cachedStationFingerprint, '
      'duration=${stopwatch.elapsedMilliseconds}ms.',
    );
  }

  int _compareStations(ChargingStation a, ChargingStation b) {
    final idComparison = a.id.compareTo(b.id);
    if (idComparison != 0) return idComparison;
    final latitudeComparison = a.latitude.compareTo(b.latitude);
    if (latitudeComparison != 0) return latitudeComparison;
    return a.longitude.compareTo(b.longitude);
  }

  String _stationFingerprint(List<ChargingStation> stations) {
    var hash = 0x811C9DC5;
    for (final station in stations) {
      final value = '${station.id}|${station.latitude.toStringAsFixed(7)}|'
          '${station.longitude.toStringAsFixed(7)};';
      for (final codeUnit in value.codeUnits) {
        hash ^= codeUnit;
        hash = (hash * 0x01000193) & 0xFFFFFFFF;
      }
    }
    return '${stations.length}-${hash.toRadixString(16).padLeft(8, '0')}';
  }

  /// Single remote seam used by [InfrastructureSyncCoordinator].
  ///
  /// The source is chosen once at construction from [useMevnetApi]. There is
  /// deliberately no silent runtime fallback from the API to Supabase: when a
  /// refresh fails the coordinator keeps serving the SQLite snapshot, which is
  /// the only offline path the application relies on.
  Future<List<ChargingStation>> _loadRemoteStations(String status) =>
      _useMevnetApi
          ? _getStationsFromMevnetApi(status: status)
          : _getStationsFromSupabase(status: status);

  Future<List<ChargingStation>> _getStationsFromMevnetApi({
    required String status,
  }) async {
    final stopwatch = Stopwatch()..start();
    final stations = await _mevnetApi.getStations(status: status);
    stopwatch.stop();
    debugPrint(
      'Station loading diagnostics: source=mevnetApi, status=$status, '
      'validStations=${stations.length}, '
      'duration=${stopwatch.elapsedMilliseconds}ms, '
      'paginationComplete=true.',
    );
    return stations;
  }

  Future<List<ChargingStation>> _getStationsFromSupabase({
    required String status,
  }) async {
    final fetchStopwatch = Stopwatch()..start();
    final rows = await _supabase.getChargingStations(status: status);
    fetchStopwatch.stop();
    final parsingStopwatch = Stopwatch()..start();
    final stations = <ChargingStation>[];
    var invalidCoordinates = 0;
    for (final row in rows) {
      final station = ChargingStation.fromSupabase(row);
      if (station == null) {
        invalidCoordinates++;
      } else {
        stations.add(station);
      }
    }
    parsingStopwatch.stop();
    debugPrint(
      'Station loading diagnostics: '
      'status=$status, '
      'stationRowsFetched=${rows.length}, '
      'validCoordinateRows=${stations.length}, '
      'invalidCoordinateRows=$invalidCoordinates, '
      'fetch=${fetchStopwatch.elapsedMilliseconds}ms, '
      'parsing=${parsingStopwatch.elapsedMilliseconds}ms, '
      'paginationComplete=true.',
    );
    return stations;
  }

  Future<int> getStationCount() async {
    return _supabase.getChargingStationCount();
  }

  Future<String> submitProposal(Proposal proposal) async {
    final actingUserId = await _supabase.ensureActingUser();
    final payload = <String, Object?>{
      'user_id': actingUserId,
      'title': proposal.city,
      'description': proposal.description,
      'address': proposal.locationLabel,
      'latitude': proposal.latitude,
      'longitude': proposal.longitude,
      'charger_type': proposal.charger,
      'expected_demand': proposal.demand == 'High'
          ? 3
          : proposal.demand == 'Low'
              ? 1
              : 2,
      'status': Proposal.statusPending,
    };
    try {
      final inserted = await _supabase.client
          .from('proposals')
          .insert(payload)
          .select('proposal_id')
          .single();
      final proposalId = inserted['proposal_id'];
      if (proposalId is! String || proposalId.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            'Proposal insert returned without a valid proposal_id.',
          );
        }
        throw const FormatException(
          'Proposal insert returned an invalid identifier.',
        );
      }
      return proposalId;
    } on PostgrestException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Proposal insert PostgREST failure: code=${error.code}, '
          'message=${error.message}, details=${error.details}, '
          'hint=${error.hint}.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Future<void> updateProposal(Proposal proposal) async {
    _assertOwnerMutationAllowed(proposal, action: 'edit');
    await _supabase.updateProposal(proposal.id, {
      'title': proposal.city,
      'description': proposal.description,
      'address': proposal.locationLabel,
      'latitude': proposal.latitude,
      'longitude': proposal.longitude,
      'charger_type': proposal.charger,
      'expected_demand': proposal.demand == 'High'
          ? 3
          : proposal.demand == 'Low'
              ? 1
              : 2,
    });
  }

  Future<String> uploadProposalPhoto({
    required String proposalId,
    required ProposalPhotoUpload upload,
    String? previousPath,
  }) =>
      _photoService.uploadAndAttach(
        proposalId: proposalId,
        upload: upload,
        previousPath: previousPath,
      );

  Future<void> removeProposalPhoto({
    required String proposalId,
    required String path,
  }) =>
      _photoService.removeAndDetach(proposalId: proposalId, path: path);

  Future<void> deleteProposal(Proposal proposal) async {
    _assertOwnerMutationAllowed(proposal, action: 'delete');
    await _supabase.deleteProposal(proposal.id);
    final path = proposal.sitePhotoPath;
    if (path != null) {
      await _photoService.cleanupAfterProposalDeletion(
        proposalId: proposal.id,
        path: path,
      );
    }
  }

  Future<void> setProposalReaction(
    Proposal proposal,
    ProposalReaction? reaction,
  ) async {
    try {
      await _supabase.setProposalReaction(
        proposalId: proposal.id,
        reaction: reaction?.databaseValue,
      );
    } on PostgrestException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Proposal reaction PostgREST failure: code=${error.code}, '
          'message=${error.message}, details=${error.details}, '
          'hint=${error.hint}.',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) {
    if (!Proposal.validStatuses.contains(status)) {
      throw ArgumentError.value(
          status, 'status', 'Unsupported proposal status');
    }
    return _supabase.updateProposalStatus(id, status);
  }

  bool ownsProposal(Proposal proposal) =>
      proposal.ownerUserId != null &&
      proposal.ownerUserId == _supabase.authenticatedUserId;

  void _assertOwnerMutationAllowed(
    Proposal proposal, {
    required String action,
  }) {
    if (!ownsProposal(proposal)) {
      throw StateError('Only the proposal owner may $action this proposal.');
    }
    final allowed =
        action == 'edit' ? proposal.canOwnerEdit : proposal.canOwnerDelete;
    if (!allowed) {
      throw StateError(
        '${proposal.status} proposals are read-only and cannot be '
        '${action == 'edit' ? 'edited' : 'deleted'}.',
      );
    }
  }

  double _nearestStationKm(
    Map<String, dynamic> proposal,
    List<ChargingStation> stations,
  ) {
    if (stations.isEmpty) return 0;
    final lat = (proposal['latitude'] as num?)?.toDouble();
    final lng = (proposal['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return 0;
    return stations.map((station) {
      final dx = (lat - station.latitude) * 111;
      final dy = (lng - station.longitude) * 111;
      return math.sqrt(dx * dx + dy * dy);
    }).reduce((a, b) => a < b ? a : b);
  }
}
