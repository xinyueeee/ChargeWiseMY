import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/proposal.dart';
import '../models/proposal_assessment.dart';

enum AdminAiReviewFailureReason {
  rateLimited,
  timeout,
  authentication,
  forbidden,
  unavailable,
}

class AdminProposalAiReview {
  const AdminProposalAiReview({
    required this.summary,
    required this.strengths,
    required this.concerns,
    required this.suggestedFollowUp,
  });

  factory AdminProposalAiReview.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final strengths = _textItems(json['strengths']);
    final concerns = _textItems(json['concerns']);
    final followUp = json['suggestedFollowUp'];
    if (summary is! String ||
        summary.trim().isEmpty ||
        strengths.isEmpty ||
        concerns.isEmpty ||
        followUp is! String ||
        followUp.trim().isEmpty) {
      throw const FormatException('Invalid Admin AI review response.');
    }
    return AdminProposalAiReview(
      summary: summary.trim(),
      strengths: strengths.take(3).toList(growable: false),
      concerns: concerns.take(3).toList(growable: false),
      suggestedFollowUp: followUp.trim(),
    );
  }

  final String summary;
  final List<String> strengths;
  final List<String> concerns;
  final String suggestedFollowUp;

  static List<String> _textItems(dynamic value) => value is List
      ? value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
      : const [];
}

class AdminAiReviewException implements Exception {
  const AdminAiReviewException(this.reason);
  final AdminAiReviewFailureReason reason;
}

class AdminProposalAiReviewService {
  const AdminProposalAiReviewService();

  Future<AdminProposalAiReview> generate({
    required Proposal proposal,
    required ProposalAssessment assessment,
    PlannedInfrastructureContext? plannedInfrastructure,
  }) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw const AdminAiReviewException(
        AdminAiReviewFailureReason.authentication,
      );
    }
    try {
      final response = await client.functions.invoke(
        'admin-proposal-ai-review',
        body: {
          'proposal': {
            'name': proposal.city,
            'state': proposal.state,
            'locality': proposal.nearestTown ?? proposal.locationLabel,
            'expectedUsage': proposal.demand,
            'communitySupport': proposal.supportCount,
            'communityNotSupport': proposal.opposeCount,
            'nearestChargingLocationDistanceKm': proposal.distance,
            'currentAdministrativeStatus': proposal.status,
          },
          'assessment': {
            'score': assessment.score,
            'outcome': assessment.outcome.label,
            'nearbyChargingLocationCount':
                assessment.nearbyStationLocationCount,
            'coverageGapAvailable': assessment.gapAnalysisAvailable,
            'relatedGapPriority': assessment.relatedGap?.priority,
            'distanceToRelatedGapKm': assessment.distanceToGapKm,
            'nearbyActiveProposalDistanceKm':
                assessment.nearbyProposalDistanceKm,
            'factors': [
              for (final factor in assessment.factors)
                {
                  'name': factor.name,
                  'observedValue': factor.observedValue,
                  'scoreAwarded': factor.scoreAwarded,
                  'maximumScore': factor.maximumScore,
                  'available': factor.available,
                  'explanation': factor.explanation,
                },
            ],
          },
          'plannedInfrastructure': {
            'source': 'MEVnet / PLANMalaysia',
            'status': 'Newly Proposed',
            'nearestProposedLocationDistanceKm':
                plannedInfrastructure?.nearestDistanceKm,
            'nearbyProposedLocationCount':
                plannedInfrastructure?.nearbyLocationCount ?? 0,
            'nearbyProposedEvcbCount':
                plannedInfrastructure?.nearbyProposedChargerCount ?? 0,
            'nearbyRadiusKm': plannedInfrastructure?.radiusKm,
          },
        },
      );
      if (response.data is! Map) {
        throw const FormatException('Unexpected Admin AI response.');
      }
      return AdminProposalAiReview.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } on FunctionException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Admin AI review failed: status=${error.status}, '
          'details=${_safeDetails(error.details)}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      final reason = switch (error.status) {
        429 => AdminAiReviewFailureReason.rateLimited,
        504 => AdminAiReviewFailureReason.timeout,
        401 => AdminAiReviewFailureReason.authentication,
        403 => AdminAiReviewFailureReason.forbidden,
        _ => AdminAiReviewFailureReason.unavailable,
      };
      throw AdminAiReviewException(reason);
    } on FormatException {
      rethrow;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Admin AI review request failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      throw const AdminAiReviewException(
        AdminAiReviewFailureReason.unavailable,
      );
    }
  }

  String _safeDetails(dynamic details) {
    if (details is! Map) return 'unavailable';
    final error = details['error'];
    final providerCode = details['providerCode'];
    return 'error=${error is String ? error : 'unknown'}, '
        'providerCode=${providerCode is String ? providerCode : 'none'}';
  }
}
