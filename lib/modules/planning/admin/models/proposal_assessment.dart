import '../../models/proposal.dart';

enum ProposalAssessmentOutcome {
  recommended,
  furtherReviewRequired,
  notRecommended,
}

extension ProposalAssessmentOutcomeLabel on ProposalAssessmentOutcome {
  String get label {
    switch (this) {
      case ProposalAssessmentOutcome.recommended:
        return 'Recommended';
      case ProposalAssessmentOutcome.furtherReviewRequired:
        return 'Further Review Required';
      case ProposalAssessmentOutcome.notRecommended:
        return 'Not Recommended';
    }
  }
}

class ProposalAssessmentFactor {
  const ProposalAssessmentFactor({
    required this.name,
    required this.observedValue,
    required this.scoreAwarded,
    required this.maximumScore,
    required this.explanation,
    this.available = true,
  });

  final String name;
  final String observedValue;
  final int scoreAwarded;
  final int maximumScore;
  final String explanation;
  final bool available;
}

class ProposalAssessment {
  const ProposalAssessment({
    required this.proposalId,
    required this.score,
    required this.outcome,
    required this.factors,
    required this.nearbyStationLocationCount,
    required this.gapAnalysisAvailable,
    this.relatedGap,
    this.distanceToGapKm,
    this.nearbyProposal,
    this.nearbyProposalDistanceKm,
  });

  final String proposalId;
  final int score;
  final ProposalAssessmentOutcome outcome;
  final List<ProposalAssessmentFactor> factors;
  final int? nearbyStationLocationCount;
  final bool gapAnalysisAvailable;
  final GapArea? relatedGap;
  final double? distanceToGapKm;
  final Proposal? nearbyProposal;
  final double? nearbyProposalDistanceKm;
}
