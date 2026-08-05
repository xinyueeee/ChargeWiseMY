import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../services/proposal_location_service.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'ai_planning_screen.dart';
import 'new_proposal_screen.dart';
import 'proposal_location_map_screen.dart';

class ProposalDetailsScreen extends StatefulWidget {
  const ProposalDetailsScreen({
    super.key,
    required this.proposal,
  });

  final Proposal proposal;

  @override
  State<ProposalDetailsScreen> createState() =>
      _ProposalDetailsScreenState();
}

class _ProposalDetailsScreenState extends State<ProposalDetailsScreen> {
  bool _deleting = false;
  bool? _pendingReaction;

  bool get _reacting => _pendingReaction != null;

  Proposal get proposal => widget.proposal;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposal Details',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'Open planning assessment',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => AiPlanningScreen(proposal: proposal),
              ),
            ),
            icon: const Icon(Icons.analytics_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: planningPagePadding,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 52,
                        width: 52,
                        decoration: BoxDecoration(
                          color: green.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.ev_station,
                          color: green,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              proposal.city,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: planningTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Community charging-station proposal',
                              style: TextStyle(
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
                  const Divider(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth =
                          constraints.maxWidth < 390
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 16) / 3;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _MetricTile(
                            width: itemWidth,
                            icon: Icons.group_outlined,
                            value: '${proposal.displayedSupports}',
                            label: 'Supports',
                          ),
                          _MetricTile(
                            width: itemWidth,
                            icon: Icons.route_outlined,
                            value: '${proposal.distance.toStringAsFixed(1)} km',
                            label: 'Nearest station',
                          ),
                          _MetricTile(
                            width: itemWidth,
                            icon: Icons.apartment_outlined,
                            value: proposal.area,
                            label: 'Area type',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            planningSectionGap,
            const PlanningSectionTitle('Location'),
            const SizedBox(height: 10),
            if (proposal.latitude == null || proposal.longitude == null)
              const PlanningEmptyState(
                icon: Icons.location_off_outlined,
                title: 'Location unavailable',
                message:
                    'This proposal does not contain valid map coordinates.',
              )
            else
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      proposal.locationLabel.isEmpty
                          ? 'Selected proposal location'
                          : proposal.locationLabel,
                      style: const TextStyle(
                        color: planningTextColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _InformationRow('State', proposal.state ?? 'Unavailable'),
                    const Divider(height: 1),
                    _InformationRow(
                      'Nearest town',
                      proposal.nearestTown ?? 'Unavailable',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _viewOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('View on Map'),
                    ),
                  ],
                ),
              ),
            planningSectionGap,
            const PlanningSectionTitle('Description'),
            const SizedBox(height: 10),
            AppCard(
              child: Text(
                proposal.description.trim().isEmpty
                    ? 'No description was provided.'
                    : proposal.description,
                style: const TextStyle(
                  color: planningMutedTextColor,
                  height: 1.5,
                ),
              ),
            ),
            planningSectionGap,
            const PlanningSectionTitle('Additional information'),
            const SizedBox(height: 10),
            AppCard(
              child: Column(
                children: [
                  _InformationRow('Status', proposal.status),
                  const Divider(height: 1),
                  _InformationRow('Created', _formatDate(proposal.createdAt)),
                  const Divider(height: 1),
                  _InformationRow('Created by', proposal.createdBy),
                  const Divider(height: 1),
                  _InformationRow('Expected usage', proposal.demand),
                  const Divider(height: 1),
                  _InformationRow('Charger type', proposal.charger),
                ],
              ),
            ),
            if (proposal.latitude != null && proposal.longitude != null) ...[
              const SizedBox(height: 10),
              AppCard(
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  leading: const Icon(Icons.code_outlined, color: green),
                  title: const Text(
                    'Technical Information',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  children: [
                    _InformationRow(
                      'Coordinates',
                      '${proposal.latitude!.toStringAsFixed(6)}, '
                          '${proposal.longitude!.toStringAsFixed(6)}',
                    ),
                  ],
                ),
              ),
            ],
            planningSectionGap,
            _ResponsiveButtonPair(
              first: OutlinedButton.icon(
                    onPressed: proposal.reaction == 0 && !_reacting
                        ? () => _react(like: true)
                        : null,
                    icon: _pendingReaction == true
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.thumb_up_alt_outlined),
                    label: Text(
                      _pendingReaction == true ? 'Saving…' : 'Support',
                    ),
                  ),
              second: OutlinedButton.icon(
                    onPressed: proposal.reaction == 0 && !_reacting
                        ? () => _react(like: false)
                        : null,
                    icon: _pendingReaction == false
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.thumb_down_alt_outlined),
                    label: Text(
                      _pendingReaction == false ? 'Saving…' : 'Not suitable',
                    ),
                  ),
            ),
            if (proposal.reaction != 0) ...[
              const SizedBox(height: 8),
              const Text(
                'Your feedback has been recorded for this proposal.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: planningMutedTextColor,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _ResponsiveButtonPair(
              first: OutlinedButton.icon(
                    onPressed: _deleting ? null : _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
              second: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: _deleting ? null : _confirmDelete,
                    icon: _deleting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline),
                    label: Text(_deleting ? 'Deleting…' : 'Delete'),
                  ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Future<void> _viewOnMap() async {
    final latitude = proposal.latitude;
    final longitude = proposal.longitude;
    if (latitude == null || longitude == null) return;
    final selection = ProposalLocationSelection(
      latitude: latitude,
      longitude: longitude,
      state: proposal.state ?? 'Malaysia',
      nearestTown: proposal.nearestTown ?? 'Selected location',
      locationLabel: proposal.locationLabel.isEmpty
          ? 'Selected proposal location'
          : proposal.locationLabel,
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProposalLocationMapScreen(
          initialSelection: selection,
          readOnly: true,
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unavailable';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = date.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year}';
  }

  Future<void> _react({required bool like}) async {
    setState(() => _pendingReaction = like);
    try {
      await context.read<PlanningViewModel>().react(proposal, like);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            like ? 'Support recorded.' : 'Feedback recorded.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Proposal reaction failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save your feedback. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _pendingReaction = null);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => NewProposalScreen(proposal: proposal),
      ),
    );
    if (changed == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text('Delete Proposal?'),
        content: Text(
          '“${proposal.city}” will be removed permanently. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await context.read<PlanningViewModel>().deleteProposal(proposal.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Proposal deleted.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Proposal deletion failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete the proposal. Please try again.'),
        ),
      );
    }
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Column(
          children: [
            Icon(icon, size: 22, color: green),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: planningMutedTextColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class _ResponsiveButtonPair extends StatelessWidget {
  const _ResponsiveButtonPair({
    required this.first,
    required this.second,
  });

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final useVerticalLayout = constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.25;
          if (useVerticalLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                first,
                const SizedBox(height: 10),
                second,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: first),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          );
        },
      );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
