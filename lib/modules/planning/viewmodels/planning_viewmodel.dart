import 'package:flutter/foundation.dart';
import '../models/proposal.dart';
import '../services/planning_repository.dart';

class PlanningViewModel extends ChangeNotifier {
  PlanningViewModel(this._repository);
  final PlanningRepository _repository;
  List<Proposal> proposals = [];
  List<GapArea> gaps = [];
  List<ChargingStation> stations = [];
  int stationCount = 0;
  bool loading = true;
  String? errorMessage;

  int get proposalCount => proposals.length;
  int get communitySupportCount =>
      proposals.fold(0, (sum, proposal) => sum + proposal.supports);
  int get highPriorityCount =>
      gaps.where((gap) => gap.priority == 'High').length;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.getProposals(),
        _repository.getGaps(),
        _repository.getStationCount(),
        _repository.getStations(),
      ]);
      proposals = results[0] as List<Proposal>;
      gaps = results[1] as List<GapArea>;
      stationCount = results[2] as int;
      stations = results[3] as List<ChargingStation>;
    } catch (error) {
      errorMessage = 'Unable to load planning data: $error';
    }
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
