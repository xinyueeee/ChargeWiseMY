import 'dart:math' as math;

import 'state_boundary_service.dart';

enum AnalysisProfile { denseUrban, urban, regional }

class AnalysisProfileDefinition {
  const AnalysisProfileDefinition({
    required this.profile,
    required this.displayName,
    required this.description,
    required this.gridSpacingDegrees,
    required this.nearbyRadiusKm,
    required this.minimumNearestStationKm,
    required this.candidateSeparationKm,
    required this.retainedCandidateLimit,
    required this.preferredRoadDistanceMeters,
    required this.maximumRoadDistanceMeters,
    required this.maximumSettlementDistanceKm,
    required this.maximumResultsPerSettlement,
  });

  final AnalysisProfile profile;
  final String displayName;
  final String description;
  final double gridSpacingDegrees;
  final double nearbyRadiusKm;
  final double minimumNearestStationKm;
  final double candidateSeparationKm;
  final int retainedCandidateLimit;
  final double preferredRoadDistanceMeters;
  final double maximumRoadDistanceMeters;
  final double maximumSettlementDistanceKm;
  final int maximumResultsPerSettlement;

  String get id => profile.name;
}

class ResolvedAnalysisProfile {
  const ResolvedAnalysisProfile({
    required this.definition,
    required this.stateStationCount,
    required this.profileAverageStationCount,
    required this.refinementFactor,
    required this.gridSpacingDegrees,
    required this.nearbyRadiusKm,
    required this.minimumNearestStationKm,
    required this.candidateSeparationKm,
    required this.retainedCandidateLimit,
    required this.preferredRoadDistanceMeters,
    required this.maximumRoadDistanceMeters,
    required this.maximumSettlementDistanceKm,
    required this.maximumResultsPerSettlement,
  });

  final AnalysisProfileDefinition definition;
  final int stateStationCount;
  final double profileAverageStationCount;
  final double refinementFactor;
  final double gridSpacingDegrees;
  final double nearbyRadiusKm;
  final double minimumNearestStationKm;
  final double candidateSeparationKm;
  final int retainedCandidateLimit;
  final double preferredRoadDistanceMeters;
  final double maximumRoadDistanceMeters;
  final double maximumSettlementDistanceKm;
  final int maximumResultsPerSettlement;

  double get gridSpacingKm => gridSpacingDegrees * 111;

  String get cacheToken =>
      '${definition.id}|profile-${AnalysisProfileConfig.profileVersion}|'
      'refinement-${AnalysisProfileConfig.refinementVersion}|'
      'dense-strategy-${AnalysisProfileConfig.denseUrbanStrategyVersion}|'
      'land-$malaysiaStateBoundaryDatasetVersion|'
      'roads-${AnalysisProfileConfig.roadDatasetVersion}|'
      'road-filter-${AnalysisProfileConfig.roadFilterVersion}|'
      'road-threshold-${AnalysisProfileConfig.roadThresholdVersion}|'
      'settlements-${AnalysisProfileConfig.settlementDatasetVersion}|'
      'settlement-filter-${AnalysisProfileConfig.settlementFilterVersion}|'
      'settlement-threshold-'
      '${AnalysisProfileConfig.settlementThresholdVersion}';

  Map<String, Object> toPayload() => <String, Object>{
        'profileId': definition.id,
        'profileDisplayName': definition.displayName,
        'stateStationCount': stateStationCount,
        'profileAverageStationCount': profileAverageStationCount,
        'refinementFactor': refinementFactor,
        'gridSpacingDegrees': gridSpacingDegrees,
        'nearbyRadiusKm': nearbyRadiusKm,
        'minimumNearestStationKm': minimumNearestStationKm,
        'candidateSeparationKm': candidateSeparationKm,
        'retainedCandidateLimit': retainedCandidateLimit,
        'preferredRoadDistanceMeters': preferredRoadDistanceMeters,
        'maximumRoadDistanceMeters': maximumRoadDistanceMeters,
        'maximumSettlementDistanceKm': maximumSettlementDistanceKm,
        'maximumResultsPerSettlement': maximumResultsPerSettlement,
      };
}

class AnalysisProfileConfig {
  const AnalysisProfileConfig._();

  static const int profileVersion = 1;
  static const int refinementVersion = 1;
  static const int denseUrbanStrategyVersion = 2;
  static const String roadDatasetVersion = 'unavailable-v1';
  static const int roadFilterVersion = 1;
  static const int roadThresholdVersion = 1;
  static const String settlementDatasetVersion =
      'dosm-geonames-district-centres-my-v2';
  static const int settlementFilterVersion = 1;
  static const int settlementThresholdVersion = 1;
  static const double minimumRefinementFactor = .82;
  static const double maximumRefinementFactor = 1.18;

