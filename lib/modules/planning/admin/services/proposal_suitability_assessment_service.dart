import 'dart:math' as math;

import '../../models/proposal.dart';
import '../models/proposal_assessment.dart';

class ProposalSuitabilityAssessmentService {
  const ProposalSuitabilityAssessmentService();

  static const double nearbyInfrastructureRadiusKm = 10;
  static const double gapRelationshipRadiusKm = 5;
  static const double duplicateConcernRadiusKm = 5;
  static const double strongDuplicateConcernRadiusKm = 2;
  static const double stationSiteGroupingRadiusKm = .075;

  ProposalAssessment assess({
    required Proposal proposal,
    required List<ChargingStation> stations,
    required List<Proposal> proposals,
    required List<GapArea> gaps,
    required bool gapAnalysisAvailable,
  }) {
    final factors = <ProposalAssessmentFactor>[];
    final hasCoordinates = proposal.latitude != null &&
        proposal.longitude != null &&
        stations.isNotEmpty;
    final nearbyStationLocations = hasCoordinates
        ? _nearbyDistinctStationLocations(proposal, stations)
        : null;

    factors.add(
      _infrastructureFactor(
        proposal,
        nearbyStationLocations,
        available: hasCoordinates,
      ),
    );

    final gapMatch = gapAnalysisAvailable && hasCoordinates
        ? _nearestGap(proposal, gaps)
        : null;
    final relatedGapMatch = gapMatch != null &&
            gapMatch.distanceKm <= gapRelationshipRadiusKm
        ? gapMatch
        : null;
    factors.add(
      _gapFactor(
        gapMatch,
        available: gapAnalysisAvailable && hasCoordinates,
      ),
    );
    factors.add(_expectedUsageFactor(proposal.demand));
    factors.add(_communitySupportFactor(proposal.displayedSupports));
    factors.add(_settlementFactor(proposal));

    final duplicate = hasCoordinates
        ? _nearestRelevantProposal(proposal, proposals)
        : null;
    factors.add(_duplicationFactor(duplicate, available: hasCoordinates));

    final availableMaximum = factors
        .where((factor) => factor.available)
        .fold<int>(0, (total, factor) => total + factor.maximumScore);
    final awarded = factors
        .where((factor) => factor.available)
        .fold<int>(0, (total, factor) => total + factor.scoreAwarded);
    final score = availableMaximum == 0
        ? 0
        : math
            .min(100, math.max(0, (awarded * 100 / availableMaximum).round()))
            .toInt();
    final outcome = score >= 70
        ? ProposalAssessmentOutcome.recommended
        : score >= 45
            ? ProposalAssessmentOutcome.furtherReviewRequired
            : ProposalAssessmentOutcome.notRecommended;

    return ProposalAssessment(
      proposalId: proposal.id,
      score: score,
      outcome: outcome,
      factors: List<ProposalAssessmentFactor>.unmodifiable(factors),
      nearbyStationLocationCount: nearbyStationLocations,
      gapAnalysisAvailable: gapAnalysisAvailable,
      relatedGap: relatedGapMatch?.area,
      distanceToGapKm: relatedGapMatch?.distanceKm,
      nearbyProposal: duplicate?.proposal,
      nearbyProposalDistanceKm: duplicate?.distanceKm,
    );
  }

  ProposalAssessmentFactor _infrastructureFactor(
    Proposal proposal,
    int? nearbyLocations, {
    required bool available,
  }) {
    if (!available || nearbyLocations == null) {
      return const ProposalAssessmentFactor(
        name: 'Infrastructure scarcity',
        observedValue: 'Location data unavailable',
        scoreAwarded: 0,
        maximumScore: 30,
        explanation: 'Infrastructure coverage could not be measured because valid proposal coordinates or station data are unavailable.',
        available: false,
      );
    }

    final distanceScore = proposal.distance >= 10
        ? 20
        : proposal.distance >= 5
            ? 15
            : proposal.distance >= 2
                ? 8
                : 2;
    final nearbyScore = nearbyLocations == 0
        ? 10
        : nearbyLocations <= 2
            ? 7
            : nearbyLocations <= 5
                ? 4
                : 0;
    final limited = nearbyLocations <= 2 && proposal.distance >= 5;
    return ProposalAssessmentFactor(
      name: 'Infrastructure scarcity',
      observedValue:
          '${proposal.distance.toStringAsFixed(1)} km nearest; $nearbyLocations locations within 10 km',
      scoreAwarded: distanceScore + nearbyScore,
      maximumScore: 30,
      explanation: limited
          ? 'The proposed area currently has limited nearby charging infrastructure.'
          : 'The score reflects the measured nearest-station distance and distinct nearby charging locations.',
    );
  }

