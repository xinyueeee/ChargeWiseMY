import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/proposal.dart';
import '../../widgets/planning_widgets.dart';
import '../models/proposal_assessment.dart';
import '../viewmodels/admin_planning_viewmodel.dart';
import 'admin_planning_assistant_screen.dart';
import 'admin_proposal_location_map_screen.dart';

class AdminProposalDetailsScreen extends StatelessWidget {
  const AdminProposalDetailsScreen({
    super.key,
    required this.proposalId,
  });

  final String proposalId;

  @override
  Widget build(BuildContext context) {
    return Consumer<AdminPlanningViewModel>(
      builder: (context, viewModel, _) {
        final proposal = viewModel.proposalById(proposalId);
        if (proposal == null) {
          return Scaffold(
            appBar: _appBar(),
            body: const PlanningEmptyState(
              icon: Icons.assignment_late_outlined,
              title: 'Proposal unavailable',
              message: 'This proposal is no longer available.',
            ),
          );
        }
        final assessment = viewModel.assessmentFor(proposal);
        return Scaffold(
          appBar: _appBar(),
          body: SafeArea(
            child: ListView(
              padding: planningPagePadding,
              children: [
                _ProposalHeader(proposal: proposal),
                planningSectionGap,
                const PlanningSectionTitle('Proposal information'),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    children: [
                      _InformationRow('Description',
                          proposal.description.trim().isEmpty
                              ? 'Not provided'
                              : proposal.description),
                      const Divider(height: 18),
                      const _InformationRow(
                        'Category',
                        'Unavailable in the current schema',
                      ),
                      const Divider(height: 18),
                      _InformationRow('Expected usage', proposal.demand),
                      const Divider(height: 18),
                      _InformationRow(
                          'Community support', '${proposal.displayedSupports}'),
                      const Divider(height: 18),
                      _InformationRow(
                          'Submitted', _formatDate(proposal.createdAt)),
                      const Divider(height: 18),
                      _InformationRow('Creator', proposal.createdBy),
                    ],
                  ),
                ),
                planningSectionGap,
                const PlanningSectionTitle('Location information'),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    children: [
                      _InformationRow(
                          'State', proposal.state ?? 'Unavailable'),
                      const Divider(height: 18),
                      _InformationRow('Nearest settlement',
                          proposal.nearestTown ?? 'Unavailable'),
                      const Divider(height: 18),
                      _InformationRow(
                        'Locality',
                        proposal.locationLabel.trim().isEmpty
                            ? 'Unavailable'
                            : proposal.locationLabel,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: proposal.latitude == null ||
                                  proposal.longitude == null
                              ? null
                              : () => _openMap(
                                    context,
                                    viewModel,
                                    proposal,
                                    assessment,
                                  ),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('View Proposed Location'),
                        ),
                      ),
                    ],
                  ),
                ),
                planningSectionGap,
                const PlanningSectionTitle('Infrastructure context'),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    children: [
                      _InformationRow(
                        'Nearest charging station',
                        '${proposal.distance.toStringAsFixed(1)} km',
                      ),
                      const Divider(height: 18),
                      _InformationRow(
                        'Nearby charging locations',
                        assessment?.nearbyStationLocationCount?.toString() ??
                            'Unavailable',
                      ),
                      const Divider(height: 18),
                      _InformationRow(
                        'Coverage-gap relationship',
                        _gapRelationship(assessment),
                      ),
                      const Divider(height: 18),
                      _InformationRow(
                        'Gap priority',
                        assessment?.relatedGap?.priority ?? 'Not applicable',
                      ),
                    ],
                  ),
                ),
                planningSectionGap,
                const PlanningSectionTitle('System assessment'),
                const SizedBox(height: 10),
                if (assessment == null)
                  const PlanningLoadingState(message: 'Assessing proposal…')
                else ...[
                  _AssessmentSummary(assessment: assessment),
                  const SizedBox(height: 12),
                  for (final factor in assessment.factors) ...[
                    _AssessmentFactorCard(factor: factor),
                    const SizedBox(height: 10),
                  ],
                ],
                planningSectionGap,
                const PlanningSectionTitle('Administrative information'),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    children: [
                      _InformationRow('Current status', proposal.status),
                      const Divider(height: 18),
                      _InformationRow(
                        'Assessment result',
                        assessment?.outcome.label ?? 'Assessing',
                      ),
                      const Divider(height: 18),
                      _InformationRow(
                        'Assessment score',
                        assessment == null ? 'Assessing' : '${assessment.score}/100',
                      ),
                      const Divider(height: 18),
                      const _InformationRow(
                        'Status history',
                        'Unavailable in the current schema',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.balance_outlined, color: green),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The system assessment is independent from the administrative status. An administrator remains responsible for the final decision.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: planningMutedTextColor,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                planningSectionGap,
                if (proposal.latitude != null && proposal.longitude != null)
                  AppCard(
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      leading: const Icon(Icons.code_outlined, color: green),
                      title: const Text(
                        'Technical Information',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      children: [
                        _InformationRow(
                          'Coordinates',
                          '${proposal.latitude!.toStringAsFixed(6)}, '
                              '${proposal.longitude!.toStringAsFixed(6)}',
                        ),
                      ],
                    ),
                  ),
                planningSectionGap,
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: assessment == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AdminPlanningAssistantScreen(
                                  proposalId: proposal.id,
                                ),
                              ),
                            ),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Open AI Planning Assistant'),
                  ),
                ),
                const SizedBox(height: 12),
                if (viewModel.statusErrorMessage != null) ...[
                  Text(
                    viewModel.statusErrorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFE74C3C)),
                  ),
                  const SizedBox(height: 10),
                ],
                _DecisionButtons(
                  updating: viewModel.isUpdating(proposal),
                  onApprove: () => _confirmStatus(
                    context,
                    viewModel,
                    proposal,
                    'Approved',
                  ),
                  onReject: () => _confirmStatus(
                    context,
                    viewModel,
                    proposal,
                    'Rejected',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  AppBar _appBar() => AppBar(
        title: const Text(
          'Admin Proposal Details',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      );

  void _openMap(
    BuildContext context,
    AdminPlanningViewModel viewModel,
    Proposal proposal,
    ProposalAssessment? assessment,
  ) {
    final nearbyStations = viewModel.nearbyStationsForMap(proposal);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminProposalLocationMapScreen(
          proposal: proposal,
          nearbyStations: nearbyStations,
          relatedGap: assessment?.relatedGap,
        ),
      ),
    );
  }

  Future<void> _confirmStatus(
    BuildContext context,
    AdminPlanningViewModel viewModel,
    Proposal proposal,
    String status,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          status == 'Approved' ? 'Approve Proposal?' : 'Reject Proposal?',
        ),
        content: Text(
          'You are ${status.toLowerCase()} “${proposal.city}”.\n\n'
          'This decision will change the proposal’s administrative status. The independent assessment score will not be rewritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          status == 'Approved'
              ? ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Approve'),
                )
              : TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE74C3C),
                  ),
                  child: const Text('Reject'),
                ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final updated = await viewModel.updateStatus(proposal, status);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated
              ? 'Proposal marked as $status.'
              : 'Unable to update proposal status.',
        ),
      ),
    );
  }

  String _gapRelationship(ProposalAssessment? assessment) {
    if (assessment == null) return 'Assessing';
    if (!assessment.gapAnalysisAvailable) return 'Analysis unavailable';
    if (assessment.relatedGap == null) return 'Outside identified gaps';
    return '${assessment.relatedGap!.name} '
        '(${assessment.distanceToGapKm!.toStringAsFixed(1)} km)';
  }
}

