import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class GapAnalysisScreen extends StatelessWidget {
  const GapAnalysisScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final vm = c.watch<PlanningViewModel>();
    final gaps = vm.gaps;
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Identify infrastructure gaps and prioritize areas for new stations.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF5F6B82), fontSize: 17),
          ),
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
            children: const [
              StatisticCard(
                value: '24',
                label: 'Infrastructure Gaps Identified',
                icon: Icons.bolt,
                color: green,
              ),
              StatisticCard(
                value: '12',
                label: 'High Priority Areas',
                icon: Icons.location_on,
                color: blue,
              ),
              StatisticCard(
                value: '8.7 km',
                label: 'Average Distance',
                icon: Icons.bar_chart,
                color: Colors.orange,
              ),
              StatisticCard(
                value: '85.3K',
                label: 'EV Users Affected',
                icon: Icons.group,
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
            priorityAreas: vm.gaps,
          ),
          const SizedBox(height: 24),
          const Text(
            'Top Priority Gaps',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          ...gaps.asMap().entries.map(
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
                                '${e.value.priority} Priority • ${e.value.distance} km nearest station',
                              ),
                            ],
                          ),
                        ),
                        Text(e.value.users),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 16),
          const AppCard(
            child: ListTile(
              leading: Icon(Icons.lightbulb_outline, color: green),
              title: Text(
                'Insights',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Most gaps are concentrated in the northern and eastern regions. Prioritizing these areas can improve accessibility.',
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }
}
