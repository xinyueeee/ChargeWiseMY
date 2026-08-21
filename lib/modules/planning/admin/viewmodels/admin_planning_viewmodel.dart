import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../models/proposal.dart';
import '../../services/state_boundary_service.dart';
import '../../viewmodels/planning_viewmodel.dart';
import '../models/proposal_assessment.dart';
import '../services/admin_planning_assistant_service.dart';
import '../services/proposal_suitability_assessment_service.dart';

class AdminPlanningViewModel extends ChangeNotifier {
  AdminPlanningViewModel(
    this._planning, {
    ProposalSuitabilityAssessmentService assessmentService =
        const ProposalSuitabilityAssessmentService(),
    AdminPlanningAssistantService assistantService =
        const AdminPlanningAssistantService(),
  })  : _assessmentService = assessmentService,
        _assistantService = assistantService {
    _planning.addListener(_handlePlanningChanged);
    _synchronize(force: true);
  }

  final PlanningViewModel _planning;
  final ProposalSuitabilityAssessmentService _assessmentService;
  final AdminPlanningAssistantService _assistantService;

  Map<String, ProposalAssessment> _assessments = const {};
  String _sourceFingerprint = '';
  String _searchQuery = '';
  String _selectedState = 'All States';
  String _selectedStatus = 'All Statuses';
  final Set<String> _updatingProposalIds = {};
  String? statusErrorMessage;

  bool get loading => _planning.loading;
  String? get loadingErrorMessage => _planning.errorMessage;
  List<Proposal> get proposals => List<Proposal>.unmodifiable(_planning.proposals);
  List<ChargingStation> get stations =>
      List<ChargingStation>.unmodifiable(_planning.stations);
  List<GapArea> get currentGapAreas =>
      List<GapArea>.unmodifiable(_planning.priorityAreas);
  String get searchQuery => _searchQuery;
  String get selectedState => _selectedState;
  String get selectedStatus => _selectedStatus;

  int get totalProposalCount => _planning.proposals.length;
  int get pendingProposalCount => _statusCount('pending');
  int get approvedProposalCount => _statusCount('approved');
  int get rejectedProposalCount => _statusCount('rejected');
  int get requiringReviewCount => _assessments.values
      .where((assessment) =>
          assessment.outcome ==
          ProposalAssessmentOutcome.furtherReviewRequired)
      .length;
  int get recommendedAssessmentCount => _assessments.values
      .where(
        (assessment) =>
            assessment.outcome == ProposalAssessmentOutcome.recommended,
      )
      .length;

