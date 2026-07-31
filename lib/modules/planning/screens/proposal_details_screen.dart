import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'ai_planning_screen.dart';
import 'new_proposal_screen.dart';

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

class _ProposalDetailsScreenState extends State<ProposalDetailsScreen>
    with RouteAware {
  late final List<Proposal> _mapProposals;
  PageRoute<dynamic>? _subscribedRoute;
  bool _mapMounted = true;
  bool _deleting = false;
  bool _reacting = false;

  Proposal get proposal => widget.proposal;

  @override
  void initState() {
    super.initState();
    _mapProposals = proposal.latitude == null || proposal.longitude == null
        ? const <Proposal>[]
        : List<Proposal>.unmodifiable([proposal]);
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
    if (_mapMounted && mounted) {
      setState(() => _mapMounted = false);
    }
  }

  @override
  void didPopNext() {
    if (!_mapMounted && mounted) {
      setState(() => _mapMounted = true);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposal Details',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
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
            if (proposal.latitude != null &&
                proposal.longitude != null &&
                _mapMounted)
              MapPanel(
                height: 230,
                proposals: _mapProposals,
                initialTarget: LatLng(
                  proposal.latitude!,
                  proposal.longitude!,
                ),
                initialZoom: 13,
              )
            else if (proposal.latitude == null ||
                proposal.longitude == null)
              const PlanningEmptyState(
                icon: Icons.location_off_outlined,
                title: 'Location unavailable',
                message:
                    'This proposal does not contain valid map coordinates.',
              ),
            if (!_mapMounted) const SizedBox(height: 230),
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
                  _InformationRow('Expected usage', proposal.demand),
                  const Divider(height: 1),
                  _InformationRow('Charger type', proposal.charger),
                  if (proposal.latitude != null &&
                      proposal.longitude != null) ...[
                    const Divider(height: 1),
                    _InformationRow(
                      'Coordinates',
                      '${proposal.latitude!.toStringAsFixed(6)}, '
                          '${proposal.longitude!.toStringAsFixed(6)}',
                    ),
                  ],
                ],
              ),
            ),
            planningSectionGap,
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: proposal.reaction == 0 && !_reacting
                        ? () => _react(like: true)
                        : null,
                    icon: const Icon(Icons.thumb_up_alt_outlined),
                    label: Text(
                      _reacting ? 'Saving…' : 'Support',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: proposal.reaction == 0 && !_reacting
                        ? () => _react(like: false)
                        : null,
                    icon: const Icon(Icons.thumb_down_alt_outlined),
                    label: const Text('Not suitable'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _deleting ? null : _edit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
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
          ],
        ),
      ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Future<void> _react({required bool like}) async {
    setState(() => _reacting = true);
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
      if (mounted) setState(() => _reacting = false);
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
        title: const Text('Delete proposal?'),
        content: Text(
          'This permanently removes the proposal for ${proposal.city}. '
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
        const SnackBar(content: Text('Proposal deleted.')),
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
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
