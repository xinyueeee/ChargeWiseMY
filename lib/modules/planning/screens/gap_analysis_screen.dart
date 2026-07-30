import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/priority_area_filter.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'priority_area_map_screen.dart';

class GapAnalysisScreen extends StatefulWidget {
  const GapAnalysisScreen({super.key});

  @override
  State<GapAnalysisScreen> createState() => _GapAnalysisScreenState();
}

class _GapAnalysisScreenState extends State<GapAnalysisScreen> {
  String _selectedState = allStatesFilter;
  PlanningViewModel? _viewModel;
  List<GapArea> _nationwideAreas = const [];
  List<GapArea> _filteredAreas = const [];
  Map<String, int> _stateCounts = const {};
  double _averageDistance = 0;

  @override
  void initState() {
    super.initState();
    debugPrint(
      'GapAnalysisScreen initState: instance=${identityHashCode(this)}.',
    );
    debugPrint(
      'GapAnalysisScreen map-free diagnostic: '
      'instance=${identityHashCode(this)}, ownsGoogleMap=false.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = context.read<PlanningViewModel>();
    if (identical(viewModel, _viewModel)) return;
    _viewModel?.removeListener(_handleViewModelChange);
    _viewModel = viewModel;
    _viewModel!.addListener(_handleViewModelChange);
    _refreshFilteredData();
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_handleViewModelChange);
    debugPrint(
      'GapAnalysisScreen dispose: instance=${identityHashCode(this)}.',
    );
    super.dispose();
  }

  void _handleViewModelChange() {
    if (!mounted) return;
    setState(_refreshFilteredData);
  }

  void _refreshFilteredData() {
    final areas = _viewModel?.priorityAreas ?? const <GapArea>[];
    if (identical(areas, _nationwideAreas)) return;
    final counts = <String, int>{
      for (final state in malaysianStateOptions) state: 0,
      allStatesFilter: areas.length,
    };
    for (final area in areas) {
      if (counts.containsKey(area.state)) {
        counts[area.state] = counts[area.state]! + 1;
      }
    }
    _nationwideAreas = areas;
    _stateCounts = Map.unmodifiable(counts);
    _applyStateFilter();
  }

  void _applyStateFilter() {
    _filteredAreas = filterPriorityAreasByState(
      _nationwideAreas,
      _selectedState,
    );
    _averageDistance = _filteredAreas.isEmpty
        ? 0
        : _filteredAreas.fold<double>(
                0, (sum, area) => sum + area.distance) /
            _filteredAreas.length;
  }

  void _openAreaMap(GapArea area) {
    if (area.latitude == null || area.longitude == null) {
      debugPrint(
        'GapAnalysisScreen map action skipped: '
        'area=${area.id}, reason=invalid coordinates.',
      );
      return;
    }
    debugPrint(
      'GapAnalysisScreen opens focused map: '
      'instance=${identityHashCode(this)}, area=${area.id}.',
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PriorityAreaMapScreen(area: area),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final vm = _viewModel!;
    debugPrint(
      'GapAnalysisScreen reads priority areas: '
      'viewModel=${identityHashCode(vm)}, '
      'nationwideCount=${vm.highPriorityAreaCount}, '
      'selectedState=$_selectedState, '
      'filteredCount=${_filteredAreas.length}.',
    );
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
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedState,
            isExpanded: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.location_on_outlined),
              labelText: 'State',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            items: [
              for (final state in malaysianStateOptions)
                DropdownMenuItem<String>(
                  value: state,
                  child: Text(
                    '$state '
                    '(${_stateCounts[state] ?? 0})',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (state) {
              if (state == null || state == _selectedState) return;
              setState(() {
                _selectedState = state;
                _applyStateFilter();
              });
            },
          ),
          const SizedBox(height: 10),
          Text(
            _selectedState == allStatesFilter
                ? '${_filteredAreas.length} priority gaps nationwide'
                : '${_filteredAreas.length} priority gaps in $_selectedState',
            style: const TextStyle(
              color: Color(0xFF5F6B82),
              fontWeight: FontWeight.w600,
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
                value: '${_filteredAreas.length}',
                label: 'Infrastructure Gaps Identified',
                icon: Icons.bolt,
                color: green,
              ),
              StatisticCard(
                value: '${_filteredAreas.length}',
                label: 'High Priority Areas',
                icon: Icons.location_on,
                color: blue,
              ),
              StatisticCard(
                value: '${_averageDistance.toStringAsFixed(1)} km',
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
          AppCard(
            child: Column(
              children: [
                const Icon(
                  Icons.map_outlined,
                  size: 46,
                  color: green,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Interactive map available on demand',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Open a priority area to view its coverage circle. '
                  'This keeps only one Android map active at a time.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF5F6B82)),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _filteredAreas.isEmpty
                      ? null
                      : () => _openAreaMap(_filteredAreas.first),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('View highest-priority gap on map'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Top Priority Gaps',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (_filteredAreas.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: AppCard(
                child: Text(
                  _selectedState == allStatesFilter
                      ? 'No priority coverage gaps detected nationwide.'
                      : 'No priority coverage gaps detected in $_selectedState.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ..._filteredAreas.asMap().entries.map(
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
                              const SizedBox(height: 2),
                              Text(
                                'Priority score: '
                                '${e.value.priorityScore.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'View on map',
                          onPressed: e.value.latitude == null ||
                                  e.value.longitude == null
                              ? null
                              : () => _openAreaMap(e.value),
                          icon: const Icon(Icons.map_outlined),
                        ),
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
                _filteredAreas.isEmpty
                    ? 'No high-priority coverage gaps were detected using the current station data and thresholds.'
                    : '${_filteredAreas.length} non-overlapping coverage gaps are shown for ${_selectedState == allStatesFilter ? 'Malaysia' : _selectedState}. The nationwide analysis used ${vm.stations.length} station coordinates and measures charging access, not predicted EV demand.',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }
}
