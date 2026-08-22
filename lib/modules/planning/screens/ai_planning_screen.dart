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
  String? _pendingStatus;

  bool get _updatingStatus => _pendingStatus != null;

  Proposal get proposal => widget.proposal;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<PlanningViewModel>();
    final ruleRecommendation = viewModel.recommendation(proposal);
    final suitable = ruleRecommendation == 'Suitable Location';
    final rejected = proposal.status.toLowerCase() == 'rejected';
    final approved = proposal.status.toLowerCase() == 'approved';
    final recommended = !rejected && (suitable || approved);
    final assessmentOutcome = rejected
        ? 'Not Recommended'
        : recommended
            ? 'Recommended'
            : 'Further Review Required';
    final coverageSeverity = proposal.distance >= 10
        ? 'High'
        : proposal.distance >= 5
            ? 'Moderate'
            : 'Low';
    final priority = suitable
        ? 'High'
        : proposal.distance >= 5 || proposal.demand == 'High'
            ? 'Medium'
            : 'Low';
    final nearbyAvailability = proposal.distance >= 10
        ? 'Limited nearby coverage'
        : proposal.distance >= 5
            ? 'Moderate nearby coverage'
            : 'Existing charging location nearby';
    final settlementRelevance = proposal.nearestTown == null
        ? 'Settlement reference unavailable'
        : 'Near ${proposal.nearestTown}, ${proposal.state ?? 'Malaysia'}';
    final nextStep = rejected
        ? 'No additional charging station is currently recommended under the current planning rules.'
        : recommended
            ? 'Proceed to a detailed feasibility study before implementation.'
            : 'Keep the proposal under review and collect detailed site-feasibility evidence.';
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Planning Assessment',
          style: planningAppBarTitleStyle,
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
                    'Nearest charging location',
                    '${proposal.distance.toStringAsFixed(1)} km',
                  ),
                  const Divider(height: 1),
                  _AssessmentRow('Coverage severity', coverageSeverity),
                  const Divider(height: 1),
                  _AssessmentRow('Planning priority', priority),
                  const Divider(height: 1),
                  _AssessmentRow('Nearby availability', nearbyAvailability),
                  const Divider(height: 1),
                  _AssessmentRow('Settlement relevance', settlementRelevance),
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
                        recommended
                            ? Icons.check_circle_outline
                            : Icons.fact_check_outlined,
                        color: recommended ? green : Colors.orange,
                        size: 30,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          assessmentOutcome,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color:
                                        recommended ? green : Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReasonLine('Coverage severity is $coverageSeverity.'),
                  _ReasonLine(
                    'The nearest recorded charging station is '
                    '${proposal.distance.toStringAsFixed(1)} km away.',
                  ),
                  _ReasonLine('$nearbyAvailability.'),
                  _ReasonLine('$settlementRelevance.'),
                  _ReasonLine(
                    'Submitted expected usage: ${proposal.demand}',
                  ),
                  _ReasonLine(
                    'Community support: ${proposal.displayedSupports}',
                  ),
                  _ReasonLine('Current proposal status: ${proposal.status}.'),
                  const Divider(height: 20),
                  Text(
                    'Priority: $priority',
                    style: const TextStyle(
                      color: planningTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    nextStep,
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      height: 1.4,
                    ),
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
            LayoutBuilder(
              builder: (context, constraints) {
                final approveButton = ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _updatingStatus
                        ? null
                        : () => _setStatus('Approved'),
                    icon: _pendingStatus == 'Approved'
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _pendingStatus == 'Approved' ? 'Approving…' : 'Approve',
                    ),
                  );
                final rejectButton = OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _updatingStatus
                        ? null
                        : () => _setStatus('Rejected'),
                    icon: _pendingStatus == 'Rejected'
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close),
                    label: Text(
                      _pendingStatus == 'Rejected' ? 'Rejecting…' : 'Reject',
                    ),
                  );
                final vertical = constraints.maxWidth < 360 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.25;
                if (vertical) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      approveButton,
                      const SizedBox(height: 10),
                      rejectButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: approveButton),
                    const SizedBox(width: 10),
                    Expanded(child: rejectButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Future<void> _setStatus(String status) async {
    setState(() => _pendingStatus = status);
    try {
      await context.read<PlanningViewModel>().setStatus(proposal, status);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assessment completed. Proposal marked as $status.'),
        ),
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
      if (mounted) setState(() => _pendingStatus = null);
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