  List<String> get stateOptions {
    final states = _planning.proposals
        .map((proposal) => proposal.state?.trim())
        .whereType<String>()
        .where((state) => state.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['All States', ...states];
  }

  List<String> get statusOptions {
    final statuses = <String>{'Pending', 'Approved', 'Rejected'};
    for (final proposal in _planning.proposals) {
      if (proposal.status.trim().isNotEmpty) statuses.add(proposal.status.trim());
    }
    final sorted = statuses.toList()..sort();
    return ['All Statuses', ...sorted];
  }

  List<Proposal> get filteredProposals {
    final query = _searchQuery.trim().toLowerCase();
    final result = _planning.proposals.where((proposal) {
      final matchesState = _selectedState == 'All States' ||
          proposal.state == _selectedState;
      final matchesStatus = _selectedStatus == 'All Statuses' ||
          proposal.status.toLowerCase() == _selectedStatus.toLowerCase();
      final matchesSearch = query.isEmpty ||
          proposal.city.toLowerCase().contains(query) ||
          proposal.description.toLowerCase().contains(query) ||
          proposal.locationLabel.toLowerCase().contains(query) ||
          (proposal.state?.toLowerCase().contains(query) ?? false) ||
          (proposal.nearestTown?.toLowerCase().contains(query) ?? false);
      return matchesState && matchesStatus && matchesSearch;
    }).toList()
      ..sort((a, b) {
        final dateComparison = (b.createdAt ?? DateTime(1970))
            .compareTo(a.createdAt ?? DateTime(1970));
        return dateComparison != 0 ? dateComparison : a.city.compareTo(b.city);
      });
    return List<Proposal>.unmodifiable(result);
  }

  ProposalAssessment? assessmentFor(Proposal proposal) =>
      _assessments[proposal.id];

  Proposal? proposalById(String proposalId) {
    for (final proposal in _planning.proposals) {
      if (proposal.id == proposalId) return proposal;
    }
    return null;
  }

  bool isUpdating(Proposal proposal) =>
      _updatingProposalIds.contains(proposal.id);

  void setSearchQuery(String value) {
    if (_searchQuery == value) return;
    _searchQuery = value;
    notifyListeners();
  }

  void setStateFilter(String value) {
    if (_selectedState == value) return;
    _selectedState = value;
    notifyListeners();
  }

  void setStatusFilter(String value) {
    if (_selectedStatus == value) return;
    _selectedStatus = value;
    notifyListeners();
  }

  void showPendingProposals() {
    _searchQuery = '';
    _selectedState = 'All States';
    _selectedStatus = 'Pending';
    notifyListeners();
  }

  void showAllProposals() {
    _searchQuery = '';
    _selectedState = 'All States';
    _selectedStatus = 'All Statuses';
    notifyListeners();
  }

  Future<void> reload() => _planning.load();

  Future<bool> updateStatus(Proposal proposal, String status) async {
    if (_updatingProposalIds.contains(proposal.id)) return false;
    _updatingProposalIds.add(proposal.id);
    statusErrorMessage = null;
    notifyListeners();
    try {
      await _planning.setStatus(proposal, status);
      return true;
    } catch (error, stackTrace) {
      statusErrorMessage = 'Unable to update proposal status. Please try again.';
      debugPrint('Admin proposal status update failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      _updatingProposalIds.remove(proposal.id);
      notifyListeners();
    }
  }

  String answerAssistantQuestion({
    required String question,
    required Proposal proposal,
  }) {
    final assessment = assessmentFor(proposal);
    if (assessment == null) {
      return 'The rule-based proposal assessment is not available yet.';
    }
    return _assistantService.answer(
      question: question,
      proposal: proposal,
      assessment: assessment,
    );
  }

  List<ChargingStation> nearbyStationsForMap(
    Proposal proposal, {
    double radiusKm = 15,
    int maximum = 80,
  }) {
    if (proposal.latitude == null || proposal.longitude == null) return const [];
    final candidates = <_StationDistance>[];
    for (final station in _planning.stations) {
      final distance = _distanceKm(
        proposal.latitude!,
        proposal.longitude!,
        station.latitude,
        station.longitude,
      );
      if (distance <= radiusKm) candidates.add(_StationDistance(station, distance));
    }
    candidates.sort((a, b) {
      final distanceComparison = a.distanceKm.compareTo(b.distanceKm);
      return distanceComparison != 0
          ? distanceComparison
          : a.station.id.compareTo(b.station.id);
    });
    return List<ChargingStation>.unmodifiable(
      candidates.take(maximum).map((item) => item.station),
    );
  }

  void _handlePlanningChanged() => _synchronize();

  void _synchronize({bool force = false}) {
    final fingerprint = _buildSourceFingerprint();
    if (!force && fingerprint == _sourceFingerprint) return;
    _sourceFingerprint = fingerprint;
    final gapAvailable = _planning.analysisReady;
    final result = <String, ProposalAssessment>{};
    for (final proposal in _planning.proposals) {
      final compatibleGapContext = gapAvailable &&
          (_planning.selectedState == malaysiaSelection ||
              proposal.state == _planning.selectedState);
      result[proposal.id] = _assessmentService.assess(
        proposal: proposal,
        stations: _planning.stations,
        proposals: _planning.proposals,
        gaps: _planning.priorityAreas,
        gapAnalysisAvailable: compatibleGapContext,
      );
    }
    _assessments = Map<String, ProposalAssessment>.unmodifiable(result);
    notifyListeners();
  }

  String _buildSourceFingerprint() {
    final proposalToken = _planning.proposals.map((proposal) =>
        '${proposal.id}:${proposal.status}:${proposal.displayedSupports}:${proposal.distance}:${proposal.demand}:${proposal.latitude}:${proposal.longitude}:${proposal.state}:${proposal.nearestTown}').join('|');
    final gapToken = _planning.priorityAreas.map((area) =>
        '${area.id}:${area.priority}:${area.priorityScore}:${area.latitude}:${area.longitude}').join('|');
    return '${_planning.loading}|${identityHashCode(_planning.stations)}|'
        '${_planning.stations.length}|${identityHashCode(_planning.priorityAreas)}|'
        '${_planning.selectedState}|$proposalToken|$gapToken';
  }

  int _statusCount(String status) => _planning.proposals
      .where((proposal) => proposal.status.trim().toLowerCase() == status)
      .length;

  double _distanceKm(
    double latitudeA,
    double longitudeA,
    double latitudeB,
    double longitudeB,
  ) {
    const earthRadiusKm = 6371.0088;
    const degreesToRadians = 0.017453292519943295;
    final latitudeDelta = (latitudeB - latitudeA) * degreesToRadians;
    final longitudeDelta = (longitudeB - longitudeA) * degreesToRadians;
    final a = math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
        math.cos(latitudeA * degreesToRadians) *
            math.cos(latitudeB * degreesToRadians) *
            math.sin(longitudeDelta / 2) *
            math.sin(longitudeDelta / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  void dispose() {
    _planning.removeListener(_handlePlanningChanged);
    super.dispose();
  }
}

class _StationDistance {
  const _StationDistance(this.station, this.distanceKm);
  final ChargingStation station;
  final double distanceKm;
}
