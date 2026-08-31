import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/proposal.dart';
import '../../widgets/planning_widgets.dart';
import '../../widgets/proposal_photo_widgets.dart';
import '../models/proposal_assessment.dart';
import '../services/admin_proposal_ai_review_service.dart';
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
        final planned = proposal.latitude == null || proposal.longitude == null
            ? null
            : viewModel.plannedContextAt(
                proposal.latitude!,
                proposal.longitude!,
              );
        return Scaffold(
          appBar: _appBar(),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final landscape =
                    MediaQuery.orientationOf(context) == Orientation.landscape;
                final compactLandscape =
                    landscape && constraints.maxHeight < 480;
                final wide = constraints.maxWidth >= 900 ||
                    (landscape && constraints.maxWidth >= 680);
                final primary = _primaryContent(
                  context,
                  viewModel,
                  proposal,
                  assessment,
                  planned,
                  photoHeight: compactLandscape
                      ? 140
                      : wide
                          ? 220
                          : 180,
                );
                final decision = _DecisionPanel(
                  proposal: proposal,
                  assessment: assessment,
                  updating: viewModel.isUpdating(proposal),
                  errorMessage: viewModel.statusErrorMessage,
                  onStatus: (status) =>
                      _confirmStatus(context, viewModel, proposal, status),
                );
                final review = _reviewContent(
                  context,
                  viewModel,
                  proposal,
                  assessment,
                  planned,
                );
                if (!wide) {
                  return ListView(
                    padding: planningPagePadding,
                    children: [
                      ...primary.take(3),
                      const SizedBox(height: 12),
                      decision,
                      ...primary.skip(3),
                      planningSectionGap,
                      ...review,
                    ],
                  );
                }
                return Padding(
                  padding: planningPagePadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 6,
                        child: ListView(children: primary),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        flex: 4,
                        child: ListView(children: [decision, ...review]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _primaryContent(
    BuildContext context,
    AdminPlanningViewModel viewModel,
    Proposal proposal,
    ProposalAssessment? assessment,
    PlannedInfrastructureContext? planned, {
    required double photoHeight,
  }) =>
      [
        _ProposalHeader(proposal: proposal),
        const SizedBox(height: 12),
        _ReviewMetrics(proposal: proposal, assessment: assessment),
        planningSectionGap,
        _sectionTitle(Icons.photo_camera_outlined, 'Site Photo'),
        const SizedBox(height: 8),
        _SitePhotoPanel(proposal: proposal, height: photoHeight),
        planningSectionGap,
        _sectionTitle(Icons.description_outlined, 'Proposal Overview'),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Description',
                style: TextStyle(
                  color: planningMutedTextColor,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                proposal.description.trim().isEmpty
                    ? 'Not provided'
                    : proposal.description,
                style: const TextStyle(height: 1.35),
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.ev_station_outlined,
                label: 'Charger type',
                value: proposal.charger,
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.trending_up,
                label: 'Expected usage',
                value: proposal.demand,
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.calendar_today_outlined,
                label: 'Submitted',
                value: _formatDate(proposal.createdAt),
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.groups_outlined,
                label: 'Community response',
                value: '${proposal.supportCount} support · '
                    '${proposal.opposeCount} not support',
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.flag_outlined,
                label: 'Current status',
                value: proposal.status,
              ),
              if (proposal.isApproved) ...[
                const Divider(height: 18),
                const _AdminLifecycleNotice(),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: proposal.latitude == null ||
                          proposal.longitude == null
                      ? null
                      : () =>
                          _openMap(context, viewModel, proposal, assessment),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View Proposed Location'),
                ),
              ),
            ],
          ),
        ),
        planningSectionGap,
        _sectionTitle(Icons.ev_station_outlined, 'Infrastructure Context'),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            children: [
              _InformationRow('Nearest Existing location',
                  '${proposal.distance.toStringAsFixed(1)} km'),
              const Divider(height: 18),
              _InformationRow(
                  'Nearby Existing locations',
                  assessment?.nearbyStationLocationCount?.toString() ??
                      'Unavailable'),
              const Divider(height: 18),
              _InformationRow(
                'Nearest MEVnet Proposed',
                planned?.nearestDistanceKm == null
                    ? 'Unavailable'
                    : '${planned!.nearestDistanceKm!.toStringAsFixed(1)} km',
              ),
              const Divider(height: 18),
              _InformationRow('Proposed nearby',
                  '${planned?.nearbyLocationCount ?? 0} locations · ${planned?.nearbyProposedChargerCount ?? 0} EVCB'),
            ],
          ),
        ),
      ];

  List<Widget> _reviewContent(
    BuildContext context,
    AdminPlanningViewModel viewModel,
    Proposal proposal,
    ProposalAssessment? assessment,
    PlannedInfrastructureContext? planned,
  ) =>
      [
        const SizedBox(height: 12),
        if (assessment != null) ...[
          _AdminAiReviewCard(
            key: ValueKey(
              _adminAiInputFingerprint(proposal, assessment, planned),
            ),
            proposal: proposal,
            assessment: assessment,
            plannedInfrastructure: planned,
          ),
          const SizedBox(height: 12),
          AppCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(Icons.rule_folder_outlined, color: green),
              title: const Text('Assessment Breakdown',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${assessment.factors.length} scored factors'),
              children: [
                for (final factor in assessment.factors)
                  _CompactFactorRow(factor: factor),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          const PlanningLoadingState(message: 'Assessing proposal…'),
        ],
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            leading: const Icon(Icons.tune_outlined, color: green),
            title: const Text('Technical Information',
                style: TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [
              _AlignedInformationRow(
                icon: Icons.key_outlined,
                label: 'Proposal ID',
                value: proposal.id,
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.person_outline,
                label: 'Creator',
                value: proposal.createdBy,
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.map_outlined,
                label: 'State',
                value: proposal.state ?? 'Unavailable',
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.location_city_outlined,
                label: 'Settlement',
                value: proposal.nearestTown ?? 'Unavailable',
              ),
              const Divider(height: 18),
              _AlignedInformationRow(
                icon: Icons.radar_outlined,
                label: 'Coverage relationship',
                value: _gapRelationship(assessment),
              ),
              if (proposal.latitude != null && proposal.longitude != null) ...[
                const Divider(height: 18),
                _AlignedInformationRow(
                  icon: Icons.my_location_outlined,
                  label: 'Coordinates',
                  value: '${proposal.latitude!.toStringAsFixed(6)}, '
                      '${proposal.longitude!.toStringAsFixed(6)}',
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: assessment == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminPlanningAssistantScreen(
                        proposalId: proposal.id,
                      ),
                    ),
                  ),
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Open Evidence Assistant'),
        ),
        const SizedBox(height: 24),
      ];

  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 19, color: green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: planningTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      );

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
    final isReview = status == Proposal.statusUnderReview;
    final isApprove = status == Proposal.statusApproved;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isReview
            ? 'Start Administrative Review?'
            : isApprove
                ? 'Approve Proposal?'
                : 'Reject Proposal?'),
        content: Text(
          isReview
              ? 'Move “${proposal.city}” to Under Review? The Driver-facing status will update immediately.'
              : 'You are marking “${proposal.city}” as $status.\n\nThe independent assessment score will not be rewritten.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          isApprove || isReview
              ? ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(isReview ? 'Start Review' : 'Approve'),
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
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 16, color: planningMutedTextColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [proposal.nearestTown, proposal.state]
                            .whereType<String>()
                            .where((item) => item.trim().isNotEmpty)
                            .join(', '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: planningMutedTextColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Submitted ${_formatDate(proposal.createdAt)}',
                    style: const TextStyle(
                        color: planningMutedTextColor, fontSize: 12)),
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

class _ReviewMetrics extends StatelessWidget {
  const _ReviewMetrics({required this.proposal, required this.assessment});

  final Proposal proposal;
  final ProposalAssessment? assessment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 620
              ? (constraints.maxWidth - 20) / 3
              : constraints.maxWidth;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ReviewMetric(
                width: width,
                icon: Icons.fact_check_outlined,
                label: 'Assessment',
                value: assessment?.outcome.label ?? 'Assessing',
                detail: assessment == null
                    ? 'Please wait'
                    : '${assessment!.score} / 100',
              ),
              _ReviewMetric(
                width: width,
                icon: Icons.trending_up,
                label: 'Expected Usage',
                value: proposal.demand,
                detail: proposal.charger,
              ),
              _ReviewMetric(
                width: width,
                icon: Icons.groups_outlined,
                label: 'Community',
                value: '${proposal.supportCount} Support',
                detail: '${proposal.opposeCount} Not Support',
              ),
            ],
          );
        },
      );
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(
            children: [
              Icon(icon, color: green, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: planningMutedTextColor, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: planningTextColor,
                            fontWeight: FontWeight.w800)),
                    Text(detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: planningMutedTextColor, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _SitePhotoPanel extends StatelessWidget {
  const _SitePhotoPanel({required this.proposal, required this.height});

  final Proposal proposal;
  final double height;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(10),
        child: proposal.sitePhotoPath == null
            ? const Row(
                children: [
                  Icon(Icons.image_not_supported_outlined,
                      color: planningMutedTextColor, size: 20),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text('No site photo provided.',
                        style: TextStyle(color: planningMutedTextColor)),
                  ),
                ],
              )
            : ProposalSitePhoto(
                storagePath: proposal.sitePhotoPath!,
                height: height,
              ),
      );
}

