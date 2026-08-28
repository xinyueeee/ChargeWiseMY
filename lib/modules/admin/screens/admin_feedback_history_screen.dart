import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/models/fault_report.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'admin_report_details_screen.dart';

/// "History" — every report regardless of status, newest first, browsable
/// with search and a status filter. No verify/resolve actions here; it's a
/// read-only audit view (act on a report from `AdminReportDetailsScreen`).
class AdminFeedbackHistoryScreen extends StatefulWidget {
  const AdminFeedbackHistoryScreen({super.key});

  @override
  State<AdminFeedbackHistoryScreen> createState() =>
      _AdminFeedbackHistoryScreenState();
}

class _AdminFeedbackHistoryScreenState
    extends State<AdminFeedbackHistoryScreen> with SingleTickerProviderStateMixin {
  static const _tabs = ['All', 'Submitted', 'Verified', 'In Progress', 'Resolved'];
  static const _pageSize = 8;

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() => _page = 0);
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<FaultReport> _applyFilters(List<FaultReport> source) {
    final tabLabel = _tabs[_tabController.index];
    final query = _query.trim().toLowerCase();
    return source.where((report) {
      final matchesTab = tabLabel == 'All' || report.status == tabLabel;
      final matchesQuery = query.isEmpty ||
          report.category.toLowerCase().contains(query) ||
          report.locationLabel.toLowerCase().contains(query) ||
          (report.reporterName ?? '').toLowerCase().contains(query);
      return matchesTab && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          titleSpacing: 0,
          title: const Text(
            'History',
            style: TextStyle(
              color: planningTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: planningTextColor,
          elevation: 0,
          actions: const [
            Padding(padding: EdgeInsets.only(right: 16), child: AdminBadge()),
          ],
        ),
        body: Consumer<AdminFeedbackViewModel>(
          builder: (context, vm, __) {
            if (vm.loading) {
              return const PlanningLoadingState(message: 'Loading history…');
            }
            final all = vm.recentReports;
            final filtered = _applyFilters(all);
            final totalPages =
                filtered.isEmpty ? 1 : (filtered.length / _pageSize).ceil();
            final page = _page.clamp(0, totalPages - 1);
            final pageItems =
                filtered.skip(page * _pageSize).take(_pageSize).toList();

            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: planningPagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search by issue, location, or reporter',
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: green,
                          unselectedLabelColor: planningMutedTextColor,
                          indicatorColor: green,
                          tabAlignment: TabAlignment.start,
                          tabs: [for (final tab in _tabs) Tab(text: tab)],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: pageItems.isEmpty
                        ? const Center(
                            child: PlanningEmptyState(
                              icon: Icons.history,
                              title: 'Nothing here',
                              message: 'No reports match this filter.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final report = pageItems[index];
                              return AdminReportListTile(
                                title: report.category,
                                location: report.locationLabel,
                                dateLabel: submittedOnLabel(report.createdAt),
                                subtitle: 'Reported by: '
                                    '${report.reporterName ?? 'Unknown driver'}',
                                photoUrl: report.photoUrls.isEmpty
                                    ? null
                                    : report.photoUrls.first,
                                chip: ReportStatusChip(report.status),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        AdminReportDetailsScreen(report: report),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: AdminPagination(
                      page: page,
                      pageCount: totalPages,
                      onPageChanged: (next) => setState(() => _page = next),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}
