import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/proposal.dart';
import '../../widgets/planning_widgets.dart';
import '../../widgets/proposal_response_widgets.dart';
import '../models/proposal_assessment.dart';
import '../viewmodels/admin_planning_viewmodel.dart';
import 'admin_proposal_details_screen.dart';

class AdminProposalListScreen extends StatefulWidget {
  const AdminProposalListScreen({super.key});

  @override
  State<AdminProposalListScreen> createState() =>
      _AdminProposalListScreenState();
}

class _AdminProposalListScreenState extends State<AdminProposalListScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final query = context.read<AdminPlanningViewModel>().searchQuery;
    if (_searchController.text != query) _searchController.text = query;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposal Management',
          style: planningAppBarTitleStyle,
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Consumer<AdminPlanningViewModel>(
        builder: (context, viewModel, _) {
          final proposals = viewModel.filteredProposals;
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: planningPagePadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        onChanged: viewModel.setSearchQuery,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search proposals',
                          suffixIcon: viewModel.searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _searchController.clear();
                                    viewModel.setSearchQuery('');
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final stateFilter = DropdownButtonFormField<String>(
                            initialValue: viewModel.selectedState,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'State',
                              isDense: true,
                            ),
                            items: [
                              for (final state in viewModel.stateOptions)
                                DropdownMenuItem(
                                  value: state,
                                  child: Text(
                                    state,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                viewModel.setStateFilter(value);
                              }
                            },
                          );
                          final statusFilter = DropdownButtonFormField<String>(
                            initialValue: viewModel.selectedStatus,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              isDense: true,
                            ),
                            items: [
                              for (final status in viewModel.statusOptions)
                                DropdownMenuItem(
                                  value: status,
                                  child: Text(
                                    status,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                viewModel.setStatusFilter(value);
                              }
                            },
                          );
                          final assessmentFilter =
                              DropdownButtonFormField<String>(
                            initialValue: viewModel.selectedAssessment,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Assessment',
                              isDense: true,
                            ),
                            items: [
                              for (final assessment
                                  in viewModel.assessmentOptions)
                                DropdownMenuItem(
                                  value: assessment,
                                  child: Text(
                                    assessment,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                viewModel.setAssessmentFilter(value);
                              }
                            },
                          );
                          final media = MediaQuery.of(context);
                          final shortLandscape =
                              media.orientation == Orientation.landscape &&
                                  media.size.height < 480;
                          final filterWidth = constraints.maxWidth >= 760
                              ? (constraints.maxWidth - 24) / 3
                              : constraints.maxWidth >= 500
                                  ? (constraints.maxWidth - 12) / 2
                                  : constraints.maxWidth;
                          final filters = [
                            stateFilter,
                            statusFilter,
                            assessmentFilter,
                          ];
                          if (shortLandscape) {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (var index = 0;
                                      index < filters.length;
                                      index++) ...[
                                    SizedBox(
                                      width: 210,
                                      child: filters[index],
                                    ),
                                    if (index != filters.length - 1)
                                      const SizedBox(width: 10),
                                  ],
                                ],
                              ),
                            );
                          }
                          return Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              for (final filter in filters)
                                SizedBox(width: filterWidth, child: filter),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${proposals.length} proposal${proposals.length == 1 ? '' : 's'}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: proposals.isEmpty
                      ? const PlanningEmptyState(
                          icon: Icons.inbox_outlined,
                          title: 'No proposals found',
                          message:
                              'No proposals match the selected search and filters.',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final landscape =
                                MediaQuery.orientationOf(context) ==
                                    Orientation.landscape;
                            final media = MediaQuery.of(context);
                            final scale = media.textScaler.scale(1);
                            final shortLandscape =
                                landscape && media.size.height < 480;
                            final largeText = scale > 1.15;
                            final columns = shortLandscape || largeText
                                ? 1
                                : constraints.maxWidth >= 1180 &&
                                        media.size.height >= 680
                                    ? 3
                                    : constraints.maxWidth >= 760 &&
                                            media.size.height >= 560
                                        ? 2
                                        : 1;
                            Widget cardAt(int index) {
                              final proposal = proposals[index];
                              return _AdminProposalCard(
                                proposal: proposal,
                                assessment: viewModel.assessmentFor(proposal),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AdminProposalDetailsScreen(
                                      proposalId: proposal.id,
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (columns == 1) {
                              return ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: proposals.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (_, index) => cardAt(index),
                              );
                            }
                            const horizontalPadding = 20.0;
                            const spacing = 12.0;
                            final contentWidth =
                                constraints.maxWidth - horizontalPadding * 2;
                            final cardWidth =
                                (contentWidth - spacing * (columns - 1)) /
                                    columns;
                            return SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              child: Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: [
                                  for (var index = 0;
                                      index < proposals.length;
                                      index++)
                                    SizedBox(
                                      width: cardWidth,
                                      child: cardAt(index),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AdminProposalCard extends StatelessWidget {
  const _AdminProposalCard({
    required this.proposal,
    required this.assessment,
    required this.onTap,
  });

  final Proposal proposal;
  final ProposalAssessment? assessment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
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
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.ev_station, color: green),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposal.city,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: planningTextColor,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [proposal.nearestTown, proposal.state]
                              .whereType<String>()
                              .where((value) => value.trim().isNotEmpty)
                              .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(Icons.trending_up, '${proposal.demand} usage'),
                  CommunityResponseSummary(
                    proposal: proposal,
                    compact: true,
                  ),
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      assessment == null
                          ? 'Assessment pending'
                          : '${assessment!.outcome.label} · ${assessment!.score}/100',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _assessmentColor(assessment?.outcome),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(proposal.createdAt),
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      color: planningMutedTextColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _assessmentColor(ProposalAssessmentOutcome? outcome) {
    switch (outcome) {
      case ProposalAssessmentOutcome.recommended:
        return green;
      case ProposalAssessmentOutcome.furtherReviewRequired:
        return const Color(0xFFF39C12);
      case ProposalAssessmentOutcome.notRecommended:
        return const Color(0xFFE74C3C);
      case null:
        return planningMutedTextColor;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Date unavailable';
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
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: green),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
