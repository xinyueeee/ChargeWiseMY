import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/planning_widgets.dart';
import '../viewmodels/admin_planning_viewmodel.dart';
import 'admin_proposal_list_screen.dart';

class AdminPlanningDashboardScreen extends StatelessWidget {
  const AdminPlanningDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Infrastructure Planning',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Consumer<AdminPlanningViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.loading) {
            return const PlanningLoadingState(message: 'Loading proposals…');
          }
          if (viewModel.loadingErrorMessage != null) {
            return PlanningErrorState(
              message: 'Unable to load proposals.',
              onRetry: viewModel.reload,
            );
          }
          return SafeArea(
            child: OrientationBuilder(
              builder: (context, orientation) {
                final size = MediaQuery.sizeOf(context);
                final useWideLayout = size.width >= 720 ||
                    (orientation == Orientation.landscape &&
                        size.width >= 560 &&
                        size.height <= 620);
                if (useWideLayout) {
                  return _buildWideDashboard(context, viewModel);
                }
                return ListView(
              padding: planningPagePadding,
              children: [
                const PlanningSectionTitle(
                  'Planning Operations',
                  subtitle:
                      'Review proposals and the supporting rule-based assessment evidence.',
                ),
                planningSectionGap,
                _buildReviewOverview(viewModel),
                const SizedBox(height: 12),
                _buildInfrastructureContext(viewModel),
                planningSectionGap,
                const PlanningSectionTitle(
                  'Quick actions',
                  subtitle: 'Open the proposal management workflow.',
                ),
                const SizedBox(height: 12),
                _buildAdminActions(context, viewModel),
                planningSectionGap,
                _AdminAssessmentNotice(),
              ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildWideDashboard(
    BuildContext context,
    AdminPlanningViewModel viewModel,
  ) => Column(
    children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: PlanningSectionTitle(
          'Planning Operations',
          subtitle: 'Proposal review and rule-based assessment evidence.',
        ),
      ),
      Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildReviewOverview(viewModel),
                    const SizedBox(height: 12),
                    _buildInfrastructureContext(viewModel),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1, color: Color(0xFFE6EAF0)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        color: planningTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildAdminActions(context, viewModel),
                    const SizedBox(height: 12),
                    _AdminAssessmentNotice(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildReviewOverview(AdminPlanningViewModel viewModel) =>
      _AdminReviewOverviewCard(
        pending: viewModel.pendingProposalCount,
        requiringReview: viewModel.requiringReviewCount,
        approved: viewModel.approvedProposalCount,
        recommended: viewModel.recommendedAssessmentCount,
        total: viewModel.totalProposalCount,
      );

  Widget _buildInfrastructureContext(AdminPlanningViewModel viewModel) =>
      _AdminInfrastructureContextCard(
        locations: viewModel.stations.length,
        chargers: viewModel.stations.fold(
          0,
          (sum, station) => sum + (station.chargerCount ?? 0),
        ),
        acChargers: viewModel.stations.fold(
          0,
          (sum, station) => sum + (station.acChargerCount ?? 0),
        ),
        dcChargers: viewModel.stations.fold(
          0,
          (sum, station) => sum + (station.dcChargerCount ?? 0),
        ),
      );

  Widget _buildAdminActions(
    BuildContext context,
    AdminPlanningViewModel viewModel,
  ) => AppCard(
    padding: const EdgeInsets.all(12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final pendingButton = ElevatedButton.icon(
          onPressed: () {
            viewModel.showPendingProposals();
            _openProposalList(context);
          },
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: const Text('Review Pending'),
        );
        final allButton = OutlinedButton.icon(
          onPressed: () {
            viewModel.showAllProposals();
            _openProposalList(context);
          },
          icon: const Icon(Icons.view_list_outlined, size: 18),
          label: const Text('View All'),
        );
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [pendingButton, const SizedBox(height: 8), allButton],
          );
        }
        return Row(
          children: [
            Expanded(child: pendingButton),
            const SizedBox(width: 8),
            Expanded(child: allButton),
          ],
        );
      },
    ),
  );

  void _openProposalList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminProposalListScreen(),
      ),
    );
  }
}

class _AdminReviewOverviewCard extends StatelessWidget {
  const _AdminReviewOverviewCard({
    required this.pending,
    required this.requiringReview,
    required this.approved,
    required this.recommended,
    required this.total,
  });

  final int pending;
  final int requiringReview;
  final int approved;
  final int recommended;
  final int total;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_outlined, color: planningTextColor),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Proposal Review',
                    style: TextStyle(
                      color: planningTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$total total',
                  style: const TextStyle(
                    color: planningMutedTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminMetric(
                    width: constraints.maxWidth >= 620
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth >= 380
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth,
                    icon: Icons.schedule_outlined,
                    label: 'Pending proposals',
                    value: pending,
                    color: const Color(0xFFF39C12),
                  ),
                  _AdminMetric(
                    width: constraints.maxWidth >= 620
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth >= 380
                        ? (constraints.maxWidth - 10) / 2
                        : constraints.maxWidth,
                    icon: Icons.fact_check_outlined,
                    label: 'Requiring review',
                    value: requiringReview,
                    color: const Color(0xFF8E44AD),
                  ),
                  _AdminMetric(
                    width: constraints.maxWidth >= 620
                        ? (constraints.maxWidth - 20) / 3
                        : constraints.maxWidth,
                    icon: Icons.check_circle_outline,
                    label: 'Approved proposals',
                    value: approved,
                    color: green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '$recommended recommended assessments · '
              '$requiringReview further-review assessments',
              style: const TextStyle(
                color: planningMutedTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _AdminMetric extends StatelessWidget {
  const _AdminMetric({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final double width;
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAssessmentNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: green, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Assessments provide planning evidence; administrative status remains an administrator decision.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: planningMutedTextColor,
                      height: 1.3,
                    ),
              ),
            ),
          ],
        ),
      );
}

class _AdminInfrastructureContextCard extends StatelessWidget {
  const _AdminInfrastructureContextCard({
    required this.locations,
    required this.chargers,
    required this.acChargers,
    required this.dcChargers,
  });

  final int locations;
  final int chargers;
  final int acChargers;
  final int dcChargers;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.ev_station_outlined, color: blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Infrastructure Context',
                    style: TextStyle(
                      color: planningTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$locations charging locations · $chargers installed chargers',
                    style: const TextStyle(color: planningMutedTextColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'AC $acChargers · DC $dcChargers',
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
