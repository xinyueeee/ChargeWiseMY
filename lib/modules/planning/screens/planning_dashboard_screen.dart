import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../auth/screens/profile_screen.dart';
import '../../charging/screens/charging_screen.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import '../services/state_boundary_service.dart';
import 'gap_analysis_screen.dart';
import 'new_proposal_screen.dart';
import 'proposal_list_screen.dart';

class PlanningDashboardScreen extends StatefulWidget {
  const PlanningDashboardScreen({super.key});

  @override
  State<PlanningDashboardScreen> createState() =>
      _PlanningDashboardScreenState();
}

class _PlanningDashboardScreenState extends State<PlanningDashboardScreen>
    with RouteAware {
  PageRoute<dynamic>? _subscribedRoute;
  bool _mapMounted = true;
  bool _legendExpanded = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
      'PlanningDashboardScreen initState: '
      'instance=${identityHashCode(this)}.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> ||
        identical(route, _subscribedRoute)) {
      return;
    }
    if (_subscribedRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _subscribedRoute = route;
    appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    _setMapMounted(false, reason: 'dashboard route covered');
  }

  @override
  void didPopNext() {
    _setMapMounted(true, reason: 'dashboard route visible again');
  }

  void _setMapMounted(bool value, {required String reason}) {
    if (_mapMounted == value || !mounted) return;
    debugPrint(
      'PlanningDashboardScreen map lifecycle: '
      'instance=${identityHashCode(this)}, '
      'mounted=$value, reason=$reason.',
    );
    setState(() => _mapMounted = value);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    debugPrint(
      'PlanningDashboardScreen dispose: '
      'instance=${identityHashCode(this)}, mapMounted=$_mapMounted.',
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<PlanningViewModel>(
        builder: (_, vm, __) {
          debugPrint(
            'PlanningDashboardScreen reads priority areas: '
            'viewModel=${identityHashCode(vm)}, '
            'count=${vm.highPriorityAreaCount}.',
          );
          return vm.loading
              ? const PlanningLoadingState(
                  message: 'Loading infrastructure planning data…',
                )
              : SafeArea(
                  child: OrientationBuilder(
                    builder: (context, orientation) {
                      final size = MediaQuery.sizeOf(context);
                      final useSplitLayout = size.width >= 700 ||
                          (orientation == Orientation.landscape &&
                              size.width >= 540 &&
                              size.height <= 620);
                      if (useSplitLayout) {
                        return _buildLandscapeDashboard(context, vm, size);
                      }
                      return ListView(
                    padding: planningPagePadding,
                    children: [
                      PlanningSectionTitle(
                        'Infrastructure Planning',
                        subtitle:
                            'Plan smarter. Build better. Power the future.',
                        trailing: IconButton(
                          tooltip: 'Refresh planning data',
                          onPressed: vm.load,
                          icon: const Icon(Icons.refresh),
                        ),
                      ),
                      planningSectionGap,
                      if (vm.errorMessage != null) ...[
                        PlanningErrorState(
                          message: vm.errorMessage!,
                          onRetry: vm.load,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _buildPlanningRegionCard(vm),
                      const SizedBox(height: 18),
                      _buildMapExplorer(vm, height: 285),
                      planningSectionGap,
                      PlanningSectionTitle(
                        'Infrastructure Summary',
                        subtitle: vm.selectedState == malaysiaSelection
                            ? 'Physical charging locations across Malaysia'
                            : 'Physical charging locations in ${vm.selectedState}',
                      ),
                      const SizedBox(height: 12),
                      _InfrastructureSummaryCard(
                        locations: vm.selectedStationCount,
                        chargers: vm.selectedInstalledChargerCount,
                        acChargers: vm.selectedAcChargerCount,
                        dcChargers: vm.selectedDcChargerCount,
                      ),
                      planningSectionGap,
                      PlanningSectionTitle(
                        'Planning Activity',
                        subtitle: vm.selectedState == malaysiaSelection
                            ? 'Proposal and coverage-gap work across Malaysia'
                            : 'Proposal and coverage-gap work in ${vm.selectedState}',
                      ),
                      const SizedBox(height: 12),
                      _PlanningActivityCard(
                        pendingProposals: _proposalStatusCount(
                          vm.selectedProposals,
                          'pending',
                        ),
                        approvedProposals: _proposalStatusCount(
                          vm.selectedProposals,
                          'approved',
                        ),
                        highPriorityAreas: vm.highPriorityAreaCount,
                      ),
                      planningSectionGap,
                      _buildQuickActions(context),
                      planningSectionGap,
                      _PlanningInsightsCard(
                        highPriorityAreas: vm.highPriorityAreaCount,
                        pendingProposals: _proposalStatusCount(
                          vm.selectedProposals,
                          'pending',
                        ),
                        averageGapDistance: vm.averageGapDistance,
                      ),
                    ],
                      );
                    },
                  ),
                );
        },
      ),
      bottomNavigationBar: FloatingBottomNav(
        currentTab: 'Planning',
        onHomeTap: () => Navigator.of(context).popUntil(
          (route) => route.isFirst,
        ),
        onChargingTap: () => _switchTo(context, const ChargingScreen()),
        onProfileTap: () => _switchTo(context, const ProfileScreen()),
      ),
    );
  }

  Widget _buildLandscapeDashboard(
    BuildContext context,
    PlanningViewModel vm,
    Size size,
  ) {
    final pending = _proposalStatusCount(vm.selectedProposals, 'pending');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: PlanningSectionTitle(
            'Infrastructure Planning',
            subtitle: 'Plan smarter. Build better. Power the future.',
            trailing: IconButton(
              tooltip: 'Refresh planning data',
              onPressed: vm.load,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        if (vm.errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _InlinePlanningError(
              message: vm.errorMessage!,
              onRetry: vm.load,
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: size.width * .39,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildPlanningRegionCard(vm),
                      const SizedBox(height: 12),
                      const Text(
                        'Infrastructure Summary',
                        style: TextStyle(
                          color: planningTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _InfrastructureSummaryCard(
                        locations: vm.selectedStationCount,
                        chargers: vm.selectedInstalledChargerCount,
                        acChargers: vm.selectedAcChargerCount,
                        dcChargers: vm.selectedDcChargerCount,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Planning Activity',
                        style: TextStyle(
                          color: planningTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _PlanningActivityCard(
                        pendingProposals: pending,
                        approvedProposals:
                            _proposalStatusCount(vm.selectedProposals, 'approved'),
                        highPriorityAreas: vm.highPriorityAreaCount,
                      ),
                      const SizedBox(height: 12),
                      _buildQuickActions(context),
                      const SizedBox(height: 12),
                      _PlanningInsightsCard(
                        highPriorityAreas: vm.highPriorityAreaCount,
                        pendingProposals: pending,
                        averageGapDistance: vm.averageGapDistance,
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1, color: Color(0xFFE6EAF0)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 20, 16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Reserve room for the section heading, context strip,
                      // spacing, and the optional national-map hint. The map
                      // then consumes only the height this panel truly owns.
                      final chromeHeight =
                          vm.selectedState == malaysiaSelection ? 132.0 : 106.0;
                      final mapHeight =
                          (constraints.maxHeight - chromeHeight).clamp(96.0, 480.0);
                      return _buildMapExplorer(vm, height: mapHeight);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlanningRegionCard(PlanningViewModel vm) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Planning Region',
              style: TextStyle(
                color: planningTextColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: vm.selectedState,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.map_outlined),
                labelText: 'State or territory',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final state in vm.stateOptions)
                  DropdownMenuItem<String>(
                    value: state,
                    child: Text(state, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (state) {
                if (state != null) {
                  vm.selectState(state, source: 'dashboard-dropdown');
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (vm.analyzingGaps)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  )
                else
                  Icon(
                    vm.analysisErrorMessage == null
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 18,
                    color: vm.analysisErrorMessage == null ? green : Colors.red,
                  ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    vm.analysisStatusMessage ??
                        '${vm.selectedState} analysis ready',
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (vm.analysisErrorMessage != null)
                  TextButton(
                    onPressed: vm.retrySelectedStateAnalysis,
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ],
        ),
      );

  Widget _buildQuickActions(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              color: planningTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () => _push(context, const NewProposalScreen()),
            icon: const Icon(Icons.add_location_alt_outlined, size: 19),
            label: const Text('Add Proposal'),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final proposalsButton = OutlinedButton.icon(
                onPressed: () => _push(context, const ProposalListScreen()),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('View Proposals'),
              );
              final gapButton = OutlinedButton.icon(
                onPressed: () => _push(context, const GapAnalysisScreen()),
                icon: const Icon(Icons.analytics_outlined, size: 18),
                label: const Text('Gap Analysis'),
              );
              if (constraints.maxWidth < 330) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [proposalsButton, const SizedBox(height: 8), gapButton],
                );
              }
              return Row(
                children: [
                  Expanded(child: proposalsButton),
                  const SizedBox(width: 8),
                  Expanded(child: gapButton),
                ],
              );
            },
          ),
        ],
      );

  Widget _buildMapExplorer(PlanningViewModel vm, {required double height}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanningSectionTitle(
            'Interactive Map',
            subtitle: vm.selectedState == malaysiaSelection
                ? 'Select a state to explore local infrastructure'
                : 'Explore locations, proposals, and priority areas',
          ),
          const SizedBox(height: 8),
          if (_mapMounted)
            Stack(
              clipBehavior: Clip.none,
              children: [
                MapPanel(
                  height: height,
                  stations: vm.mapStations,
                  proposals: vm.mapProposals,
                  priorityAreas: vm.mapPriorityAreas,
                  stateRegions: vm.stateRegions,
                  stateOverviews: vm.stateOverviewSummaries,
                  selectedState: vm.selectedState,
                  focusBounds: vm.selectedMapBounds,
                  analysisCacheHit: vm.lastAnalysisCacheHit,
                  onStateSelected: (state, source) => vm.selectState(
                    state,
                    source: source,
                  ),
                ),
                if (vm.selectedState != malaysiaSelection)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _CompactMapLegend(
                      expanded: _legendExpanded,
                      onToggle: () => setState(
                        () => _legendExpanded = !_legendExpanded,
                      ),
                    ),
                  ),
              ],
            )
          else
            SizedBox(height: height),
          const SizedBox(height: 8),
          _MapContextCard(
            locations: vm.selectedStationCount,
            chargers: vm.selectedInstalledChargerCount,
            activeProposals: _proposalStatusCount(vm.selectedProposals, 'pending'),
            priorityAreas: vm.highPriorityAreaCount,
          ),
          if (vm.selectedState == malaysiaSelection) ...[
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 16,
                  color: planningMutedTextColor,
                ),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Tap a state to explore local charging infrastructure',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      );

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  void _switchTo(BuildContext context, Widget page) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  static int _proposalStatusCount(
    Iterable<Proposal> proposals,
    String status,
  ) => proposals
      .where((proposal) => proposal.status.trim().toLowerCase() == status)
      .length;
}

class _InlinePlanningError extends StatelessWidget {
  const _InlinePlanningError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: planningMutedTextColor),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _InfrastructureSummaryCard extends StatelessWidget {
  const _InfrastructureSummaryCard({
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
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 420;
            final metrics = [
              _DashboardPrimaryMetric(
                icon: Icons.location_on_outlined,
                label: 'Charging Locations',
                value: '$locations',
                color: green,
              ),
              _DashboardPrimaryMetric(
                icon: Icons.ev_station_outlined,
                label: 'Installed Chargers',
                value: '$chargers',
                color: blue,
              ),
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt_outlined, color: green),
                    SizedBox(width: 8),
                    Text(
                      'Charging Infrastructure',
                      style: TextStyle(
                        color: planningTextColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (horizontal)
                  Row(
                    children: [
                      Expanded(child: metrics.first),
                      const SizedBox(
                        height: 42,
                        child: VerticalDivider(color: Color(0xFFE6EAF0)),
                      ),
                      Expanded(child: metrics.last),
                    ],
                  )
                else
                  Column(
                    children: [
                      metrics.first,
                      const Divider(height: 24, color: Color(0xFFE6EAF0)),
                      metrics.last,
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  'AC $acChargers · DC $dcChargers',
                  style: const TextStyle(
                    color: planningMutedTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
      );
}

class _DashboardPrimaryMetric extends StatelessWidget {
  const _DashboardPrimaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 25,
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
      );
}

class _PlanningActivityCard extends StatelessWidget {
  const _PlanningActivityCard({
    required this.pendingProposals,
    required this.approvedProposals,
    required this.highPriorityAreas,
  });

  final int pendingProposals;
  final int approvedProposals;
  final int highPriorityAreas;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proposal Activity',
              style: TextStyle(
                color: planningTextColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActivityPill(
                  icon: Icons.schedule_outlined,
                  text: 'Pending $pendingProposals',
                  color: const Color(0xFFF39C12),
                ),
                _ActivityPill(
                  icon: Icons.check_circle_outline,
                  text: 'Approved $approvedProposals',
                  color: green,
                ),
                _ActivityPill(
                  icon: Icons.insights_outlined,
                  text: 'Priority $highPriorityAreas',
                  color: const Color(0xFFE67E22),
                ),
              ],
            ),
          ],
        ),
      );
}

class _ActivityPill extends StatelessWidget {
  const _ActivityPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

class _MapContextCard extends StatelessWidget {
  const _MapContextCard({
    required this.locations,
    required this.chargers,
    required this.activeProposals,
    required this.priorityAreas,
  });

  final int locations;
  final int chargers;
  final int activeProposals;
  final int priorityAreas;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            _MapContextMetric(value: '$locations', label: 'locations'),
            _MapContextMetric(value: '$chargers', label: 'installed chargers'),
            _MapContextMetric(value: '$activeProposals', label: 'active proposals'),
            _MapContextMetric(value: '$priorityAreas', label: 'priority areas'),
          ],
        ),
      );
}

class _MapContextMetric extends StatelessWidget {
  const _MapContextMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: const TextStyle(color: planningMutedTextColor, fontSize: 13),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: planningTextColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: label),
          ],
        ),
      );
}

class _PlanningInsightsCard extends StatelessWidget {
  const _PlanningInsightsCard({
    required this.highPriorityAreas,
    required this.pendingProposals,
    required this.averageGapDistance,
  });

  final int highPriorityAreas;
  final int pendingProposals;
  final double averageGapDistance;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Planning Insights',
              style: TextStyle(
                color: planningTextColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            _InsightLine(
              icon: Icons.insights_outlined,
              text: highPriorityAreas == 0
                  ? 'No high-priority coverage gaps are currently ranked.'
                  : '$highPriorityAreas high-priority coverage gap${highPriorityAreas == 1 ? '' : 's'} need attention.',
            ),
            const SizedBox(height: 8),
            _InsightLine(
              icon: Icons.rate_review_outlined,
              text: pendingProposals == 0
                  ? 'No proposals are awaiting action.'
                  : '$pendingProposals proposal${pendingProposals == 1 ? '' : 's'} await${pendingProposals == 1 ? 's' : ''} action.',
            ),
            const SizedBox(height: 8),
            _InsightLine(
              icon: Icons.route_outlined,
              text: averageGapDistance <= 0
                  ? 'No ranked coverage-gap distance is available for this selection.'
                  : 'Ranked gaps average ${averageGapDistance.toStringAsFixed(1)} km to the nearest charging location.',
            ),
          ],
        ),
      );
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: planningMutedTextColor, height: 1.35),
            ),
          ),
        ],
      );
}

class _CompactMapLegend extends StatelessWidget {
  const _CompactMapLegend({
    required this.expanded,
    required this.onToggle,
  });

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.layers_outlined, size: 20),
                    const SizedBox(width: 6),
                    const Text(
                      'Layers',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 10),
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 2, 8, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MapLegendItem(
                      asset: 'assets/icons/station_lightning.png',
                      label: 'Charging locations',
                    ),
                    SizedBox(height: 7),
                    _MapLegendItem(
                      asset: 'assets/icons/proposed_station.png',
                      label: 'Proposed',
                    ),
                    SizedBox(height: 7),
                    _MapLegendItem(
                      asset: 'assets/icons/high_priority.png',
                      label: 'Priority gap',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
}

class _MapLegendItem extends StatelessWidget {
  const _MapLegendItem({required this.asset, required this.label});

  final String asset;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(asset, width: 18, height: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}