  ProposalAssessmentFactor _gapFactor(
    _GapMatch? match, {
    required bool available,
  }) {
    if (!available) {
      return const ProposalAssessmentFactor(
        name: 'Coverage-gap relationship',
        observedValue: 'Current gap analysis unavailable',
        scoreAwarded: 0,
        maximumScore: 25,
        explanation: 'No compatible cached coverage-gap result is available for this proposal location.',
        available: false,
      );
    }
    if (match == null || match.distanceKm > gapRelationshipRadiusKm) {
      return const ProposalAssessmentFactor(
        name: 'Coverage-gap relationship',
        observedValue: 'Outside identified gap areas',
        scoreAwarded: 0,
        maximumScore: 25,
        explanation: 'The proposal is outside the current identified coverage gaps. This is neutral evidence and is not an automatic rejection.',
      );
    }

    final priority = match.area.priority.trim().toLowerCase();
    final awarded = priority == 'high'
        ? 25
        : priority == 'medium'
            ? 17
            : 8;
    return ProposalAssessmentFactor(
      name: 'Coverage-gap relationship',
      observedValue:
          '${match.area.priority} Priority gap, ${match.distanceKm.toStringAsFixed(1)} km away',
      scoreAwarded: awarded,
      maximumScore: 25,
      explanation: 'The proposed location is within 5 km of ${match.area.name}, a ${match.area.priority.toLowerCase()}-priority infrastructure coverage gap.',
    );
  }

  ProposalAssessmentFactor _expectedUsageFactor(String demand) {
    switch (demand.trim().toLowerCase()) {
      case 'high':
        return const ProposalAssessmentFactor(
          name: 'Self-reported expected usage',
          observedValue: 'High',
          scoreAwarded: 20,
          maximumScore: 20,
          explanation: 'The driver submitted High expected usage. This is self-reported and is not a demand prediction.',
        );
      case 'medium':
        return const ProposalAssessmentFactor(
          name: 'Self-reported expected usage',
          observedValue: 'Medium',
          scoreAwarded: 12,
          maximumScore: 20,
          explanation: 'The driver submitted Medium expected usage. This is self-reported and is not a demand prediction.',
        );
      case 'low':
        return const ProposalAssessmentFactor(
          name: 'Self-reported expected usage',
          observedValue: 'Low',
          scoreAwarded: 5,
          maximumScore: 20,
          explanation: 'The driver submitted Low expected usage. This is self-reported and is not a demand prediction.',
        );
      default:
        return ProposalAssessmentFactor(
          name: 'Self-reported expected usage',
          observedValue: demand.trim().isEmpty ? 'Unavailable' : demand,
          scoreAwarded: 0,
          maximumScore: 20,
          explanation: 'The submitted expected-usage value is unavailable or unsupported.',
          available: false,
        );
    }
  }

  ProposalAssessmentFactor _communitySupportFactor(int supports) {
    final awarded = supports >= 50
        ? 10
        : supports >= 30
            ? 8
            : supports >= 10
                ? 5
                : supports > 0
                    ? 2
                    : 0;
    return ProposalAssessmentFactor(
      name: 'Community support',
      observedValue: '$supports support${supports == 1 ? '' : 's'}',
      scoreAwarded: awarded,
      maximumScore: 10,
      explanation: '$supports users currently support this proposal. Community support contributes evidence but is not a mandatory approval gate.',
    );
  }

  ProposalAssessmentFactor _settlementFactor(Proposal proposal) {
    final hasState = proposal.state?.trim().isNotEmpty == true;
    final hasSettlement = proposal.nearestTown?.trim().isNotEmpty == true;
    if (!hasState && !hasSettlement) {
      return const ProposalAssessmentFactor(
        name: 'Settlement relevance',
        observedValue: 'Unavailable',
        scoreAwarded: 0,
        maximumScore: 10,
        explanation: 'Verified state and settlement context is unavailable.',
        available: false,
      );
    }
    final awarded = hasState && hasSettlement ? 10 : 6;
    final observed = hasSettlement
        ? '${proposal.nearestTown}, ${proposal.state ?? 'state unavailable'}'
        : proposal.state!;
    return ProposalAssessmentFactor(
      name: 'Settlement relevance',
      observedValue: observed,
      scoreAwarded: awarded,
      maximumScore: 10,
      explanation: hasState && hasSettlement
          ? 'The proposal has verified state and nearest-settlement context.'
          : 'Only partial verified location context is available. No population claim is inferred.',
    );
  }

