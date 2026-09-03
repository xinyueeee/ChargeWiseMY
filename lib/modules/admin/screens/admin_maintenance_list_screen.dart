import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/models/fault_report.dart';
import '../../feedback/widgets/feedback_widgets.dart'
    show formatReportDate, orange, red;
import '../../planning/widgets/planning_widgets.dart';
import '../models/maintenance_record.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'new_maintenance_record_screen.dart';

class AdminMaintenanceListScreen extends StatefulWidget {
  const AdminMaintenanceListScreen({super.key});

  @override
  State<AdminMaintenanceListScreen> createState() =>
      _AdminMaintenanceListScreenState();
}

class _AdminMaintenanceListScreenState extends State<AdminMaintenanceListScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['All', 'On Site', 'Scheduled', 'Delayed'];
  static const _pageSize = 6;

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

  List<MaintenanceRecord> _applyFilters(
    List<MaintenanceRecord> source,
    AdminFeedbackViewModel vm,
  ) {
    final tabLabel = _tabs[_tabController.index];
    final query = _query.trim().toLowerCase();
    return source.where((record) {
      final matchesTab = tabLabel == 'All' || record.status == tabLabel;
      if (query.isEmpty) return matchesTab;
      final report = vm.reportById(record.reportId);
      final title = report?.category ?? record.summary;
      final location = report?.locationLabel ?? record.stationId ?? '';
      final matchesQuery = title.toLowerCase().contains(query) ||
          location.toLowerCase().contains(query);
      return matchesTab && matchesQuery;
    }).toList()
      ..sort((a, b) => b.maintenanceDate.compareTo(a.maintenanceDate));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          titleSpacing: 0,
          title: const Text(
            'Maintenance Ongoing',
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
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: AdminBadge(),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openNewRecord,
          backgroundColor: green,
          icon: const Icon(Icons.add),
          label: const Text('Log Maintenance'),
        ),
        body: Consumer<AdminFeedbackViewModel>(
          builder: (context, vm, __) {
            if (vm.loading) {
              return const PlanningLoadingState(
                message: 'Loading maintenance tasks…',
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
            final ongoing =
                vm.maintenanceRecords.where((r) => r.isOngoing).toList();
            final onSite = ongoing.where((r) => r.status == 'On Site').length;
            final scheduled =
                ongoing.where((r) => r.status == 'Scheduled').length;
            final delayed = ongoing.where((r) => r.status == 'Delayed').length;
            final others = ongoing.where((r) => r.status == 'Other').length;
            final filtered = _applyFilters(ongoing, vm);
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
                        const Text(
                          'Track and manage ongoing maintenance tasks',
                          style: TextStyle(color: planningMutedTextColor),
                        ),
                        const SizedBox(height: 16),
                        AppCard(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: green.withValues(alpha: .12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.build_outlined,
                                    color: green),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${ongoing.length}',
                                      style: const TextStyle(
                                        color: green,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Text(
                                      'Maintenance Ongoing',
                                      style: TextStyle(
                                        color: planningTextColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Active maintenance tasks requiring attention',
                                      style: TextStyle(
                                        color: planningMutedTextColor,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _legendDot('On Site', onSite, green),
                                  _legendDot('Scheduled', scheduled, orange),
                                  _legendDot('Delayed', delayed, red),
                                  _legendDot(
                                      'Others', others, planningMutedTextColor),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search by location or issue',
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
                          tabs: [
                            Tab(text: 'All (${ongoing.length})'),
                            Tab(text: 'On Site ($onSite)'),
                            Tab(text: 'Scheduled ($scheduled)'),
                            Tab(text: 'Delayed ($delayed)'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: pageItems.isEmpty
                        ? const Center(
                            child: PlanningEmptyState(
                              icon: Icons.build_outlined,
                              title: 'Nothing here',
                              message:
                                  'No maintenance tasks match this filter.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final record = pageItems[index];
                              final report = vm.reportById(record.reportId);
                              final color = record.status == 'Delayed'
                                  ? red
                                  : record.status == 'Scheduled'
                                      ? orange
                                      : green;
                              return AdminMaintenanceListTile(
                                title: report?.category ?? record.summary,
                                location: report?.locationLabel ??
                                    record.stationId ??
                                    'General maintenance',
                                reportedOnLabel: 'Reported on '
                                    '${formatReportDate(report?.createdAt ?? record.createdAt)}',
                                statusChip: _StatusPill(
                                  label: record.status,
                                  color: record.status == 'On Site'
                                      ? green
                                      : record.status == 'Delayed'
                                          ? red
                                          : record.status == 'Scheduled'
                                              ? orange
                                              : planningMutedTextColor,
                                ),
                                statusColor: color,
                                photoUrl: report?.photoUrls.isEmpty ?? true
                                    ? null
                                    : report!.photoUrls.first,
                                technicianName: record.technicianName,
                                etaLabel: record.etaLabel,
                                delayed: record.status == 'Delayed',
                                onTap: () => _openEditRecord(context, record),
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

  Widget _legendDot(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              '$label  $count',
              style:
                  const TextStyle(fontSize: 11, color: planningMutedTextColor),
            ),
          ],
        ),
      );

  Future<void> _openNewRecord() async {
    final vm = context.read<AdminFeedbackViewModel>();
    final candidates = vm.reports
        .where((r) => r.status == 'Verified' || r.status == 'In Progress')
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));

    final target = await showModalBottomSheet<_MaintenanceTarget>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LinkReportSheet(candidates: candidates),
    );
    if (target == null || !mounted) return;

    final report = target.report;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewMaintenanceRecordScreen(
          reportId: report?.id,
          stationId: report?.stationId,
          reportSummary: report == null
              ? null
              : '${report.category} · ${report.locationLabel}',
        ),
      ),
    );
  }

  void _openEditRecord(BuildContext context, MaintenanceRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewMaintenanceRecordScreen(record: record),
      ),
    );
  }
}

/// Result of the "which report is this for?" sheet. [report] is null when the
/// admin chose routine maintenance not tied to any report.
class _MaintenanceTarget {
  const _MaintenanceTarget(this.report);
  final FaultReport? report;
}

class _LinkReportSheet extends StatelessWidget {
  const _LinkReportSheet({required this.candidates});

  final List<FaultReport> candidates;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E4EA),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Which report is this maintenance for?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (candidates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Text(
                        'No verified or in-progress reports yet.',
                        style: TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  for (final report in candidates)
                    ListTile(
                      leading: const Icon(Icons.ev_station, color: green),
                      title: Text(
                        report.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${report.locationLabel.isEmpty ? 'No location' : report.locationLabel}'
                        ' · ${report.status}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () =>
                          Navigator.pop(context, _MaintenanceTarget(report)),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.handyman_outlined,
                      color: planningMutedTextColor,
                    ),
                    title: const Text('Routine maintenance'),
                    subtitle: const Text('Not linked to a specific report'),
                    onTap: () =>
                        Navigator.pop(context, const _MaintenanceTarget(null)),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}