class _DecisionPanel extends StatelessWidget {
  const _DecisionPanel({
    required this.proposal,
    required this.assessment,
    required this.updating,
    required this.errorMessage,
    required this.onStatus,
  });

  final Proposal proposal;
  final ProposalAssessment? assessment;
  final bool updating;
  final String? errorMessage;
  final ValueChanged<String> onStatus;

  @override
  Widget build(BuildContext context) {
    final pending = proposal.status == Proposal.statusPending;
    final underReview = proposal.status == Proposal.statusUnderReview;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_outlined,
                  color: green, size: 21),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Administrative Decision',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              StatusChip(proposal.status),
            ],
          ),
          const SizedBox(height: 12),
          _InformationRow(
              'Assessment', assessment?.outcome.label ?? 'Assessing'),
          const Divider(height: 18),
          _InformationRow('Score',
              assessment == null ? 'Assessing' : '${assessment!.score}/100'),
          const SizedBox(height: 10),
          const Text(
            'The rule-based assessment informs review but does not make the administrative decision.',
            style: TextStyle(color: planningMutedTextColor, height: 1.35),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 10),
            Text(errorMessage!,
                style: const TextStyle(color: Color(0xFFE74C3C))),
          ],
          const SizedBox(height: 14),
          if (pending)
            ElevatedButton.icon(
              onPressed:
                  updating ? null : () => onStatus(Proposal.statusUnderReview),
              icon: updating
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline),
              label: const Text('Start Review'),
            )
          else if (underReview)
            _DecisionButtons(
              updating: updating,
              onApprove: () => onStatus(Proposal.statusApproved),
              onReject: () => onStatus(Proposal.statusRejected),
            )
          else
            Row(
              children: [
                Icon(
                  proposal.status == Proposal.statusApproved
                      ? Icons.verified_outlined
                      : Icons.block_outlined,
                  color: proposal.status == Proposal.statusApproved
                      ? green
                      : const Color(0xFFE74C3C),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'This proposal is ${proposal.status}. No further decision action is active.',
                    style: const TextStyle(color: planningMutedTextColor),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CompactFactorRow extends StatelessWidget {
  const _CompactFactorRow({required this.factor});
  final ProposalAssessmentFactor factor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                factor.available
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 18,
                color: factor.available ? green : planningMutedTextColor),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(factor.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(factor.observedValue,
                      style: const TextStyle(
                          color: planningMutedTextColor, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(factor.explanation,
                      style: const TextStyle(
                          color: planningMutedTextColor, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              factor.available
                  ? '${factor.scoreAwarded}/${factor.maximumScore}'
                  : 'N/A',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
}

class _AdminAiReviewCard extends StatefulWidget {
  const _AdminAiReviewCard({
    super.key,
    required this.proposal,
    required this.assessment,
    required this.plannedInfrastructure,
  });

  final Proposal proposal;
  final ProposalAssessment assessment;
  final PlannedInfrastructureContext? plannedInfrastructure;

  @override
  State<_AdminAiReviewCard> createState() => _AdminAiReviewCardState();
}

String _adminAiInputFingerprint(
  Proposal proposal,
  ProposalAssessment assessment,
  PlannedInfrastructureContext? planned,
) =>
    <Object?>[
      proposal.id,
      proposal.city,
      proposal.state,
      proposal.nearestTown,
      proposal.locationLabel,
      proposal.demand,
      proposal.supportCount,
      proposal.opposeCount,
      proposal.distance,
      proposal.status,
      assessment.score,
      assessment.outcome,
      assessment.nearbyStationLocationCount,
      assessment.gapAnalysisAvailable,
      assessment.relatedGap?.id,
      assessment.distanceToGapKm,
      assessment.nearbyProposalDistanceKm,
      for (final factor in assessment.factors) ...[
        factor.name,
        factor.observedValue,
        factor.scoreAwarded,
        factor.maximumScore,
        factor.available,
        factor.explanation,
      ],
      planned?.nearestDistanceKm,
      planned?.nearbyLocationCount,
      planned?.nearbyProposedChargerCount,
      planned?.radiusKm,
    ].join('|');

class _AdminAiReviewCardState extends State<_AdminAiReviewCard> {
  AdminProposalAiReview? _review;
  AdminAiReviewFailureReason? _failure;
  bool _loading = false;

  Future<void> _generate() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failure = null;
      _review = null;
    });
    try {
      final review = await const AdminProposalAiReviewService().generate(
        proposal: widget.proposal,
        assessment: widget.assessment,
        plannedInfrastructure: widget.plannedInfrastructure,
      );
      if (!mounted) return;
      setState(() => _review = review);
    } on AdminAiReviewException catch (error) {
      if (!mounted) return;
      setState(() => _failure = error.reason);
    } on FormatException {
      if (!mounted) return;
      setState(() => _failure = AdminAiReviewFailureReason.unavailable);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final review = _review;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: green, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI Proposal Review',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Optional interpretation of the verified proposal and rule-based assessment. It does not make the administrative decision.',
            style: TextStyle(color: planningMutedTextColor, height: 1.35),
          ),
          if (_loading) ...[
            const SizedBox(height: 14),
            const Row(
              children: [
                SizedBox.square(
                  dimension: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(child: Text('Generating grounded proposal review…')),
              ],
            ),
          ] else if (review != null) ...[
            const SizedBox(height: 14),
            Text(review.summary),
            const SizedBox(height: 12),
            const Text('Strengths',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final item in review.strengths) Text('• $item'),
            const SizedBox(height: 10),
            const Text(
              'Concerns / verification required',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final item in review.concerns) Text('• $item'),
            const SizedBox(height: 10),
            const Text(
              'Suggested Admin follow-up',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(review.suggestedFollowUp),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate Review'),
            ),
          ] else if (_failure != null) ...[
            const SizedBox(height: 12),
            Text(
              _failureMessage(_failure!),
              style: const TextStyle(color: planningMutedTextColor),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try Again'),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Generate AI Review'),
            ),
          ],
        ],
      ),
    );
  }

  String _failureMessage(AdminAiReviewFailureReason reason) => switch (reason) {
        AdminAiReviewFailureReason.rateLimited =>
          'AI service is temporarily busy. Please try again shortly.',
        AdminAiReviewFailureReason.timeout =>
          'AI review took too long. Please try again.',
        AdminAiReviewFailureReason.authentication =>
          'Sign in again before generating an Admin AI review.',
        AdminAiReviewFailureReason.forbidden =>
          'An authenticated administrator profile is required for AI review.',
        AdminAiReviewFailureReason.unavailable =>
          "AI review couldn't be generated right now.",
      };
}

class _AdminLifecycleNotice extends StatelessWidget {
  const _AdminLifecycleNotice();

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: green, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Approved for planning consideration. This remains a community proposal and is not Existing MEVnet infrastructure.',
              style: TextStyle(
                color: planningMutedTextColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      );
}

class _AlignedInformationRow extends StatelessWidget {
  const _AlignedInformationRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Icon(icon, size: 18, color: green),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.2;
                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: SelectableText(
                        value,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.25) {
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
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
