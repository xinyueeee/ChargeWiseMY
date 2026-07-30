import 'package:flutter/foundation.dart';
import '../models/proposal.dart';
import '../services/planning_repository.dart';

class PlanningViewModel extends ChangeNotifier {
  PlanningViewModel(this._repository) {
    debugPrint(
      'PlanningViewModel created: instance=${identityHashCode(this)}.',
    );
  }

  final PlanningRepository _repository;
  List<Proposal> proposals = [];
  List<ChargingStation> stations = [];
  List<GapArea> _priorityAreas = const [];
  int stationCount = 0;
  bool loading = true;
  bool analyzingGaps = false;
  String? errorMessage;
  int _loadGeneration = 0;

  int get proposalCount => proposals.length;
  int get communitySupportCount =>
      proposals.fold(0, (sum, proposal) => sum + proposal.supports);
  List<GapArea> get priorityAreas => List.unmodifiable(_priorityAreas);
  int get highPriorityAreaCount => _priorityAreas.length;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    loading = true;
    analyzingGaps = false;
    errorMessage = null;
    notifyListeners();
    debugPrint(
      'PlanningViewModel load started: instance=${identityHashCode(this)}, '
      'generation=$generation.',
    );
    try {
      final results = await Future.wait([
        _repository.getProposals(),
        _repository.getStationCount(),
        _repository.getStations(),
      ]);
      if (generation != _loadGeneration) {
        debugPrint(
          'PlanningViewModel ignored stale station result: '
          'instance=${identityHashCode(this)}, generation=$generation.',
        );
        return;
      }
      proposals = results[0] as List<Proposal>;
      stationCount = results[1] as int;
      stations = results[2] as List<ChargingStation>;
      analyzingGaps = true;
      notifyListeners();
      debugPrint(
        'PlanningViewModel analysis requested: '
        'instance=${identityHashCode(this)}, generation=$generation, '
        'stationCount=${stations.length}.',
      );
      final detectedAreas = await _repository.getGaps(stations);
      if (generation != _loadGeneration) {
        debugPrint(
          'PlanningViewModel ignored stale coverage-gap result: '
          'instance=${identityHashCode(this)}, generation=$generation, '
          'resultCount=${detectedAreas.length}.',
        );
        return;
      }
      _priorityAreas = List.unmodifiable(detectedAreas);
      debugPrint(
        'PlanningViewModel analysis stored: '
        'instance=${identityHashCode(this)}, generation=$generation, '
        'stationCount=${stations.length}, '
        'priorityAreaCount=${_priorityAreas.length}.',
      );
    } catch (error, stackTrace) {
      if (generation != _loadGeneration) return;
      errorMessage = 'Unable to load planning data: $error';
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
  }

  Future<void> react(Proposal proposal, bool like) async {
    if (proposal.reaction == 0) {
      await _repository.reactToProposal(proposal, like);
      proposal.reaction = like ? 1 : -1;
      notifyListeners();
    }
  }

  String recommendation(Proposal p) =>
      p.demand == 'High' && p.distance > 5 && p.supports > 30
          ? 'Suitable Location'
          : 'Needs Further Review';
  Future<void> setStatus(Proposal p, String status) async {
    await _repository.updateStatus(p.id, status);
    p.status = status;
    notifyListeners();
  }

  Future<void> submitProposal(Proposal proposal) async {
    await _repository.submitProposal(proposal);
    await load();
  }
}
