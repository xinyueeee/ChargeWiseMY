import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
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
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu, size: 30),
                          const SizedBox(width: 20),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Infrastructure Planning',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF101B40),
                                  ),
                                ),
                                Text(
                                  'Plan smarter. Build better. Power the future.',
                                  style: TextStyle(color: Color(0xFF5F6B82)),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.notifications_none, size: 30),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (vm.errorMessage != null) ...[
                        AppCard(
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_off_outlined,
                                  color: Colors.red),
                              const SizedBox(width: 10),
                              Expanded(child: Text(vm.errorMessage!)),
                              TextButton(
                                onPressed: vm.load,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search location, state or area',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(28),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8F9FC),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_mapMounted)
                        Stack(
                          children: [
                          MapPanel(
                            height: 300,
                            stations: vm.stations,
                            proposals: vm.proposals,
                            priorityAreas: vm.priorityAreas,
                          ),
                          Positioned(
                            left: 14,
                            top: 14,
                            child: AppCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('⚡  Existing Stations'),
                                  SizedBox(height: 10),
                                  Text('🔌  Proposed Stations'),
                                  SizedBox(height: 10),
                                  Text('🔴  High Priority Area'),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            top: 14,
                            child: AppCard(
                              padding: const EdgeInsets.all(12),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _MapLegendItem(
                                    asset: 'assets/icons/station_lightning.png',
                                    label: 'Existing Stations',
                                  ),
                                  SizedBox(height: 10),
                                  _MapLegendItem(
                                    asset: 'assets/icons/proposed_station.png',
                                    label: 'Proposed Stations',
                                  ),
                                  SizedBox(height: 10),
                                  _MapLegendItem(
                                    asset: 'assets/icons/high_priority.png',
                                    label: 'High Priority Area',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ],
                        )
                      else
                        const SizedBox(height: 300),
                      const SizedBox(height: 18),
                      const Text(
                        'Infrastructure Overview',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            StatisticCard(
                              value: '${vm.stationCount}',
                              label: 'Existing Stations',
                              icon: Icons.bolt,
                              color: green,
                            ),
                            SizedBox(width: 10),
                            StatisticCard(
                              value: '${vm.proposalCount}',
                              label: 'Proposed Stations',
                              icon: Icons.ev_station,
                              color: blue,
                            ),
                            SizedBox(width: 10),
                            StatisticCard(
                              value: '${vm.highPriorityAreaCount}',
                              label: 'High Priority Areas',
                              icon: Icons.insights,
                              color: Colors.orange,
                            ),
                            SizedBox(width: 10),
                            StatisticCard(
                              value: '${vm.communitySupportCount}',
                              label: 'Community Support',
                              icon: Icons.group_outlined,
                              color: Colors.deepPurple,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Quick Actions',
                        style: TextStyle(
                            fontSize: 23, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _action(
                            context,
                            Icons.add_circle_outline,
                            'New Proposal',
                            const NewProposalScreen(),
                          ),
                          _action(
                            context,
                            Icons.article_outlined,
                            'View Proposals',
                            const ProposalListScreen(),
                          ),
                          _action(
                            context,
                            Icons.pie_chart_outline,
                            'Gap Analysis',
                            const GapAnalysisScreen(),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
        },
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Widget _action(
          BuildContext context, IconData icon, String label, Widget page) =>
      SizedBox(
        width: 155,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(12)),
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          icon: Icon(icon, color: green),
          label: Text(label, style: const TextStyle(color: Color(0xFF101B40))),
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
          Image.asset(asset, width: 22, height: 22),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
}
