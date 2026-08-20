import '../../models/proposal.dart';
import '../models/proposal_assessment.dart';

class AdminAssistantMessage {
  const AdminAssistantMessage({
    required this.text,
    required this.fromAdministrator,
  });

  final String text;
  final bool fromAdministrator;
}

class AdminPlanningAssistantService {
  const AdminPlanningAssistantService();

  String answer({
    required String question,
    required Proposal proposal,
    required ProposalAssessment assessment,
  }) {
    final normalized = question.trim().toLowerCase();
    if (normalized.contains('why') &&
        (normalized.contains('recommend') || normalized.contains('score'))) {
      final strongest = [...assessment.factors]
        ..sort((a, b) {
          final aRatio = a.available && a.maximumScore > 0
              ? a.scoreAwarded / a.maximumScore
              : -1;
          final bRatio = b.available && b.maximumScore > 0
              ? b.scoreAwarded / b.maximumScore
              : -1;
          return bRatio.compareTo(aRatio);
        });
      final evidence = strongest
          .where((factor) => factor.available && factor.scoreAwarded > 0)
          .take(3)
          .map((factor) =>
              '${factor.name}: ${factor.scoreAwarded}/${factor.maximumScore}')
          .join('; ');
      return 'The rule-based assessment is ${assessment.outcome.label} at '
          '${assessment.score}/100. The strongest available evidence is '
          '${evidence.isEmpty ? 'not sufficient to identify a strong factor' : evidence}. '
          'The current administrative status is ${proposal.status}. '
          'Administrative approval remains a separate decision.';
    }

    if (normalized.contains('risk') || normalized.contains('weak')) {
      final weakest = assessment.factors
          .where((factor) => factor.available)
          .toList()
        ..sort((a, b) {
          final aRatio = a.maximumScore == 0
              ? 0
              : a.scoreAwarded / a.maximumScore;
          final bRatio = b.maximumScore == 0
              ? 0
              : b.scoreAwarded / b.maximumScore;
          return aRatio.compareTo(bRatio);
        });
      if (weakest.isEmpty) {
        return 'The current dataset does not provide enough verified evidence to rank weaknesses.';
      }
      return weakest
          .take(3)
          .map((factor) => '${factor.name}: ${factor.explanation}')
          .join('\n');
    }

    if (normalized.contains('infrastructure') ||
        normalized.contains('nearest station') ||
        normalized.contains('coverage')) {
      final locations = assessment.nearbyStationLocationCount;
      return 'The nearest existing charging station is '
          '${proposal.distance.toStringAsFixed(1)} km away. '
          '${locations == null ? 'The nearby charging-location count is unavailable.' : 'There are $locations distinct charging locations within 10 km.'}';
    }

    if (normalized.contains('gap')) {
      final gap = assessment.relatedGap;
      if (!assessment.gapAnalysisAvailable) {
        return 'A compatible cached coverage-gap result is not currently available for this proposal.';
      }
      if (gap == null) {
        return 'This proposal is outside the identified coverage-gap areas. That is neutral evidence and does not automatically reject it.';
      }
      return 'The proposal is ${assessment.distanceToGapKm!.toStringAsFixed(1)} km from '
          '${gap.name}, classified ${gap.priority} Priority with a '
          '${gap.priorityScore.toStringAsFixed(0)} coverage-gap priority score.';
    }

    if (normalized.contains('nearby proposal') ||
        normalized.contains('similar proposal') ||
        normalized.contains('duplicate')) {
      final nearby = assessment.nearbyProposal;
      if (nearby == null) {
        return 'No pending or approved proposal was identified within 5 km.';
      }
      return '“${nearby.city}” is ${assessment.nearbyProposalDistanceKm!.toStringAsFixed(1)} km away and currently ${nearby.status}. This is a review concern, not an automatic rejection.';
    }

    if (normalized.contains('verify') ||
        normalized.contains('before approving')) {
      return 'Before deciding, verify road accessibility, land ownership, parking availability, zoning, electrical capacity, traffic conditions, construction feasibility, and cost. These items are not available in the current dataset. Also review the submitted description, location, infrastructure measurements, nearby proposals, and community support.';
    }

    if (normalized.contains('status')) {
      return 'The current administrative status is ${proposal.status}. The independent system assessment is ${assessment.outcome.label} at ${assessment.score}/100. Changing administrative status does not change the assessment score.';
    }

    return 'I can answer grounded questions about this proposal’s rule-based score, infrastructure coverage, coverage-gap relationship, nearby proposals, community support, current administrative status, and known limitations. Road access, land ownership, parking availability, electrical capacity, population, traffic, zoning, cost, and future EV demand are not available in the current dataset.';
  }
}
