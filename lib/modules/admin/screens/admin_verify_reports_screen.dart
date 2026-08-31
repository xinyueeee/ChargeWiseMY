import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/models/fault_report.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'admin_report_details_screen.dart';

class AdminVerifyReportsScreen extends StatefulWidget {
  const AdminVerifyReportsScreen({super.key});

  @override
  State<AdminVerifyReportsScreen> createState() =>
      _AdminVerifyReportsScreenState();
}

class _AdminVerifyReportsScreenState extends State<AdminVerifyReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'All',
    'High Priority',
    'Medium Priority',
    'Low Priority'
  ];
  static const _pageSize = 6;

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  int _page = 0;
  final Set<String> _verifying = {};

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
      final matchesTab =
          tabLabel == 'All' || '${report.priority} Priority' == tabLabel;
      final matchesCategory =
          _categoryFilter == null || report.category == _categoryFilter;
      final matchesQuery = query.isEmpty ||
          report.category.toLowerCase().contains(query) ||
          report.locationLabel.toLowerCase().contains(query);
      return matchesTab && matchesCategory && matchesQuery;
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime(0);
        final bDate = b.createdAt ?? DateTime(0);
        return bDate.compareTo(aDate);
      });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          titleSpacing: 0,
          title: const Text(
            'Verify Reports',
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
        body: Consumer<AdminFeedbackViewModel>(
          builder: (context, vm, __) {
            if (vm.loading) {
              return const PlanningLoadingState(message: 'Loading reports…');
            }
            final toVerify = vm.reportsToVerify;
            final high = toVerify.where((r) => r.priority == 'High').length;
            final medium = toVerify.where((r) => r.priority == 'Medium').length;
            final low = toVerify.where((r) => r.priority == 'Low').length;
            final filtered = _applyFilters(toVerify);
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
                        Text(
                          'Review and verify submitted reports',
                          style: const TextStyle(color: planningMutedTextColor),
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
                                  color: blue.withValues(alpha: .12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.search, color: blue),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${toVerify.length}',
                                      style: const TextStyle(
                                        color: blue,
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Text(
                                      'Reports to Verify',
                                      style: TextStyle(
                                        color: planningTextColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'Reports awaiting review and verification',
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
                                  _legendDot('High Priority', high, red),
                                  _legendDot('Medium Priority', medium, orange),
                                  _legendDot('Low Priority', low, green),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                onChanged: (value) =>
                                    setState(() => _query = value),
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.search),
                                  hintText: 'Search by issue or location',
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
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _openFilterSheet(context),
                              icon: const Icon(Icons.filter_list, size: 18),
                              label: Text(
                                _categoryFilter == null
                                    ? 'Filter'
                                    : 'Filter (1)',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: blue,
                          unselectedLabelColor: planningMutedTextColor,
                          indicatorColor: blue,
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            for (final tab in _tabs)
                              Tab(
                                text: tab == 'All'
                                    ? 'All (${toVerify.length})'
                                    : '$tab (${tab.startsWith('High') ? high : tab.startsWith('Medium') ? medium : low})',
                              ),
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
                              icon: Icons.fact_check_outlined,
                              title: 'Nothing to verify',
                              message:
                                  'No reports match this filter right now.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: pageItems.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final report = pageItems[index];
                              final verifying = _verifying.contains(report.id);
                              return AdminReportListTile(
                                title: report.category,
                                location: report.locationLabel,
                                dateLabel: submittedOnLabel(report.createdAt),
                                subtitle: 'Reported by: '
                                    '${report.reporterName ?? 'Unknown driver'}',
                                photoUrl: report.photoUrls.isEmpty
                                    ? null
                                    : report.photoUrls.first,
                                chip: PriorityChip(report.priority),
                                onTap: () => _openDetails(context, report),
                                actions: Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            _openDetails(context, report),
                                        child: const Text('View Details'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: green,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: verifying
                                            ? null
                                            : () => _verify(vm, report),
                                        child: verifying
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text('Verify'),
                                      ),
                                    ),
                                  ],
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

  void _openDetails(BuildContext context, FaultReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdminReportDetailsScreen(report: report),
      ),
    );
  }

  Future<void> _verify(AdminFeedbackViewModel vm, FaultReport report) async {
    setState(() => _verifying.add(report.id));
    try {
      await vm.verifyReport(report);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${report.category}" verified.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Verify report failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to verify. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _verifying.remove(report.id));
    }
  }

  void _openFilterSheet(BuildContext context) {
    var draft = _categoryFilter;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filter by Category',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in kFaultReportCategories)
                    ChoiceChip(
                      label: Text(category),
                      selected: draft == category,
                      onSelected: (selected) => setSheetState(
                        () => draft = selected ? category : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _categoryFilter = draft;
                    _page = 0;
                  });
                  Navigator.of(sheetContext).pop();
                },
                child: const Text('Apply Filter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
