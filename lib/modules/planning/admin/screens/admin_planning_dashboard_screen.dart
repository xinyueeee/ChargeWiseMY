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
            child: ListView(
              padding: planningPagePadding,
              children: [
                const PlanningSectionTitle(
                  'Proposal review overview',
                  subtitle:
                      'Review submitted charging-station proposals and independent rule-based assessments.',
                ),
                planningSectionGap,
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 720 ? 3 : 2;
                    final width = (constraints.maxWidth -
                            ((columns - 1) * 12)) /
                        columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SummaryCard(
                          width: width,
                          icon: Icons.assignment_outlined,
                          label: 'Total proposals',
                          value: viewModel.totalProposalCount,
                          color: const Color(0xFF3767E8),
                        ),
                        _SummaryCard(
                          width: width,
                          icon: Icons.schedule_outlined,
                          label: 'Pending',
                          value: viewModel.pendingProposalCount,
                          color: const Color(0xFFF39C12),
                        ),
                        _SummaryCard(
                          width: width,
                          icon: Icons.check_circle_outline,
                          label: 'Approved',
                          value: viewModel.approvedProposalCount,
                          color: green,
                        ),
                        _SummaryCard(
                          width: width,
                          icon: Icons.cancel_outlined,
                          label: 'Rejected',
                          value: viewModel.rejectedProposalCount,
                          color: const Color(0xFFE74C3C),
                        ),
                        _SummaryCard(
                          width: width,
                          icon: Icons.fact_check_outlined,
                          label: 'Requiring review',
                          value: viewModel.requiringReviewCount,
                          color: const Color(0xFF8E44AD),
                        ),
                      ],
                    );
                  },
                ),
                planningSectionGap,
                const PlanningSectionTitle(
                  'Quick actions',
                  subtitle: 'Open the proposal management workflow.',
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final pendingButton = ElevatedButton.icon(
                        onPressed: () {
                          viewModel.showPendingProposals();
                          _openProposalList(context);
                        },
                        icon: const Icon(Icons.rate_review_outlined),
                        label: const Text('Review Pending Proposals'),
                      );
                      final allButton = OutlinedButton.icon(
                        onPressed: () {
                          viewModel.showAllProposals();
                          _openProposalList(context);
                        },
                        icon: const Icon(Icons.view_list_outlined),
                        label: const Text('View All Proposals'),
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pendingButton,
                            const SizedBox(height: 10),
                            allButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: pendingButton),
                          const SizedBox(width: 12),
                          Expanded(child: allButton),
                        ],
                      );
                    },
                  ),
                ),
                planningSectionGap,
                AppCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'System assessments provide transparent planning evidence. Administrative status remains a separate decision made by an administrator.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: planningMutedTextColor,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openProposalList(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminProposalListScreen(),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(
              '$value',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: planningMutedTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
