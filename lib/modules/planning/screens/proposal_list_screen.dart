import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'proposal_details_screen.dart';

class ProposalListScreen extends StatelessWidget {
  const ProposalListScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final vm = c.watch<PlanningViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposal List',
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
            'Browse and support community proposals.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, color: Color(0xFF5F6B82)),
          ),
          const SizedBox(height: 22),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search proposal...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('⚑  Showing: All Status', style: TextStyle(fontSize: 16)),
              Text(
                'Sort by: Most Supported',
                style: TextStyle(color: green, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...vm.proposals.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: ProposalCard(
                proposal: p,
                onDetails: () => Navigator.push(
                  c,
                  MaterialPageRoute(
                    builder: (_) => ProposalDetailsScreen(proposal: p),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }
}
