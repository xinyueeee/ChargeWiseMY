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
  int _notifyListenersCount = 0;

  int get proposalCount => proposals.length;
  int get communitySupportCount =>
      proposals.fold(0, (sum, proposal) => sum + proposal.supports);
  List<GapArea> get priorityAreas => _priorityAreas;
  int get highPriorityAreaCount => _priorityAreas.length;

  @override
  void notifyListeners() {
    _notifyListenersCount++;
    debugPrint(
      'PlanningViewModel notifyListeners: '
      'instance=${identityHashCode(this)}, '
      'count=$_notifyListenersCount.',
    );
    super.notifyListeners();
  }

  Future<void> load() async {
    final initializationStopwatch = Stopwatch()..start();
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
      final stationResults = await Future.wait([
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
      stationCount = stationResults[0] as int;
      final loadedStations = stationResults[1] as List<ChargingStation>;
      if (!_sameStationData(stations, loadedStations)) {
        stations = loadedStations;
      }
      analyzingGaps = true;
      debugPrint(
        'PlanningViewModel analysis requested: '
        'instance=${identityHashCode(this)}, generation=$generation, '
        'stationCount=${stations.length}.',
      );
      final planningResults = await Future.wait([
        _repository.getProposals(stations),
        _repository.getGaps(stations),
      ]);
      final loadedProposals = planningResults[0] as List<Proposal>;
      final detectedAreas = planningResults[1] as List<GapArea>;
      if (generation != _loadGeneration) {
        debugPrint(
          'PlanningViewModel ignored stale coverage-gap result: '
          'instance=${identityHashCode(this)}, generation=$generation, '
          'resultCount=${detectedAreas.length}.',
        );
        return;
      }
      proposals = loadedProposals;
      _priorityAreas = detectedAreas;
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
    initializationStopwatch.stop();
    debugPrint(
      'PlanningViewModel initialization complete: '
      'instance=${identityHashCode(this)}, generation=$generation, '
      'duration=${initializationStopwatch.elapsedMilliseconds}ms, '
      'notifyListenersCount=$_notifyListenersCount, '
      'stations=${stations.length}, proposals=${proposals.length}, '
      'priorityAreas=${_priorityAreas.length}.',
    );
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

  bool _sameStationData(
    List<ChargingStation> current,
    List<ChargingStation> incoming,
  ) {
    if (current.length != incoming.length) return false;
    for (var index = 0; index < current.length; index++) {
      final a = current[index];
      final b = incoming[index];
      if (a.id != b.id ||
          a.latitude != b.latitude ||
          a.longitude != b.longitude ||
          a.name != b.name ||
          a.chargerType != b.chargerType) {
        return false;
      }
    }
    return true;
  }

}
