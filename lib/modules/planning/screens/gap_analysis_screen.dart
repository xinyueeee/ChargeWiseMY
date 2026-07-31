import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'priority_area_map_screen.dart';

class GapAnalysisScreen extends StatelessWidget {
  const GapAnalysisScreen({super.key});

  void _openAreaMap(BuildContext context, GapArea area) {
    if (area.latitude == null || area.longitude == null) {
      debugPrint(
        'GapAnalysisScreen map action skipped: '
        'area=${area.id}, reason=invalid coordinates.',
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PriorityAreaMapScreen(area: area),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PlanningViewModel>(
      builder: (context, viewModel, _) {
        final areas = viewModel.priorityAreas;
        debugPrint(
          'GapAnalysisScreen reads state analysis: '
          'viewModel=${identityHashCode(viewModel)}, '
          'state=${viewModel.selectedState}, resultCount=${areas.length}.',
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'State Gap Analysis',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: Colors.black,
          ),
          body: viewModel.loading
              ? const PlanningLoadingState(
                  message: 'Loading station locations…',
                )
              : SafeArea(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: planningPagePadding,
                        sliver: SliverList(
                          delegate: SliverChildListDelegate.fixed([
                            const Text(
                              'Coverage-gap analysis based only on existing '
                              'charging-station coordinates and proximity.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: planningMutedTextColor,
                                height: 1.4,
                              ),
                            ),
                            planningSectionGap,
                            DropdownButtonFormField<String>(
                              value: viewModel.selectedState,
                              isExpanded: true,
                              decoration: InputDecoration(
                                prefixIcon:
                                    const Icon(Icons.location_on_outlined),
                                labelText: 'Planning region',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: [
                                for (final state in viewModel.stateOptions)
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
                                  viewModel.selectState(state);
                                }
                              },
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: viewModel.analyzingGaps
                                  ? null
                                  : viewModel.runSelectedStateAnalysis,
                              icon: viewModel.analyzingGaps
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.analytics_outlined),
                              label: Text(
                                viewModel.analyzingGaps
                                    ? 'Analyzing ${viewModel.selectedState}…'
                                    : 'Run Analysis',
                              ),
                            ),
                            if (viewModel.analysisErrorMessage != null) ...[
                              const SizedBox(height: 10),
                              PlanningErrorState(
                                message: viewModel.analysisErrorMessage!,
                                onRetry: viewModel.runSelectedStateAnalysis,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Text(
                              '${areas.length} ranked infrastructure gap'
                              '${areas.length == 1 ? '' : 's'} in '
                              '${viewModel.selectedState}',
                              style: const TextStyle(
                                color: planningMutedTextColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            planningSectionGap,
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final columns =
                                    constraints.maxWidth >= 700 ? 3 : 2;
                                return GridView.count(
                                  crossAxisCount: columns,
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio:
                                      constraints.maxWidth < 360 ? .92 : 1.12,
                                  children: [
                                    StatisticCard(
                                      width: double.infinity,
                                      value: '${areas.length}',
                                      label: 'Infrastructure Gaps',
                                      icon: Icons.location_on_outlined,
                                      color: blue,
                                    ),
                                    StatisticCard(
                                      width: double.infinity,
                                      value:
                                          '${viewModel.highPriorityAreaCount}',
                                      label: 'High Priority Areas',
                                      icon: Icons.priority_high,
                                      color: Colors.red,
                                    ),
                                    StatisticCard(
                                      width: double.infinity,
                                      value:
                                          '${viewModel.mediumPriorityAreaCount}',
                                      label: 'Medium Priority Areas',
                                      icon: Icons.remove,
                                      color: Colors.orange,
                                    ),
                                    StatisticCard(
                                      width: double.infinity,
                                      value:
                                          '${viewModel.lowPriorityAreaCount}',
                                      label: 'Low Priority Areas',
                                      icon: Icons.low_priority,
                                      color: green,
                                    ),
                                    StatisticCard(
                                      width: double.infinity,
                                      value:
                                          '${viewModel.averageGapDistance.toStringAsFixed(1)} km',
                                      label: 'Average Nearest Station',
                                      icon: Icons.route_outlined,
                                      color: Colors.orange,
                                    ),
                                    StatisticCard(
                                      width: double.infinity,
                                      value: viewModel.averageCoverageScore
                                          .toStringAsFixed(1),
                                      label: 'Average Coverage Score',
                                      icon: Icons.analytics_outlined,
                                      color: Colors.deepPurple,
                                    ),
                                  ],
                                );
                              },
                            ),
                            planningSectionGap,
                            PlanningSectionTitle(
                              'Top Priority List',
                              subtitle: areas.isEmpty
                                  ? 'No ranked results for this region'
                                  : 'Ranked by the existing coverage-gap score',
                            ),
                          ]),
                        ),
                      ),
                      if (viewModel.analyzingGaps)
                        const SliverPadding(
                          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver: SliverToBoxAdapter(
                            child: PlanningLoadingState(
                              message:
                                  'Analyzing cached station coordinates…',
                            ),
                          ),
                        )
                      else if (areas.isEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          sliver: SliverToBoxAdapter(
                            child: PlanningEmptyState(
                              icon: Icons.check_circle_outline,
                              title: 'No infrastructure gaps detected',
                              message:
                                  'No grid cells in ${viewModel.selectedState} '
                                  'met the current station-coverage criteria.',
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final area = areas[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _PriorityGapCard(
                                    rank: index + 1,
                                    area: area,
                                    onViewMap: area.latitude == null ||
                                            area.longitude == null
                                        ? null
                                        : () => _openAreaMap(context, area),
                                  ),
                                );
                              },
                              childCount: areas.length,
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                        sliver: SliverToBoxAdapter(
                          child: AppCard(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.insights_outlined, color: green),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    viewModel.analysisInsight,
                                    style: const TextStyle(
                                      color: planningMutedTextColor,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          bottomNavigationBar: const FloatingBottomNav(),
        );
      },
    );
  }
}

class _PriorityGapCard extends StatelessWidget {
  const _PriorityGapCard({
    required this.rank,
    required this.area,
    required this.onViewMap,
  });

  final int rank;
  final GapArea area;
  final VoidCallback? onViewMap;

  @override
  Widget build(BuildContext context) {
    final priorityColor = area.priority == 'High'
        ? Colors.red
        : area.priority == 'Medium'
            ? Colors.orange
            : green;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: priorityColor,
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  area.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: planningTextColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: priorityColor.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    area.priority,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: priorityColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _GapMetric(
                icon: Icons.stars_outlined,
                value:
                    'Priority score ${area.priorityScore.toStringAsFixed(0)}',
              ),
              _GapMetric(
                icon: Icons.route_outlined,
                value: 'Nearest ${area.distance.toStringAsFixed(1)} km',
              ),
              _GapMetric(
                icon: Icons.analytics_outlined,
                value:
                    'Coverage score ${area.coverageScore.toStringAsFixed(1)}',
              ),
              _GapMetric(
                icon: Icons.ev_station_outlined,
                value:
                    '${area.nearbyStationCount} stations within 25 km',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            area.reason,
            style: const TextStyle(
              color: planningMutedTextColor,
              height: 1.35,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onViewMap,
              icon: const Icon(Icons.map_outlined, size: 18),
              label: const Text('View on Map'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GapMetric extends StatelessWidget {
  const _GapMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: planningMutedTextColor),
          const SizedBox(width: 5),
          Text(
            value,
            style: const TextStyle(
              color: planningMutedTextColor,
              fontSize: 13,
            ),
          ),
        ],
      );
}
