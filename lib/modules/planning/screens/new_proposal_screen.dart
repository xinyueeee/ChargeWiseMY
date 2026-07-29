import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class NewProposalScreen extends StatefulWidget {
  const NewProposalScreen({super.key});
  @override
  State<NewProposalScreen> createState() => _NewProposalScreenState();
}

class _NewProposalScreenState extends State<NewProposalScreen> {
  String demand = 'Medium';
  String area = 'Residential Area';
  final reason = TextEditingController();
  final address = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(
          title: const Text(
            'New Proposal',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
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
              'Submit a new charging station proposal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF5F6B82), fontSize: 17),
            ),
            const SizedBox(height: 20),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📍  1. Select Location',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 15),
                  const MapPanel(height: 240),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(55),
                    ),
                    onPressed: () {},
                    icon: const Icon(Icons.near_me, color: green),
                    label: const Text(
                      'Use Current Location',
                      style: TextStyle(color: green, fontSize: 17),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _field(
                    '📍  2. Address / Area',
                    'Enter address, location or area',
                    address,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🏢  3. Area Type',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        DropdownButton<String>(
                          isExpanded: true,
                          value: area,
                          items: [
                            'Residential Area',
                            'Commercial Area',
                            'Highway'
                          ]
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) => setState(() => area = v!),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📄  4. Reason for Proposal',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: reason,
                    maxLines: 5,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      hintText:
                          'Explain why this location is suitable for a new charging station...',
                      border: OutlineInputBorder(),
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
                    '📈  5. Expected Demand',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: ['Low', 'Medium', 'High']
                        .map(
                          (v) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: ChoiceChip(
                                label: Text(v),
                                selected: demand == v,
                                selectedColor: green.withValues(alpha: .2),
                                onSelected: (_) => setState(() => demand = v),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '🖼  6. Upload Photo (Optional)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 130,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: green.withValues(alpha: .35),
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload_outlined,
                            color: green, size: 42),
                        Text('Tap to upload photos of the proposed location'),
                        Text('JPG, PNG up to 5MB'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: green,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                final proposal = Proposal(
                  id: '',
                  city: address.text.trim().isEmpty
                      ? 'New Proposal Location'
                      : address.text.trim(),
                  description: reason.text,
                  supports: 0,
                  status: 'Pending',
                  area: area,
                  charger: 'AC Charger',
                  distance: 0,
                  demand: demand,
                );
                try {
                  await c.read<PlanningViewModel>().submitProposal(proposal);
                  if (!c.mounted) return;
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(
                        content: Text('Proposal submitted successfully')),
                  );
                } catch (_) {
                  if (!c.mounted) return;
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Unable to submit proposal. Check your Supabase policies.')),
                  );
                }
              },
              child: const Text(
                'Submit Proposal  ➤',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const FloatingBottomNav(),
      );
  Widget _field(String label, String hint, TextEditingController controller) =>
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );
}
