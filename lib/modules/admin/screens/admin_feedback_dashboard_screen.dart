import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/models/fault_report.dart';
import '../../feedback/screens/new_report_screen.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../planning/admin/screens/admin_proposal_list_screen.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'admin_feedback_history_screen.dart';
import 'admin_maintenance_list_screen.dart';
import 'admin_report_details_screen.dart';
import 'admin_verify_reports_screen.dart';

class AdminFeedbackDashboardScreen extends StatelessWidget {
  const AdminFeedbackDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AdminFeedbackViewModel>(
        builder: (context, vm, __) {
          if (vm.loading) {
            return const PlanningLoadingState(
              message: 'Loading feedback overview…',
            );
          }
          if (vm.errorMessage != null) {
            return Padding(
              padding: planningPagePadding,
              child: PlanningErrorState(
                message: vm.errorMessage!,
                onRetry: vm.load,
              ),
            );
          }

          final recent = vm.recentReports.take(5).toList();
          return RefreshIndicator(
            onRefresh: vm.load,
            child: ListView(
              padding: planningPagePadding,
              children: [
                const PlanningSectionTitle(
                  'Infrastructure Feedback',
                  subtitle: 'Review, verify, and track driver-reported issues.',
                ),
                planningSectionGap,
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 10.0;
                    final columns = constraints.maxWidth >= 420 ? 4 : 2;

                    final tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.assignment_late_outlined,
                            value: '${vm.submittedCount}',
                            label: 'New Reports',
                            color: red,
                            onTap: () => _openVerifyReports(context),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.autorenew,
                            value: '${vm.inProgressCount}',
                            label: 'In Progress',
                            color: blue,
                            onTap: () =>
                                _openHistory(context, initialTabIndex: 3),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.check_circle_outline,
                            value: '${vm.resolvedCount}',
                            label: 'Resolved',
                            color: green,
                            onTap: () =>
                                _openHistory(context, initialTabIndex: 4),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.build_outlined,
                            value: '${vm.openMaintenanceCount}',
                            label: 'Maintenance Ongoing',
                            color: purple,
                            onTap: () => _openMaintenance(context),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                planningSectionGap,
                PlanningSectionTitle(
                  'Recent Fault Reports',
                  trailing: TextButton(
                    onPressed: () => _openHistory(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: TextStyle(
                            color: green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: green, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (recent.isEmpty)
                  const PlanningEmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No reports yet',
                    message: 'Driver-submitted fault reports will appear here.',
                  )
                else
                  for (final report in recent) ...[
                    AdminReportListTile(
                      title: report.category,
                      location: report.locationLabel,
                      dateLabel: formatRelativeTime(report.createdAt),
                      chip: ReportStatusChip(report.status),
                      photoUrl: report.photoUrls.isEmpty
                          ? null
                          : report.photoUrls.first,
                      onTap: () => _openDetails(context, report),
                    ),
                    const SizedBox(height: 10),
                  ],
                planningSectionGap,
                const PlanningSectionTitle('Quick Actions'),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QuickActionCard(
                      icon: Icons.post_add_outlined,
                      title: 'New Fault Report',
                      subtitle: 'Create a new fault report',
                      color: green,
                      onTap: () => _openNewReport(context),
                    ),
                    const SizedBox(width: 10),
                    QuickActionCard(
                      icon: Icons.search,
                      title: 'Verify Reports',
                      subtitle: 'Review and verify reports',
                      color: purple,
                      onTap: () => _openVerifyReports(context),
                    ),
                    const SizedBox(width: 10),
                    QuickActionCard(
                      icon: Icons.how_to_vote_outlined,
                      title: 'Community Votes',
                      subtitle: 'View and manage community votes',
                      color: orange,
                      onTap: () => _openCommunityVotes(context),
                    ),
                    const SizedBox(width: 10),
                    QuickActionCard(
                      icon: Icons.history,
                      title: 'History',
                      subtitle: 'View report and action history',
                      color: blue,
                      onTap: () => _openHistory(context),
                    ),
                  ],
                ),
                planningSectionGap,
                PlanningSectionTitle(
                  'Reports by Status',
                  trailing: TextButton(
                    onPressed: () => _openHistory(context),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View Details',
                          style: TextStyle(
                            color: green,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Icon(Icons.chevron_right, color: green, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: const EdgeInsets.all(16),
                  child: AdminDonutChart(
                    segments: [
                      DonutSegment(
                        label: 'Submitted',
                        value: vm.submittedCount,
                        color: red,
                      ),
                      DonutSegment(
                        label: 'Verified',
                        value: vm.verifiedCount,
                        color: orange,
                      ),
                      DonutSegment(
                        label: 'In Progress',
                        value: vm.inProgressCount,
                        color: blue,
                      ),
                      DonutSegment(
                        label: 'Resolved',
                        value: vm.resolvedCount,
                        color: green,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

  void _openDetails(BuildContext context, FaultReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminReportDetailsScreen(report: report),
      ),
    );
  }

  void _openNewReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NewReportScreen()),
    );
  }

  void _openVerifyReports(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AdminVerifyReportsScreen()),
    );
  }

  void _openMaintenance(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminMaintenanceListScreen(),
      ),
    );
  }

  void _openHistory(BuildContext context, {int initialTabIndex = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            AdminFeedbackHistoryScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  void _openCommunityVotes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AdminProposalListScreen()),
    );
  }
}
