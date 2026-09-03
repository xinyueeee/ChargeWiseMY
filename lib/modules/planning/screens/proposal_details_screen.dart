import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../services/proposal_location_service.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../widgets/planning_destination_bottom_nav.dart';
import '../widgets/proposal_photo_widgets.dart';
import '../widgets/proposal_response_widgets.dart';
import 'new_proposal_screen.dart';
import 'proposal_location_map_screen.dart';

class ProposalDetailsScreen extends StatefulWidget {
  const ProposalDetailsScreen({super.key, required this.proposal});

  final Proposal proposal;

  @override
  State<ProposalDetailsScreen> createState() => _ProposalDetailsScreenState();
}

class _ProposalDetailsScreenState extends State<ProposalDetailsScreen> {
  bool _deleting = false;
  bool _reacting = false;
  ProposalReaction? _pendingReaction;

  Proposal _currentProposal(PlanningViewModel viewModel) =>
      viewModel.proposalById(widget.proposal.id) ?? widget.proposal;

  @override
  Widget build(BuildContext context) {
    return Consumer<PlanningViewModel>(
      builder: (context, viewModel, _) {
        final proposal = _currentProposal(viewModel);
        final owned = viewModel.ownsProposal(proposal);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              owned ? 'My Proposal' : 'Community Proposal',
              style: planningAppBarTitleStyle,
            ),
            centerTitle: true,
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: Colors.black,
          ),
          body: DriverNavigationShell(
            config: planningDriverNavConfig(context),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final landscape = MediaQuery.orientationOf(context) ==
                      Orientation.landscape;
                  final wide = constraints.maxWidth >= 900 ||
                      (landscape && constraints.maxWidth >= 650);
                  final primary = _primaryContent(proposal, owned);
                  final actions = _actionContent(proposal, owned);
                  if (!wide) {
                    return ListView(
                      padding: planningPagePadding,
                      children: [
                        _ProposalIdentity(proposal: proposal, owned: owned),
                        const SizedBox(height: 12),
                        ...actions,
                        planningSectionGap,
                        ...primary,
                      ],
                    );
                  }
                  return Padding(
                    padding: planningPagePadding,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: ListView(
                            children: [
                              _ProposalIdentity(
                                  proposal: proposal, owned: owned),
                              const SizedBox(height: 12),
                              ...primary,
                            ],
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          flex: 4,
                          child: ListView(children: actions),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          bottomNavigationBar:
              planningDriverNavConfig(context).bottomBarFor(context),
        );
      },
    );
  }