  ProposalAssessmentFactor _duplicationFactor(
    _ProposalMatch? duplicate, {
    required bool available,
  }) {
    if (!available) {
      return const ProposalAssessmentFactor(
        name: 'Nearby proposal duplication risk',
        observedValue: 'Location data unavailable',
        scoreAwarded: 0,
        maximumScore: 5,
        explanation: 'Nearby proposal duplication could not be checked.',
        available: false,
      );
    }
    if (duplicate == null || duplicate.distanceKm > duplicateConcernRadiusKm) {
      return const ProposalAssessmentFactor(
        name: 'Nearby proposal duplication risk',
        observedValue: 'No pending or approved proposal within 5 km',
        scoreAwarded: 5,
        maximumScore: 5,
        explanation: 'No nearby active proposal duplication concern was identified.',
      );
    }
    final strong = duplicate.distanceKm <= strongDuplicateConcernRadiusKm;
    return ProposalAssessmentFactor(
      name: 'Nearby proposal duplication risk',
      observedValue:
          '${duplicate.proposal.city}, ${duplicate.distanceKm.toStringAsFixed(1)} km away',
      scoreAwarded: strong ? 0 : 2,
      maximumScore: 5,
      explanation: 'Another ${duplicate.proposal.status.toLowerCase()} proposal exists ${duplicate.distanceKm.toStringAsFixed(1)} km from this location. This is a review concern, not an automatic rejection.',
    );
  }

  int _nearbyDistinctStationLocations(
    Proposal proposal,
    List<ChargingStation> stations,
  ) {
    final nearby = stations.where((station) {
      return _distanceKm(
            proposal.latitude!,
            proposal.longitude!,
            station.latitude,
            station.longitude,
          ) <=
          nearbyInfrastructureRadiusKm;
    }).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final representatives = <ChargingStation>[];
    for (final station in nearby) {
      final sameSite = representatives.any(
        (site) =>
            _distanceKm(
              site.latitude,
              site.longitude,
              station.latitude,
              station.longitude,
            ) <=
            stationSiteGroupingRadiusKm,
      );
      if (!sameSite) representatives.add(station);
    }
    return representatives.length;
  }

  _GapMatch? _nearestGap(Proposal proposal, List<GapArea> gaps) {
    _GapMatch? nearest;
    for (final area in gaps) {
      if (area.latitude == null || area.longitude == null) continue;
      final distance = _distanceKm(
        proposal.latitude!,
        proposal.longitude!,
        area.latitude!,
        area.longitude!,
      );
      if (nearest == null || distance < nearest.distanceKm) {
        nearest = _GapMatch(area, distance);
      }
    }
    return nearest;
  }

  _ProposalMatch? _nearestRelevantProposal(
    Proposal proposal,
    List<Proposal> proposals,
  ) {
    _ProposalMatch? nearest;
    for (final other in proposals) {
      if (other.id == proposal.id ||
          other.latitude == null ||
          other.longitude == null) {
        continue;
      }
      final status = other.status.trim().toLowerCase();
      if (status != 'pending' && status != 'approved') continue;
      final distance = _distanceKm(
        proposal.latitude!,
        proposal.longitude!,
        other.latitude!,
        other.longitude!,
      );
      if (nearest == null || distance < nearest.distanceKm) {
        nearest = _ProposalMatch(other, distance);
      }
    }
    return nearest;
  }

  double _distanceKm(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusKm = 6371.0088;
    final latitudeDelta = _radians(latitudeB - latitudeA);
    final longitudeDelta = _radians(longitudeB - longitudeA);
    final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(_radians(latitudeA)) *
            math.cos(_radians(latitudeB)) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _radians(double degrees) => degrees * math.pi / 180;
}

class _GapMatch {
  const _GapMatch(this.area, this.distanceKm);
  final GapArea area;
  final double distanceKm;
}

class _ProposalMatch {
  const _ProposalMatch(this.proposal, this.distanceKm);
  final Proposal proposal;
  final double distanceKm;
}
