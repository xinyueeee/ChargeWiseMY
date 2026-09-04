import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../planning/widgets/planning_widgets.dart';
import '../models/fault_report.dart';
import '../viewmodels/feedback_viewmodel.dart';
import '../widgets/feedback_widgets.dart';
import 'my_reports_screen.dart';
import 'new_report_screen.dart';
import 'report_details_screen.dart';
import 'report_map_screen.dart';

class FeedbackDashboardScreen extends StatelessWidget {
  const FeedbackDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          centerTitle: true,
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Infrastructure Feedback', style: planningAppBarTitleStyle),
              SizedBox(height: 2),
              Text(
                'Report issues and track their status',
                style: TextStyle(
                  fontSize: 12,
                  color: planningMutedTextColor,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        body: Consumer<FeedbackViewModel>(
          builder: (context, vm, __) {
            if (vm.loading) {
              return const PlanningLoadingState(
                message: 'Loading your reports…',
              );
            }

            final recent = List<FaultReport>.of(vm.myReports)
              ..sort(
                (a, b) => (b.createdAt ?? DateTime(0))
                    .compareTo(a.createdAt ?? DateTime(0)),
              );
            final topThree = recent.take(3).toList();
            final inProgress =
                vm.myReports.where((r) => r.status != 'Resolved').length;
            final resolved =
                vm.myReports.where((r) => r.status == 'Resolved').length;

            return SafeArea(
              child: RefreshIndicator(
                onRefresh: () => vm.load(silent: true),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: planningPagePadding,
                  children: [
                    if (vm.errorMessage != null) ...[
                      PlanningErrorState(
                        message: vm.errorMessage!,
                        onRetry: vm.load,
                      ),
                      const SizedBox(height: 16),
                    ],
                    FeedbackHeroBanner(
                      onReportIssue: () => _openNewReport(context),
                    ),
                    planningSectionGap,
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Report Overview',
                            style: TextStyle(
                              color: planningTextColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ReportOverviewStat(
                                value: '${vm.myReports.length}',
                                label: 'My Reports',
                                subtitle: 'View all your submissions',
                                icon: Icons.description_outlined,
                                color: blue,
                                onTap: () => _openMyReports(context, 'All'),
                              ),
                              ReportOverviewStat(
                                value: '$inProgress',
                                label: 'In Progress',
                                subtitle: 'Reports still being worked on',
                                icon: Icons.access_time_outlined,
                                color: orange,
                                onTap: () => _openMyReports(context, 'All'),
                              ),
                              ReportOverviewStat(
                                value: '$resolved',
                                label: 'Resolved',
                                subtitle: 'Issues have been resolved',
                                icon: Icons.check_circle_outline,
                                color: green,
                                onTap: () =>
                                    _openMyReports(context, 'Resolved'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    planningSectionGap,
                    const PlanningSectionTitle('Quick Actions'),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        QuickActionCard(
                          icon: Icons.camera_alt_outlined,
                          title: 'Report Issue',
                          subtitle: 'Submit a new fault report',
                          color: green,
                          onTap: () => _openNewReport(context),
                        ),
                        const SizedBox(width: 10),
                        QuickActionCard(
                          icon: Icons.map_outlined,
                          title: 'Nearby Issues',
                          subtitle: 'View reported issues near you',
                          color: blue,
                          onTap: () => _openNearbyIssues(context),
                        ),
                        const SizedBox(width: 10),
                        QuickActionCard(
                          icon: Icons.info_outline,
                          title: 'How It Works',
                          subtitle: 'Learn about our feedback process',
                          color: purple,
                          onTap: () => _showHowItWorks(context),
                        ),
                      ],
                    ),
                    planningSectionGap,
                    PlanningSectionTitle(
                      'My Recent Reports',
                      trailing: TextButton(
                        onPressed: () => _openMyReports(context, 'All'),
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
                    if (topThree.isEmpty)
                      PlanningEmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'No reports yet',
                        message: 'Submit your first fault report to help '
                            'keep charging stations reliable.',
                        action: ElevatedButton.icon(
                          onPressed: () => _openNewReport(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Report an Issue'),
                        ),
                      )
                    else
                      for (final report in topThree) ...[
                        ReportCard(
                          report: report,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  ReportDetailsScreen(report: report),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              ),
            );
          },
        ),
      );

  void _openNewReport(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const NewReportScreen()),
    );
  }

  void _openMyReports(BuildContext context, String initialTab) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MyReportsScreen(initialTab: initialTab),
      ),
    );
  }

  void _openNearbyIssues(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ReportMapScreen()),
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'How It Works',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: planningTextColor,
              ),
            ),
            SizedBox(height: 16),
            _HowItWorksStep(
              number: '1',
              title: 'Submit',
              description: 'Report a fault with its location, category, '
                  'and optional photos.',
            ),
            SizedBox(height: 14),
            _HowItWorksStep(
              number: '2',
              title: 'Verified',
              description: 'An administrator reviews your report and '
                  'confirms the issue.',
            ),
            SizedBox(height: 14),
            _HowItWorksStep(
              number: '3',
              title: 'Resolved',
              description: 'Once it\'s fixed, the report is marked '
                  'resolved and closed out.',
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number, title, description;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: green, shape: BoxShape.circle),
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: planningTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    color: planningMutedTextColor,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
