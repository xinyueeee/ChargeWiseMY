import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../models/fault_report.dart';
import '../viewmodels/feedback_viewmodel.dart';
import '../widgets/feedback_widgets.dart';
import 'report_details_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, this.initialTab = 'All'});

  final String initialTab;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = [
    'All',
    'Submitted',
    'Verified',
    'In Progress',
    'Resolved',
  ];
  static const _pageSize = 5;

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _categoryFilter;
  String _sort = 'Newest';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final initialIndex = _tabs.indexOf(widget.initialTab);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
    )..addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _page = 0);
        }
      });
    // Refresh on open so any status change an admin made since the list last
    // loaded (app startup / previous visit) shows up here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedbackViewModel>().load(silent: true);
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
    final filtered = source.where((report) {
      final matchesTab =
          tabLabel == 'All' || feedbackStatusLabel(report.status) == tabLabel;
      final matchesCategory =
          _categoryFilter == null || report.category == _categoryFilter;
      final matchesQuery = query.isEmpty ||
          report.category.toLowerCase().contains(query) ||
          report.description.toLowerCase().contains(query) ||
          report.locationLabel.toLowerCase().contains(query);
      return matchesTab && matchesCategory && matchesQuery;
    }).toList()
      ..sort((a, b) {
        final aDate = a.createdAt ?? DateTime(0);
        final bDate = b.createdAt ?? DateTime(0);
        return _sort == 'Newest'
            ? bDate.compareTo(aDate)
            : aDate.compareTo(bDate);
      });
    return filtered;
  }

  DriverNavigationConfig _navConfig(BuildContext context) =>
      DriverNavigationConfig(
        currentTab: 'Feedback',
        onHomeTap: () => switchDriverTab(context, DriverTab.home),
        onChargingTap: () => switchDriverTab(context, DriverTab.charging),
        onFeedbackTap: () => Navigator.of(context).pop(),
        onPlanningTap: () => switchDriverTab(context, DriverTab.planning),
        onProfileTap: () => switchDriverTab(context, DriverTab.profile),
      );

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
              Text('My Reports', style: planningAppBarTitleStyle),
              SizedBox(height: 2),
              Text(
                'View and manage your reported issues',
                style: TextStyle(
                  fontSize: 12,
                  color: planningMutedTextColor,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE9EDF3))),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: green,
                unselectedLabelColor: planningMutedTextColor,
                indicatorColor: green,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: [for (final tab in _tabs) Tab(text: tab)],
              ),
            ),
          ),
        ),
        body: DriverNavigationShell(
          config: _navConfig(context),
          child: Consumer<FeedbackViewModel>(
            builder: (context, vm, __) {
              if (vm.loading) {
                return const PlanningLoadingState(
                  message: 'Loading your reports…',
                );
              }
              if (vm.errorMessage != null) {
                return PlanningErrorState(
                  message: vm.errorMessage!,
                  onRetry: vm.load,
                );
              }

              final filtered = _applyFilters(vm.myReports);
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.search),
                                    hintText: 'Search by issue or location',
                                    suffixIcon: _query.isEmpty
                                        ? null
                                        : IconButton(
                                            tooltip: 'Clear search',
                                            onPressed: () {
                                              FocusScope.of(context).unfocus();
                                              _searchController.clear();
                                              setState(() {
                                                _query = '';
                                                _page = 0;
                                              });
                                            },
                                            icon: const Icon(Icons.clear),
                                          ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onChanged: (value) => setState(() {
                                    _query = value;
                                    _page = 0;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 10),
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
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'My Reports (${filtered.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: planningTextColor,
                                ),
                              ),
                              DropdownButton<String>(
                                value: _sort,
                                underline: const SizedBox.shrink(),
                                icon: const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: green,
                                  size: 18,
                                ),
                                style: const TextStyle(
                                  color: green,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'Newest',
                                    child: Text('Sort by: Newest'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'Oldest',
                                    child: Text('Sort by: Oldest'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _sort = value;
                                    _page = 0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () => vm.load(silent: true),
                        child: filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                children: [
                                  PlanningEmptyState(
                                    icon: Icons.fact_check_outlined,
                                    title: vm.myReports.isEmpty
                                        ? 'No reports yet'
                                        : 'No matching reports',
                                    message: vm.myReports.isEmpty
                                        ? 'Submit your first fault report to '
                                            'help keep charging stations '
                                            'reliable.'
                                        : 'Try changing the search text, tab, '
                                            'or category filter.',
                                  ),
                                ],
                              )
                            : ListView(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 8),
                                children: [
                                  for (final report in pageItems) ...[
                                    ReportCard(
                                      report: report,
                                      trailingTime:
                                          formatRelativeTime(report.createdAt),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) => ReportDetailsScreen(
                                              report: report),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  const SizedBox(height: 6),
                                  _Pagination(
                                    page: page,
                                    totalPages: totalPages,
                                    onChanged: (next) =>
                                        setState(() => _page = next),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: _navConfig(context).bottomBarFor(context),
      );

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter by Category',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: planningTextColor,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All categories'),
                    selected: draft == null,
                    selectedColor: green.withValues(alpha: .16),
                    onSelected: (_) => setSheetState(() => draft = null),
                  ),
                  for (final category in kFaultReportCategories)
                    ChoiceChip(
                      label: Text(category),
                      selected: draft == category,
                      selectedColor: green.withValues(alpha: .16),
                      onSelected: (_) => setSheetState(() => draft = category),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _categoryFilter = draft;
                      _page = 0;
                    });
                    Navigator.of(sheetContext).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply Filter'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.totalPages,
    required this.onChanged,
  });

  final int page;
  final int totalPages;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        for (var index = 0; index < totalPages; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => onChanged(index),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == page ? green : Colors.transparent,
                  shape: BoxShape.circle,
                  border: index == page
                      ? null
                      : Border.all(color: const Color(0xFFE9EDF3)),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index == page ? Colors.white : planningTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          onPressed: page < totalPages - 1 ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}
