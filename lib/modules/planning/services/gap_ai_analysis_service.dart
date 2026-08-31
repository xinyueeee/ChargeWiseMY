import 'package:flutter/foundation.dart';
import '../models/proposal.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GapAiAnalysisContext {
  const GapAiAnalysisContext({
    required this.state,
    required this.areaName,
    required this.analysisProfile,
    required this.priority,
    required this.priorityScore,
    required this.coverageScore,
    required this.nearestLocationDistanceKm,
    required this.nearbyLocationCount,
    required this.nearbyRadiusKm,
    required this.localLocationCount,
    required this.reason,
    this.settlementName,
    this.settlementCategory,
    this.plannedInfrastructure,
  });

  factory GapAiAnalysisContext.fromArea(
    GapArea area, {
    String? displayName,
    PlannedInfrastructureContext? plannedInfrastructure,
  }) =>
      GapAiAnalysisContext(
        state: area.state,
        areaName: displayName ?? area.name,
        analysisProfile: area.analysisProfileId,
        priority: area.priority,
        priorityScore: area.priorityScore,
        coverageScore: area.coverageScore,
        nearestLocationDistanceKm: area.distance,
        nearbyLocationCount: area.nearbyStationCount,
        nearbyRadiusKm: area.nearbyRadiusKm,
        localLocationCount: area.localStationLocationCount,
        reason: area.reason,
        settlementName: area.nearestSettlementName,
        settlementCategory: area.nearestSettlementCategory,
        plannedInfrastructure: plannedInfrastructure,
      );

  final String state;
  final String areaName;
  final String analysisProfile;
  final String priority;
  final double priorityScore;
  final double coverageScore;
  final double nearestLocationDistanceKm;
  final int nearbyLocationCount;
  final double nearbyRadiusKm;
  final int localLocationCount;
  final String reason;
  final String? settlementName;
  final String? settlementCategory;
  final PlannedInfrastructureContext? plannedInfrastructure;

  Map<String, Object?> toJson() => {
        'state': state,
        'analysedArea': areaName,
        'analysisProfile': analysisProfile,
        'priority': priority,
        'gapScore': priorityScore,
        'coverageScore': coverageScore,
        'nearestChargingLocationDistanceKm': nearestLocationDistanceKm,
        'nearbyChargingLocationCount': nearbyLocationCount,
        'nearbyRadiusKm': nearbyRadiusKm,
        'localChargingLocationCount': localLocationCount,
        'settlementName': settlementName,
        'settlementClassification': settlementCategory,
        'deterministicReason': reason,
        'nearestMevnetProposedLocationDistanceKm':
            plannedInfrastructure?.nearestDistanceKm,
        'nearbyMevnetProposedLocationCount':
            plannedInfrastructure?.nearbyLocationCount ?? 0,
        'nearbyMevnetProposedEvcbCount':
            plannedInfrastructure?.nearbyProposedChargerCount ?? 0,
        'plannedNearbyRadiusKm':
            plannedInfrastructure?.radiusKm ?? nearbyRadiusKm,
      };
}

class GapAiAnalysisResult {
  const GapAiAnalysisResult({
    required this.interpretation,
    required this.keyConsiderations,
    required this.suggestedNextStep,
  });

  final String interpretation;
  final List<String> keyConsiderations;
  final String suggestedNextStep;

  factory GapAiAnalysisResult.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final considerations = json['keyConsiderations'];
    final nextStep = json['suggestedNextStep'];
    if (summary is! String ||
        summary.trim().isEmpty ||
        considerations is! List ||
        nextStep is! String ||
        nextStep.trim().isEmpty) {
      throw const FormatException('Invalid Gap AI response.');
    }
    final items = considerations
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (items.isEmpty || items.length > 3) {
      throw const FormatException('Invalid AI considerations.');
    }
    return GapAiAnalysisResult(
      interpretation: summary.trim(),
      keyConsiderations: items,
      suggestedNextStep: nextStep.trim(),
    );
  }
}

abstract interface class GapAiAnalysisService {
  Future<GapAiAnalysisResult> generate(GapAiAnalysisContext context);
}

enum GapAiFailureReason { rateLimited, timeout, authentication, unavailable }

class SupabaseGapAiAnalysisService implements GapAiAnalysisService {
  const SupabaseGapAiAnalysisService();

  @override
  Future<GapAiAnalysisResult> generate(GapAiAnalysisContext context) async {
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) {
      throw const GapAiAnalysisUnavailableException(
        'Sign in is required to generate an AI analysis.',
        reason: GapAiFailureReason.authentication,
      );
    }
    try {
      final response = await client.functions.invoke(
        'gap-ai-analysis',
        body: context.toJson(),
      );
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Unexpected Gap AI response.');
      }
      return GapAiAnalysisResult.fromJson(Map<String, dynamic>.from(data));
    } on FunctionException catch (error) {
      if (kDebugMode) {
        debugPrint(
          'Gap AI function failure: status=${error.status}, '
          'details=${_safeFunctionDetails(error.details)}',
        );
      }
      final reason = switch (error.status) {
        429 => GapAiFailureReason.rateLimited,
        504 => GapAiFailureReason.timeout,
        401 || 403 => GapAiFailureReason.authentication,
        _ => GapAiFailureReason.unavailable,
      };
      throw GapAiAnalysisUnavailableException(
        'Gap AI function failed (${error.status}).',
        reason: reason,
      );
    } on FormatException {
      rethrow;
    } catch (error) {
      throw GapAiAnalysisUnavailableException('Gap AI request failed: $error');
    }
  }

  String _safeFunctionDetails(dynamic details) {
    if (details is! Map) return 'unavailable';
    final error = details['error'];
    final field = details['field'];
    final providerCode = details['providerCode'];
    final providerMessage = details['providerMessage'];
    return 'error=${error is String ? error : 'unknown'}, '
        'field=${field is String ? field : 'none'}, '
        'providerCode=${providerCode is String ? providerCode : 'none'}, '
        'providerMessage=${providerMessage is String ? providerMessage : 'none'}';
  }
}

class UnconfiguredGapAiAnalysisService implements GapAiAnalysisService {
  const UnconfiguredGapAiAnalysisService();

  static const systemInstruction = '''
You are an EV infrastructure planning assistant for ChargeWiseMY.
Interpret only the supplied deterministic Gap Analysis result. Never change,
recalculate, contradict, or invent its score, priority, distances, counts, or
classifications. Clearly separate supplied facts from unknown site conditions.
Do not assume traffic, population, EV demand, parking suitability, electrical
capacity, land ownership, or commercial viability. Provide concise planning
guidance, not a final infrastructure decision.
''';

  @override
  Future<GapAiAnalysisResult> generate(GapAiAnalysisContext context) {
    throw const GapAiAnalysisUnavailableException(
      'A secure server-side AI endpoint has not been configured.',
    );
  }
}

class GapAiAnalysisUnavailableException implements Exception {
  const GapAiAnalysisUnavailableException(
    this.message, {
    this.reason = GapAiFailureReason.unavailable,
  });
  final String message;
  final GapAiFailureReason reason;

  @override
  String toString() => message;
}
