import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';

class AiPlanningScreen extends StatefulWidget {
  const AiPlanningScreen({
    super.key,
    required this.proposal,
  });

  final Proposal proposal;

  @override
  State<AiPlanningScreen> createState() => _AiPlanningScreenState();
}

class _AiPlanningScreenState extends State<AiPlanningScreen> {
  bool _updatingStatus = false;

  Proposal get proposal => widget.proposal;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<PlanningViewModel>();
    final recommendation = viewModel.recommendation(proposal);
    final suitable = recommendation == 'Suitable Location';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Planning Assessment',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 23),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: ListView(
          padding: planningPagePadding,
          children: [
            AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    backgroundColor: green,
                    child: Icon(Icons.ev_station, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposal.city,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: planningTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${proposal.displayedSupports} community supports',
                          style: const TextStyle(
                            color: planningMutedTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(child: StatusChip(proposal.status)),
                ],
              ),
            ),
            planningSectionGap,
            const PlanningSectionTitle(
              'Assessment summary',
              subtitle: 'Uses the submitted proposal and station proximity',
            ),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                children: [
                  _AssessmentRow(
                    'Nearest existing station',
                    '${proposal.distance.toStringAsFixed(1)} km',
                  ),
                  const Divider(height: 1),
                  _AssessmentRow('Expected usage', proposal.demand),
                  const Divider(height: 1),
                  _AssessmentRow(
                    'Community support',
                    '${proposal.displayedSupports}',
                  ),
                  const Divider(height: 1),
                  _AssessmentRow('Current status', proposal.status),
                ],
              ),
            ),
            planningSectionGap,
            const PlanningSectionTitle('Recommendation'),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        suitable
                            ? Icons.check_circle_outline
                            : Icons.fact_check_outlined,
                        color: suitable ? green : Colors.orange,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          recommendation,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color:
                                        suitable ? green : Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReasonLine(
                    'Nearest-station distance: '
                    '${proposal.distance.toStringAsFixed(1)} km',
                  ),
                  _ReasonLine(
                    'Submitted expected usage: ${proposal.demand}',
                  ),
                  _ReasonLine(
                    'Community support: ${proposal.displayedSupports}',
                  ),
                  const Divider(height: 24),
                  const Text(
                    'This is a transparent rule-based planning aid. It does '
                    'not predict population growth or future EV demand.',
                    style: TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            planningSectionGap,
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _updatingStatus
                        ? null
                        : () => _setStatus('Approved'),
                    icon: const Icon(Icons.check),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _updatingStatus
                        ? null
                        : () => _setStatus('Rejected'),
                    icon: _updatingStatus
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close),
                    label: Text(_updatingStatus ? 'Updating…' : 'Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Future<void> _setStatus(String status) async {
    setState(() => _updatingStatus = true);
    try {
      await context.read<PlanningViewModel>().setStatus(proposal, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proposal marked as $status.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Proposal status update failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update the proposal status.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }
}

class _AssessmentRow extends StatelessWidget {
  const _AssessmentRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: planningMutedTextColor),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.circle,
                size: 7,
                color: planningMutedTextColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(color: planningMutedTextColor),
              ),
            ),
          ],
        ),
      );
}