  static const Map<AnalysisProfile, AnalysisProfileDefinition> definitions = {
    AnalysisProfile.denseUrban: AnalysisProfileDefinition(
      profile: AnalysisProfile.denseUrban,
      displayName: 'Dense Urban Analysis',
      description:
          'Neighbourhood-level charging infrastructure coverage assessment',
      gridSpacingDegrees: .018,
      nearbyRadiusKm: 3,
      minimumNearestStationKm: 2.5,
      candidateSeparationKm: 3,
      retainedCandidateLimit: 16,
      preferredRoadDistanceMeters: 300,
      maximumRoadDistanceMeters: 500,
      maximumSettlementDistanceKm: 20,
      maximumResultsPerSettlement: 16,
    ),
    AnalysisProfile.urban: AnalysisProfileDefinition(
      profile: AnalysisProfile.urban,
      displayName: 'Urban Analysis',
      description:
          'City and suburban charging infrastructure coverage assessment',
      gridSpacingDegrees: .075,
      nearbyRadiusKm: 12,
      minimumNearestStationKm: 8,
      candidateSeparationKm: 15,
      retainedCandidateLimit: 22,
      preferredRoadDistanceMeters: 500,
      maximumRoadDistanceMeters: 1000,
      maximumSettlementDistanceKm: 20,
      maximumResultsPerSettlement: 4,
    ),
    AnalysisProfile.regional: AnalysisProfileDefinition(
      profile: AnalysisProfile.regional,
      displayName: 'Regional Analysis',
      description: 'Regional charging infrastructure coverage assessment',
      gridSpacingDegrees: .18,
      nearbyRadiusKm: 25,
      minimumNearestStationKm: 15,
      candidateSeparationKm: 35,
      retainedCandidateLimit: 20,
      preferredRoadDistanceMeters: 1000,
      maximumRoadDistanceMeters: 3000,
      maximumSettlementDistanceKm: 40,
      maximumResultsPerSettlement: 3,
    ),
  };

  static const Map<String, AnalysisProfile> stateProfiles = {
    'Kuala Lumpur': AnalysisProfile.denseUrban,
    'Putrajaya': AnalysisProfile.denseUrban,
    'Selangor': AnalysisProfile.urban,
    'Johor': AnalysisProfile.urban,
    'Penang': AnalysisProfile.urban,
    'Melaka': AnalysisProfile.urban,
    'Negeri Sembilan': AnalysisProfile.urban,
    'Sabah': AnalysisProfile.regional,
    'Sarawak': AnalysisProfile.regional,
    'Kedah': AnalysisProfile.regional,
    'Perak': AnalysisProfile.regional,
    'Pahang': AnalysisProfile.regional,
    'Terengganu': AnalysisProfile.regional,
    'Kelantan': AnalysisProfile.regional,
    'Perlis': AnalysisProfile.regional,
    'Labuan': AnalysisProfile.regional,
  };

  static AnalysisProfileDefinition definitionFor(String state) {
    final profile = stateProfiles[state] ?? AnalysisProfile.regional;
    return definitions[profile]!;
  }

  static ResolvedAnalysisProfile resolve(
    String state,
    Map<String, int> stationCountsByState,
  ) {
    final definition = definitionFor(state);
    if (state == malaysiaSelection) {
      final total = stationCountsByState.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );
      return _resolved(
        definition,
        stateStationCount: total,
        profileAverageStationCount: total.toDouble(),
        refinementFactor: 1,
      );
    }

    final peerStates = stateProfiles.entries
        .where((entry) => entry.value == definition.profile)
        .map((entry) => entry.key)
        .toList(growable: false);
    final peerCounts = [
      for (final peerState in peerStates)
        stationCountsByState[peerState] ?? 0,
    ];
    final average = peerCounts.isEmpty
        ? 0.0
        : peerCounts.fold<int>(0, (sum, count) => sum + count) /
            peerCounts.length;
    final selectedCount = stationCountsByState[state] ?? 0;
    final unboundedFactor = math.sqrt((average + 1) / (selectedCount + 1));
    final factor = unboundedFactor
        .clamp(minimumRefinementFactor, maximumRefinementFactor)
        .toDouble();
    return _resolved(
      definition,
      stateStationCount: selectedCount,
      profileAverageStationCount: average,
      refinementFactor: factor,
    );
  }

  static ResolvedAnalysisProfile _resolved(
    AnalysisProfileDefinition definition, {
    required int stateStationCount,
    required double profileAverageStationCount,
    required double refinementFactor,
  }) {
    return ResolvedAnalysisProfile(
      definition: definition,
      stateStationCount: stateStationCount,
      profileAverageStationCount: profileAverageStationCount,
      refinementFactor: refinementFactor,
      gridSpacingDegrees:
          definition.gridSpacingDegrees * refinementFactor,
      nearbyRadiusKm: definition.nearbyRadiusKm,
      minimumNearestStationKm: definition.minimumNearestStationKm,
      candidateSeparationKm:
          definition.candidateSeparationKm * refinementFactor,
      retainedCandidateLimit: definition.retainedCandidateLimit,
      preferredRoadDistanceMeters: definition.preferredRoadDistanceMeters,
      maximumRoadDistanceMeters: definition.maximumRoadDistanceMeters,
      maximumSettlementDistanceKm:
          definition.maximumSettlementDistanceKm,
      maximumResultsPerSettlement:
          definition.maximumResultsPerSettlement,
    );
  }
}
