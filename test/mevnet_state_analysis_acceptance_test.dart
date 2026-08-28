import 'dart:convert';
import 'dart:io';

import 'package:chargewise_my/modules/planning/models/proposal.dart';
import 'package:chargewise_my/modules/planning/services/coverage_gap_analyzer.dart';
import 'package:chargewise_my/modules/planning/services/state_boundary_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<ChargingStation> existingLocations;

  setUpAll(() async {
    final source = await File(
      'tools/mevnet/staging/mevnet_staging.json',
    ).readAsString();
    final rows = (jsonDecode(source) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .where((row) => row['include_for_existing_coverage'] == true);
    existingLocations = rows
        .map(ChargingStation.fromSupabase)
        .whereType<ChargingStation>()
        .toList(growable: false);
  });

  test('MEVnet snapshot retains one physical row per Existing location', () {
    expect(existingLocations, hasLength(1374));
    expect(
      existingLocations.fold<int>(
        0,
        (sum, station) => sum + (station.chargerCount ?? 0),
      ),
      4161,
    );
  });

  for (final state in const [
    malaysiaSelection,
    'Kuala Lumpur',
    'Selangor',
    'Labuan',
    'Perlis',
  ]) {
    test('actual Existing snapshot produces deterministic $state gaps',
        () async {
      const analyzer = CoverageGapAnalyzer();
      final first = await analyzer.analyze(
        existingLocations,
        selectedState: state,
      );
      final second = await analyzer.analyze(
        existingLocations.reversed.toList(growable: false),
        selectedState: state,
      );

      expect(first, isNotEmpty);
      if (state != malaysiaSelection) {
        expect(first.every((area) => area.state == state), isTrue);
      }
      expect(
        first.map((area) => area.id).toList(),
        second.map((area) => area.id).toList(),
      );
      expect(
        first.map((area) => area.priorityScore).toList(),
        second.map((area) => area.priorityScore).toList(),
      );
    });
  }
}
