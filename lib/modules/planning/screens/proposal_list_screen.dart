import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../widgets/planning_destination_bottom_nav.dart';
import '../widgets/planning_widgets.dart';
import '../widgets/proposal_response_widgets.dart';
import 'new_proposal_screen.dart';
import 'proposal_details_screen.dart';

enum _ProposalMode { mine, community }

enum _ProposalBucket { active, approved, closed }

class ProposalListScreen extends StatefulWidget {
  const ProposalListScreen({super.key});

  @override
  State<ProposalListScreen> createState() => _ProposalListScreenState();
}

class _ProposalListScreenState extends State<ProposalListScreen> {
  final TextEditingController _searchController = TextEditingController();
  _ProposalMode _mode = _ProposalMode.mine;
  _ProposalBucket _bucket = _ProposalBucket.active;
  String _query = '';
  String _state = 'All states';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Proposals', style: planningAppBarTitleStyle),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          actions: [
            IconButton(
              tooltip: 'Create proposal',
              onPressed: _openNewProposal,
              icon: const Icon(Icons.add_location_alt_outlined),
            ),
          ],
        ),
        body: DriverNavigationShell(
          config: planningDriverNavConfig(context),
          child: Consumer<PlanningViewModel>(
            builder: (context, viewModel, _) {
              if (viewModel.loading) {
                return const PlanningLoadingState(
                    message: 'Loading proposals…');
              }
              if (viewModel.errorMessage != null) {
                return PlanningErrorState(
                  message: viewModel.errorMessage!,
                  onRetry: viewModel.load,
                );
              }
              final source = _mode == _ProposalMode.mine
                  ? viewModel.myProposals
                  : viewModel.communityProposals;
              final states = <String>{
                for (final proposal in viewModel.communityProposals)
                  if (proposal.state?.trim().isNotEmpty == true)
                    proposal.state!,
              }.toList()
                ..sort();
              if (_state != 'All states' && !states.contains(_state)) {
                _state = 'All states';
              }
              final visible = _filtered(source);
              return SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final sidePadding =
                        math.max(16.0, (constraints.maxWidth - 920) / 2);
                    return CustomScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        SliverToBoxAdapter(
                          child: _ProposalListHeader(
                            mode: _mode,
                            bucket: _bucket,
                            queryController: _searchController,
                            query: _query,
                            state: _state,
                            states: states,
                            resultCount: visible.length,
                            onModeChanged: (value) => setState(() {
                              _mode = value;
                              _bucket = _ProposalBucket.active;
                              _state = 'All states';
                            }),
                            onBucketChanged: (value) =>
                                setState(() => _bucket = value),
                            onQueryChanged: (value) =>
                                setState(() => _query = value),
                            onClearQuery: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            onStateChanged: (value) =>
                                setState(() => _state = value),
                          ),
                        ),
                        if (visible.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: _emptyState(source),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              sidePadding,
                              4,
                              sidePadding,
                              24,
                            ),
                            sliver: SliverList.separated(
                              itemCount: visible.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final proposal = visible[index];
                                return _ProposalListCard(
                                  proposal: proposal,
                                  owned: _mode == _ProposalMode.mine,
                                  onTap: () => _openDetails(proposal),
                                  onEdit: _mode == _ProposalMode.mine &&
                                          viewModel.canOwnerEdit(proposal)
                                      ? () => _edit(proposal)
                                      : null,
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
        bottomNavigationBar:
            planningDriverNavConfig(context).bottomBarFor(context),
      );

  List<Proposal> _filtered(List<Proposal> source) {
    final normalizedQuery = _query.trim().toLowerCase();
    final result = source.where((proposal) {
      final matchesBucket = switch (_bucket) {
        _ProposalBucket.active => proposal.isActive,
        _ProposalBucket.approved => proposal.isApproved,
        _ProposalBucket.closed => proposal.isRejected,
      };
      final matchesState = _mode == _ProposalMode.mine ||
          _state == 'All states' ||
          proposal.state == _state;
      final matchesSearch = normalizedQuery.isEmpty ||
          proposal.city.toLowerCase().contains(normalizedQuery) ||
          proposal.locationLabel.toLowerCase().contains(normalizedQuery) ||
          (proposal.state?.toLowerCase().contains(normalizedQuery) ?? false) ||
          (proposal.nearestTown?.toLowerCase().contains(normalizedQuery) ??
              false);
      return matchesBucket && matchesState && matchesSearch;
    }).toList()
      ..sort(Proposal.compareForReviewQueue);
    return List<Proposal>.unmodifiable(result);
  }

  Widget _emptyState(List<Proposal> source) {
    final hasBucketRecords = source.any((proposal) => switch (_bucket) {
          _ProposalBucket.active => proposal.isActive,
          _ProposalBucket.approved => proposal.isApproved,
          _ProposalBucket.closed => proposal.isRejected,
        });
    if (hasBucketRecords) {
      return const PlanningEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No proposals match these filters',
        message: 'Change the search text or state filter and try again.',
      );
    }
    final title = switch ((_mode, _bucket)) {
      (_ProposalMode.mine, _ProposalBucket.active) =>
        'You have no active proposals.',
      (_ProposalMode.mine, _ProposalBucket.approved) =>
        'You have no approved proposals yet.',
      (_ProposalMode.mine, _ProposalBucket.closed) =>
        'You have no rejected proposals.',
      (_ProposalMode.community, _ProposalBucket.active) =>
        'No active community proposals right now.',
      (_ProposalMode.community, _ProposalBucket.approved) =>
        'No approved community proposals yet.',
      (_ProposalMode.community, _ProposalBucket.closed) =>
        'No closed proposals.',
    };
    return PlanningEmptyState(
      icon: _mode == _ProposalMode.mine
          ? Icons.assignment_outlined
          : Icons.groups_outlined,
      title: title,
      message: _bucket == _ProposalBucket.active
          ? 'New proposals will appear here as they enter review.'
          : 'Final-status proposals remain available here for reference.',
      action: _mode == _ProposalMode.mine && _bucket == _ProposalBucket.active
          ? ElevatedButton.icon(
              onPressed: _openNewProposal,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Create Proposal'),
            )
          : null,
    );
  }

  Future<void> _openNewProposal() => Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(builder: (_) => const NewProposalScreen()),
      );

  Future<void> _openDetails(Proposal proposal) => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ProposalDetailsScreen(proposal: proposal),
        ),
      );

  Future<void> _edit(Proposal proposal) => Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => NewProposalScreen(proposal: proposal),
        ),
      );
}

