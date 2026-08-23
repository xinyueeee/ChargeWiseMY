import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/gap_ai_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Proposal proposal(
    String id,
    String status, {
    DateTime? createdAt,
  }) =>
      Proposal(
        id: id,
        city: 'Test location',
        description: 'Test proposal',
        supports: 0,
        status: status,
        area: 'Residential Area',
        charger: 'AC Charger',
        distance: 8,
        demand: 'Medium',
        createdAt: createdAt,
      );

  test('proposal statuses expose the expected lifecycle permissions', () {
    for (final status in [
      Proposal.statusPending,
      Proposal.statusUnderReview,
    ]) {
      final value = proposal(status, status);
      expect(value.isActive, isTrue);
      expect(value.isTerminal, isFalse);
      expect(value.canOwnerEdit, isTrue);
      expect(value.canOwnerDelete, isTrue);
    }

    for (final status in [
      Proposal.statusApproved,
      Proposal.statusRejected,
    ]) {
      final value = proposal(status, status);
      expect(value.isActive, isFalse);
      expect(value.isTerminal, isTrue);
      expect(value.canOwnerEdit, isFalse);
      expect(value.canOwnerDelete, isFalse);
    }
  });

  test('database statuses and reaction values normalize canonically', () {
    expect(Proposal.databaseStatus('under_review'), Proposal.statusUnderReview);
    expect(Proposal.databaseStatus('approved'), Proposal.statusApproved);
    expect(ProposalReaction.fromDatabase('Like'), ProposalReaction.support);
    expect(ProposalReaction.fromDatabase('Dislike'), ProposalReaction.oppose);
    expect(ProposalReaction.fromDatabase(null), isNull);
    expect(ProposalReaction.support.databaseValue, 'Like');
    expect(ProposalReaction.oppose.databaseValue, 'Dislike');
  });

  test('review queue puts unresolved work first and newest first within status',
      () {
    final values = [
      proposal('rejected', Proposal.statusRejected),
      proposal('pending-old', Proposal.statusPending,
          createdAt: DateTime.utc(2025)),
      proposal('approved', Proposal.statusApproved),
      proposal('review', Proposal.statusUnderReview),
      proposal('pending-new', Proposal.statusPending,
          createdAt: DateTime.utc(2026)),
    ]..sort(Proposal.compareForReviewQueue);

    expect(
      values.map((item) => item.id),
      ['review', 'pending-new', 'pending-old', 'approved', 'rejected'],
    );
  });

  test(
      'Gap AI serializes absent planned infrastructure as null and zero counts',
      () {
    final json = const GapAiAnalysisContext(
      state: 'Labuan',
      areaName: 'Test gap',
      analysisProfile: 'regional',
      priority: 'High',
      priorityScore: 90,
      coverageScore: 88,
      nearestLocationDistanceKm: 12,
      nearbyLocationCount: 0,
      nearbyRadiusKm: 25,
      localLocationCount: 0,
      reason: 'Coverage test',
    ).toJson();

    expect(json['nearestMevnetProposedLocationDistanceKm'], isNull);
    expect(json['nearbyMevnetProposedLocationCount'], 0);
    expect(json['nearbyMevnetProposedEvcbCount'], 0);
  });

  test('Gap AI preserves finite planned-infrastructure evidence', () {
    final json = const GapAiAnalysisContext(
      state: 'Selangor',
      areaName: 'Test gap',
      analysisProfile: 'urban',
      priority: 'Medium',
      priorityScore: 70,
      coverageScore: 65,
      nearestLocationDistanceKm: 7,
      nearbyLocationCount: 1,
      nearbyRadiusKm: 25,
      localLocationCount: 1,
      reason: 'Coverage test',
      plannedInfrastructure: PlannedInfrastructureContext(
        nearestDistanceKm: 1.4,
        nearbyLocationCount: 2,
        nearbyProposedChargerCount: 6,
        radiusKm: 25,
      ),
    ).toJson();

    expect(json['nearestMevnetProposedLocationDistanceKm'], 1.4);
    expect(json['nearbyMevnetProposedLocationCount'], 2);
    expect(json['nearbyMevnetProposedEvcbCount'], 6);
  });
}