class _ProposalHeader extends StatelessWidget {
  const _ProposalHeader({required this.proposal});
  final Proposal proposal;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: green.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.ev_station, color: green, size: 30),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  proposal.city,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: planningTextColor,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  proposal.locationLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: planningMutedTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(child: StatusChip(proposal.status)),
        ],
      ),
    );
  }
}

class _AssessmentSummary extends StatelessWidget {
  const _AssessmentSummary({required this.assessment});
  final ProposalAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final color = assessment.outcome == ProposalAssessmentOutcome.recommended
        ? green
        : assessment.outcome ==
                ProposalAssessmentOutcome.furtherReviewRequired
            ? const Color(0xFFF39C12)
            : const Color(0xFFE74C3C);
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${assessment.score}',
              style: TextStyle(
                color: color,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  assessment.outcome.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Transparent rule-based score out of 100',
                  style: TextStyle(color: planningMutedTextColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentFactorCard extends StatelessWidget {
  const _AssessmentFactorCard({required this.factor});
  final ProposalAssessmentFactor factor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor.name,
                  style: const TextStyle(
                    color: planningTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                factor.available
                    ? '${factor.scoreAwarded}/${factor.maximumScore}'
                    : 'Unavailable',
                style: TextStyle(
                  color: factor.available ? green : planningMutedTextColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            factor.observedValue,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            factor.explanation,
            style: const TextStyle(
              color: planningMutedTextColor,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420 || MediaQuery.textScalerOf(context).scale(1) > 1.25) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: planningMutedTextColor)),
              const SizedBox(height: 5),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: Text(label,
                  style: const TextStyle(color: planningMutedTextColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DecisionButtons extends StatelessWidget {
  const _DecisionButtons({
    required this.updating,
    required this.onApprove,
    required this.onReject,
  });
  final bool updating;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final approve = ElevatedButton.icon(
          onPressed: updating ? null : onApprove,
          icon: updating
              ? const SizedBox.square(
                  dimension: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: const Text('Approve'),
        );
        final reject = OutlinedButton.icon(
          onPressed: updating ? null : onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFE74C3C),
            side: const BorderSide(color: Color(0xFFE74C3C)),
          ),
          icon: const Icon(Icons.cancel_outlined),
          label: const Text('Reject'),
        );
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [approve, const SizedBox(height: 10), reject],
          );
        }
        return Row(
          children: [
            Expanded(child: approve),
            const SizedBox(width: 12),
            Expanded(child: reject),
          ],
        );
      },
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Unavailable';
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