class _ProposalListHeader extends StatelessWidget {
  const _ProposalListHeader({
    required this.mode,
    required this.bucket,
    required this.queryController,
    required this.query,
    required this.state,
    required this.states,
    required this.resultCount,
    required this.onModeChanged,
    required this.onBucketChanged,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onStateChanged,
  });

  final _ProposalMode mode;
  final _ProposalBucket bucket;
  final TextEditingController queryController;
  final String query;
  final String state;
  final List<String> states;
  final int resultCount;
  final ValueChanged<_ProposalMode> onModeChanged;
  final ValueChanged<_ProposalBucket> onBucketChanged;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onStateChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ModeChip(
                  label: 'My Proposals',
                  icon: Icons.person_outline,
                  selected: mode == _ProposalMode.mine,
                  onSelected: () => onModeChanged(_ProposalMode.mine),
                ),
                _ModeChip(
                  label: 'Community',
                  icon: Icons.groups_outlined,
                  selected: mode == _ProposalMode.community,
                  onSelected: () => onModeChanged(_ProposalMode.community),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BucketChip(
                    label: 'Active',
                    selected: bucket == _ProposalBucket.active,
                    onSelected: () => onBucketChanged(_ProposalBucket.active),
                  ),
                  const SizedBox(width: 7),
                  _BucketChip(
                    label: 'Approved',
                    selected: bucket == _ProposalBucket.approved,
                    onSelected: () => onBucketChanged(_ProposalBucket.approved),
                  ),
                  const SizedBox(width: 7),
                  _BucketChip(
                    label:
                        mode == _ProposalMode.community ? 'Closed' : 'Rejected',
                    selected: bucket == _ProposalBucket.closed,
                    onSelected: () => onBucketChanged(_ProposalBucket.closed),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final search = TextField(
                  controller: queryController,
                  textInputAction: TextInputAction.search,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: mode == _ProposalMode.mine
                        ? 'Search my proposals'
                        : 'Search community proposals',
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: onClearQuery,
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                );
                if (mode == _ProposalMode.mine) return search;
                final stateFilter = DropdownButtonFormField<String>(
                  initialValue: state,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'All states',
                      child: Text('All states'),
                    ),
                    for (final item in states)
                      DropdownMenuItem(
                        value: item,
                        child: Text(item, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onStateChanged(value);
                  },
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 7),
                      stateFilter,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    SizedBox(width: 190, child: stateFilter),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              '$resultCount proposal${resultCount == 1 ? '' : 's'}',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: planningMutedTextColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        avatar: Icon(icon, size: 18, color: selected ? green : null),
        label: Text(label),
        selected: selected,
        selectedColor: green.withValues(alpha: .12),
        onSelected: (_) => onSelected(),
      );
}

class _BucketChip extends StatelessWidget {
  const _BucketChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: green.withValues(alpha: .12),
        onSelected: (_) => onSelected(),
      );
}

class _ProposalListCard extends StatelessWidget {
  const _ProposalListCard({
    required this.proposal,
    required this.owned,
    required this.onTap,
    this.onEdit,
  });
  final Proposal proposal;
  final bool owned;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => AppCard(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      owned
                          ? Icons.assignment_ind_outlined
                          : Icons.groups_outlined,
                      color:
                          proposal.isRejected ? planningMutedTextColor : green,
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        proposal.city,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: planningTextColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: StatusChip(proposal.status)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: planningMutedTextColor,
                    ),
                    const SizedBox(width: 5),
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
                const SizedBox(height: 9),
                CommunityResponseSummary(proposal: proposal, compact: true),
                const Divider(height: 20),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text(
                      'Submitted ${_formatDate(proposal.createdAt)}',
                      style: const TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 12,
                      ),
                    ),
                    if (owned && proposal.isTerminal) const _ReadOnlyLabel(),
                    if (onEdit != null)
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_outlined, size: 15, color: green),
                              SizedBox(width: 4),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  static String _location(Proposal proposal) {
    final value = [proposal.nearestTown, proposal.state]
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .join(', ');
    return value.isEmpty ? proposal.locationLabel : value;
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return 'date unavailable';
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
}

class _ReadOnlyLabel extends StatelessWidget {
  const _ReadOnlyLabel();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 14, color: planningMutedTextColor),
          SizedBox(width: 4),
          Text(
            'Read-only',
            style: TextStyle(
              color: planningMutedTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
}
