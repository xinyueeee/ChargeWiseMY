import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../../auth/screens/profile_screen.dart';
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
                  child: ListView(
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
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Planning region',
                              style: TextStyle(
                                color: planningTextColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: vm.selectedState,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.map_outlined),
                                labelText: 'Malaysian state or territory',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final state in vm.stateOptions)
                                  DropdownMenuItem<String>(
                                    value: state,
                                    child: Text(
                                      state,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (state) {
                                if (state != null) {
                                  vm.selectState(
                                    state,
                                    source: 'dashboard-dropdown',
                                  );
                                }
                              },
                            ),
                            if (vm.selectedState != malaysiaSelection) ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: InputChip(
                                  avatar: const Icon(
                                    Icons.location_on_outlined,
                                    size: 17,
                                    color: green,
                                  ),
                                  label: Text(vm.selectedState),
                                  deleteIcon: const Icon(Icons.close, size: 17),
                                  deleteButtonTooltipMessage:
                                      'Return to Malaysia Overview',
                                  onDeleted: () => vm.selectState(
                                    malaysiaSelection,
                                    source: 'state-chip-clear',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            AnalysisStatusPanel(
                              message: vm.analysisStatusMessage ??
                                  '${vm.selectedState} analysis ready',
                              analyzing: vm.analyzingGaps,
                              hasError: vm.analysisErrorMessage != null,
                              onRetry: vm.analysisErrorMessage == null
                                  ? null
                                  : vm.retrySelectedStateAnalysis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_mapMounted)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            MapPanel(
                              height: 300,
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
                                top: 10,
                                left: 10,
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
                        const SizedBox(height: 300),
                      if (vm.selectedState == malaysiaSelection) ...[
                        const SizedBox(height: 8),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.touch_app_outlined,
                              size: 17,
                              color: planningMutedTextColor,
                            ),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Tap a state to explore its charging infrastructure',
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
                      const SizedBox(height: 18),
                      PlanningSectionTitle(
                        'Infrastructure Overview',
                        subtitle: vm.selectedState == malaysiaSelection
                            ? 'Current nationwide planning summary'
                            : 'Current planning summary for ${vm.selectedState}',
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 700 ? 4 : 2;
                          return GridView.count(
                            crossAxisCount: columns,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio:
                                constraints.maxWidth < 360 ? 1.05 : 1.22,
                            children: [
                            StatisticCard(
                              value: '${vm.selectedStationCount}',
                              label: 'Existing Stations',
                              icon: Icons.bolt,
                              color: green,
                              width: double.infinity,
                            ),
                            StatisticCard(
                              value: '${vm.proposalCount}',
                              label: 'Proposed Stations',
                              icon: Icons.ev_station,
                              color: blue,
                              width: double.infinity,
                            ),
                            StatisticCard(
                              value: '${vm.highPriorityAreaCount}',
                              label: 'High Priority Areas',
                              icon: Icons.insights,
                              color: Colors.orange,
                              width: double.infinity,
                            ),
                            StatisticCard(
                              value: '${vm.communitySupportCount}',
                              label: 'Community Support',
                              icon: Icons.group_outlined,
                              color: Colors.deepPurple,
                              width: double.infinity,
                            ),
                            ],
                          );
                        },
                      ),
                      planningSectionGap,
                      const PlanningSectionTitle(
                        'Quick Actions',
                        subtitle: 'Create proposals or review coverage',
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: () => _push(
                          context,
                          const NewProposalScreen(),
                        ),
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Add Proposed Station'),
                      ),
                      const SizedBox(height: 10),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final proposalsButton = OutlinedButton.icon(
                            onPressed: () => _push(
                              context,
                              const ProposalListScreen(),
                            ),
                            icon: const Icon(Icons.article_outlined),
                            label: const Text('View Proposals'),
                          );
                          final gapButton = OutlinedButton.icon(
                            onPressed: () => _push(
                              context,
                              const GapAnalysisScreen(),
                            ),
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('Gap Analysis'),
                          );
                          if (constraints.maxWidth < 420) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                proposalsButton,
                                const SizedBox(height: 10),
                                gapButton,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: proposalsButton),
                              const SizedBox(width: 10),
                              Expanded(child: gapButton),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
        },
      ),
      bottomNavigationBar: FloatingBottomNav(
        onProfileTap: () => _push(context, const ProfileScreen()),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
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
                      label: 'Existing',
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
