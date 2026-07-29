import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class AiPlanningScreen extends StatelessWidget {
  const AiPlanningScreen({super.key, required this.proposal});
  final Proposal proposal;
  @override
  Widget build(BuildContext c) {
    final vm = c.watch<PlanningViewModel>();
    final suitable = vm.recommendation(proposal) == 'Suitable Location';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Infrastructure Planning',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 25),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          AppCard(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: green,
                child: Icon(Icons.bolt, color: Colors.white),
              ),
              title: Text(
                proposal.city,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Proposed on 2 Jun 2025\n👥  ${proposal.displayedSupports} Supports',
              ),
              trailing: StatusChip(proposal.status),
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Analysis Summary',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                _line('Nearest Existing Station', '${proposal.distance} km'),
                _line('Existing Stations Nearby', '2'),
                _line('Population Density', 'High'),
                _line('Expected Demand', proposal.demand),
                _line(
                  'Community Support',
                  '${proposal.displayedSupports} Votes',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Recommendation',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: green,
                      child: Icon(Icons.bolt, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      vm.recommendation(proposal),
                      style: const TextStyle(
                        fontSize: 27,
                        color: green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 15),
                  child: Text(
                    '★★★★★',
                    style: TextStyle(fontSize: 32, color: Colors.amber),
                  ),
                ),
                const Divider(),
                const Text(
                  'Reason',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '• Low charging coverage in this area\n• High and growing EV population\n• Strong community support\n• Good road accessibility and connectivity',
                  style: TextStyle(
                    fontSize: 17,
                    height: 1.8,
                    color: Color(0xFF5F6B82),
                  ),
                ),
                const Divider(height: 30),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recommendation\n',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                    Text(
                      suitable ? 'Approve Proposal' : 'Needs review',
                      style: const TextStyle(
                        color: green,
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => vm.setStatus(proposal, 'Approved'),
                        style: ElevatedButton.styleFrom(backgroundColor: green),
                        child: const Text(
                          '✓  Approve',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => vm.setStatus(proposal, 'Rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('✕  Reject'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Text(
                a,
                style: const TextStyle(fontSize: 18, color: Color(0xFF5F6B82)),
              ),
            ),
            Text(
              b,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
}
