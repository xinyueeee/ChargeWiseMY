import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class GapAnalysisScreen extends StatelessWidget {
  const GapAnalysisScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final vm = c.watch<PlanningViewModel>();
    final priorityAreas = vm.priorityAreas;
    debugPrint(
      'GapAnalysisScreen reads priority areas: '
      'viewModel=${identityHashCode(vm)}, '
      'count=${vm.highPriorityAreaCount}.',
    );
    final averageDistance = priorityAreas.isEmpty
        ? 0.0
        : priorityAreas.fold<double>(
                0, (sum, area) => sum + area.distance) /
            priorityAreas.length;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Gap Analysis',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: vm.loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    vm.analyzingGaps
                        ? 'Analyzing charging-station coverage…'
                        : 'Loading complete charging-station data…',
                  ),
                ],
              ),
            )
          : vm.errorMessage != null
              ? Center(
                  child: AppCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(vm.errorMessage!),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: vm.load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Charging-infrastructure coverage-gap analysis based on existing station locations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF5F6B82), fontSize: 17),
          ),
          if (vm.analyzingGaps) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Analyzing charging-station coverage…',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search location, state or area',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          const SizedBox(height: 18),
          GridView.count(
            crossAxisCount: 2,
            childAspectRatio: 1.3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              StatisticCard(
                value: '${priorityAreas.length}',
                label: 'Infrastructure Gaps Identified',
                icon: Icons.bolt,
                color: green,
              ),
              StatisticCard(
                value: '${vm.highPriorityAreaCount}',
                label: 'High Priority Areas',
                icon: Icons.location_on,
                color: blue,
              ),
              StatisticCard(
                value: '${averageDistance.toStringAsFixed(1)} km',
                label: 'Average Nearest-Station Distance',
                icon: Icons.bar_chart,
                color: Colors.orange,
              ),
              StatisticCard(
                value: '${vm.stations.length}',
                label: 'Station Coordinates Analysed',
                icon: Icons.ev_station,
                color: Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Gap Map Overview',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          MapPanel(
            height: 300,
            gaps: true,
            stations: vm.stations,
            proposals: vm.proposals,
            priorityAreas: priorityAreas,
          ),
          const SizedBox(height: 24),
          const Text(
            'Top Priority Gaps',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          ...priorityAreas.asMap().entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppCard(
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: e.value.priority == 'High'
                              ? Colors.red
                              : e.value.priority == 'Medium'
                                  ? Colors.orange
                                  : Colors.lightGreen,
                          child: Text(
                            '${e.key + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.value.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                 fontSize: 16,
                                ),
                              ),
                              Text(
                                '${e.value.nearbyStationCount} charging '
                                'station${e.value.nearbyStationCount == 1 ? '' : 's'} '
                                'within 25 km',
                                style: const TextStyle(
                                  color: Color(0xFF5F6B82),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Nearest station: '
                                '${e.value.distance.toStringAsFixed(1)} km',
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Priority score: '
                              '${e.value.priorityScore.toStringAsFixed(0)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 16),
          AppCard(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline, color: green),
              title: const Text(
                'Insights',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                priorityAreas.isEmpty
                    ? 'No high-priority coverage gaps were detected using the current station data and thresholds.'
                    : '${priorityAreas.length} non-overlapping coverage gaps were detected from ${vm.stations.length} station coordinates. These results measure charging access, not predicted EV demand.',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }
}