  List<Widget> _primaryContent(Proposal proposal, bool owned) => [
        if (owned && proposal.sitePhotoPath != null) ...[
          _SectionLabel(Icons.photo_camera_outlined, 'Site Photo'),
          const SizedBox(height: 8),
          AppCard(
            padding: const EdgeInsets.all(10),
            child: ProposalSitePhoto(
              storagePath: proposal.sitePhotoPath!,
              height: 180,
            ),
          ),
          planningSectionGap,
        ],
        _SectionLabel(Icons.description_outlined, 'Proposal Information'),
        const SizedBox(height: 8),
        AppCard(
          child: Text(
            proposal.description.trim().isEmpty
                ? 'No description was provided.'
                : proposal.description,
            style: const TextStyle(
              color: planningMutedTextColor,
              height: 1.45,
            ),
          ),
        ),
        if (proposal.isApproved) ...[
          const SizedBox(height: 12),
          const _LifecycleNotice(
            icon: Icons.verified_outlined,
            color: green,
            title: 'Approved for planning consideration',
            message:
                'Approved by Admin for planning consideration. This remains a community proposal and does not count as existing charging infrastructure.',
          ),
        ] else if (proposal.isRejected) ...[
          const SizedBox(height: 12),
          const _LifecycleNotice(
            icon: Icons.lock_outline,
            color: planningMutedTextColor,
            title: 'Proposal closed',
            message:
                'This rejected proposal is retained as read-only planning history.',
          ),
        ],
        planningSectionGap,
        _SectionLabel(Icons.location_on_outlined, 'Location'),
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                proposal.locationLabel.trim().isEmpty
                    ? 'Selected proposal location'
                    : proposal.locationLabel,
                style: const TextStyle(
                  color: planningTextColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _InformationRow('State', proposal.state ?? 'Unavailable'),
              _InformationRow(
                  'Nearest town', proposal.nearestTown ?? 'Unavailable'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    proposal.latitude == null || proposal.longitude == null
                        ? null
                        : () => _viewOnMap(proposal),
                icon: const Icon(Icons.map_outlined),
                label: const Text('View on Map'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: Theme.of(context).copyWith(
              listTileTheme: const ListTileThemeData(
                horizontalTitleGap: 8,
                minLeadingWidth: 0,
              ),
            ),
            child: ExpansionTile(
              leading:
                  const Icon(Icons.tune_outlined, size: 19, color: green),
              title: const Text(
                'Additional Information',
                style: TextStyle(
                  color: planningTextColor,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                _InformationRow('Charger type', proposal.charger),
                _InformationRow('Expected usage', proposal.demand),
                _InformationRow('Nearest Existing location',
                    '${proposal.distance.toStringAsFixed(1)} km'),
                if (proposal.latitude != null && proposal.longitude != null)
                  _InformationRow(
                    'Coordinates',
                    '${proposal.latitude!.toStringAsFixed(6)}, '
                        '${proposal.longitude!.toStringAsFixed(6)}',
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ];

  List<Widget> _actionContent(Proposal proposal, bool owned) => [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.insights_outlined, color: green),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Overview',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  StatusChip(proposal.status),
                ],
              ),
              const SizedBox(height: 12),
              _InformationRow('Expected usage', proposal.demand),
              _InformationRow('Submitted', _formatDate(proposal.createdAt)),
              const Divider(height: 18),
              const Text('Community Response',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              CommunityResponseSummary(proposal: proposal),
            ],
          ),
        ),
        if (!owned) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.how_to_vote_outlined, color: green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Your Response',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose an option, switch it at any time, or tap the selected option again to clear it.',
                  style: TextStyle(color: planningMutedTextColor, height: 1.35),
                ),
                const SizedBox(height: 12),
                ProposalReactionButtons(
                  selected: _reacting && _pendingReaction != null
                      ? _pendingReaction
                      : proposal.currentUserReaction,
                  busy: _reacting,
                  onChanged: (reaction) => _setReaction(proposal, reaction),
                ),
              ],
            ),
          ),
        ],
        if (owned && proposal.canOwnerEdit && proposal.canOwnerDelete) ...[
          const SizedBox(height: 12),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.manage_accounts_outlined, color: green),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Manage Proposal',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ResponsiveButtonPair(
                  first: OutlinedButton.icon(
                    onPressed: _deleting ? null : () => _edit(proposal),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                  second: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed:
                        _deleting ? null : () => _confirmDelete(proposal),
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
        ] else if (owned) ...[
          const SizedBox(height: 12),
          const _LifecycleNotice(
            icon: Icons.lock_outline,
            color: planningMutedTextColor,
            title: 'Read-only proposal',
            message:
                'Approved and rejected proposals can be viewed but can no longer be edited or deleted.',
          ),
        ],
        const SizedBox(height: 24),
      ];

  Future<void> _setReaction(
    Proposal proposal,
    ProposalReaction? reaction,
  ) async {
    if (_reacting) return;
    setState(() {
      _reacting = true;
      _pendingReaction = reaction;
    });
    try {
      await context.read<PlanningViewModel>().setReaction(proposal, reaction);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reaction == null
                ? 'Your response was cleared.'
                : reaction == ProposalReaction.support
                    ? 'Support recorded.'
                    : 'Not Support recorded.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Proposal reaction update failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update your response. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reacting = false;
          _pendingReaction = null;
        });
      }
    }
  }

  Future<void> _viewOnMap(Proposal proposal) async {
    final latitude = proposal.latitude;
    final longitude = proposal.longitude;
    if (latitude == null || longitude == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ProposalLocationMapScreen(
          initialSelection: ProposalLocationSelection(
            latitude: latitude,
            longitude: longitude,
            state: proposal.state ?? 'Malaysia',
            nearestTown: proposal.nearestTown ?? 'Selected location',
            locationLabel: proposal.locationLabel.isEmpty
                ? 'Selected proposal location'
                : proposal.locationLabel,
          ),
          readOnly: true,
        ),
      ),
    );
  }

  Future<void> _edit(Proposal proposal) async {
    if (!proposal.canOwnerEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This proposal is read-only.')),
      );
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => NewProposalScreen(proposal: proposal),
      ),
    );
    if (changed == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete(Proposal proposal) async {
    if (!proposal.canOwnerDelete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This proposal can no longer be deleted.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
        title: const Text('Delete proposal?'),
        content: const Text(
          'This permanently removes your proposal and its community responses.',
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
      await context.read<PlanningViewModel>().deleteProposal(proposal);
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

class _LifecycleNotice extends StatelessWidget {
  const _LifecycleNotice({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProposalIdentity extends StatelessWidget {
  const _ProposalIdentity({required this.proposal, required this.owned});
  final Proposal proposal;
  final bool owned;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: green.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                owned ? Icons.assignment_ind_outlined : Icons.groups_outlined,
                color: green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    proposal.city,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: planningTextColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 16, color: planningMutedTextColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _location(proposal),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: planningMutedTextColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    owned ? 'Submitted by you' : 'Community proposal',
                    style: const TextStyle(
                        color: planningMutedTextColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: StatusChip(proposal.status)),
          ],
        ),
      );

  static String _location(Proposal proposal) {
    final location = [proposal.nearestTown, proposal.state]
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .join(', ');
    return location.isEmpty ? proposal.locationLabel : location;
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 19, color: green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: planningTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      );
}

class _ResponsiveButtonPair extends StatelessWidget {
  const _ResponsiveButtonPair({required this.first, required this.second});
  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.25) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 10), second],
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
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 340 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.25) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: planningMutedTextColor, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(value,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(color: planningMutedTextColor)),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(value,
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        ),
      );
}

String _formatDate(DateTime? date) {
  if (date == null) return 'Unavailable';
  const months = [
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
    'Dec'
  ];
  final local = date.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}
