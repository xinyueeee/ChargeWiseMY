import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'ai_planning_screen.dart';

class ProposalDetailsScreen extends StatelessWidget {
  const ProposalDetailsScreen({super.key, required this.proposal});
  final Proposal proposal;
  @override
  Widget build(BuildContext c) {
    final vm = c.watch<PlanningViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposal Details',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute(
                builder: (_) => AiPlanningScreen(proposal: proposal),
              ),
            ),
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      height: 85,
                      width: 85,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bolt, color: green, size: 48),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proposal.city,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Proposed on 2 Jun 2025',
                            style: TextStyle(
                              fontSize: 17,
                              color: Color(0xFF5F6B82),
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(proposal.status),
                  ],
                ),
                const Divider(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _metric('👥', '${proposal.displayedSupports}', 'Supports'),
                    _metric('📍', '${proposal.distance} km', 'Nearest Station'),
                    _metric('🏢', proposal.area, 'Area Type'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Location',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          MapPanel(
            height: 270,
            stations: vm.stations,
            proposals: vm.proposals,
            priorityAreas: vm.gaps,
          ),
          const SizedBox(height: 18),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Description',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 15),
                Text(
                  proposal.description,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color(0xFF5F6B82),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Additional Information',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const Divider(),
                _row('Area Type', proposal.area),
                _row('Expected Demand', proposal.demand),
                _row('Charger Type', proposal.charger),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: proposal.reaction == 0
                      ? () => vm.react(proposal, true)
                      : null,
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  label: Text('Support (${proposal.displayedSupports})'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: proposal.reaction == 0
                      ? () => vm.react(proposal, false)
                      : null,
                  icon: const Icon(Icons.thumb_down_alt_outlined),
                  label: const Text('Not suitable'),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Widget _metric(String i, String v, String l) => Column(
        children: [
          Text(i, style: const TextStyle(fontSize: 26)),
          Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(l, style: const TextStyle(color: Color(0xFF5F6B82))),
        ],
      );
  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                a,
                style: const TextStyle(color: Color(0xFF5F6B82), fontSize: 17),
              ),
            ),
            Text(b, style: const TextStyle(fontSize: 17)),
          ],
        ),
      );
}
