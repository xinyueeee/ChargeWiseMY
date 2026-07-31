import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import 'new_proposal_screen.dart';
import 'proposal_details_screen.dart';

class ProposalListScreen extends StatefulWidget {
  const ProposalListScreen({super.key});

  @override
  State<ProposalListScreen> createState() => _ProposalListScreenState();
}

class _ProposalListScreenState extends State<ProposalListScreen> {
  final TextEditingController _searchController = TextEditingController();
  PlanningViewModel? _viewModel;
  List<Proposal> _source = const [];
  List<Proposal> _visible = const [];
  String _query = '';
  String _status = 'All statuses';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewModel = context.read<PlanningViewModel>();
    if (identical(viewModel, _viewModel)) return;
    _viewModel?.removeListener(_handleViewModelChange);
    _viewModel = viewModel;
    _viewModel!.addListener(_handleViewModelChange);
    _refreshSource();
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_handleViewModelChange);
    _searchController.dispose();
    super.dispose();
  }

  void _handleViewModelChange() {
    if (!mounted) return;
    setState(_refreshSource);
  }

  void _refreshSource() {
    final proposals = _viewModel?.selectedProposals ?? const <Proposal>[];
    if (!identical(proposals, _source)) {
      _source = proposals;
    }
    _applyFilters();
  }

  void _applyFilters() {
    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = _source.where((proposal) {
      final matchesStatus =
          _status == 'All statuses' || proposal.status == _status;
      final matchesSearch = normalizedQuery.isEmpty ||
          proposal.city.toLowerCase().contains(normalizedQuery) ||
          proposal.description.toLowerCase().contains(normalizedQuery);
      return matchesStatus && matchesSearch;
    }).toList()
      ..sort((a, b) {
        final supportComparison =
            b.displayedSupports.compareTo(a.displayedSupports);
        return supportComparison != 0
            ? supportComparison
            : a.city.compareTo(b.city);
      });
    _visible = List<Proposal>.unmodifiable(filtered);
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = _viewModel!;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Proposals',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          IconButton(
            tooltip: 'Add proposed station',
            onPressed: _openNewProposal,
            icon: const Icon(Icons.add_location_alt_outlined),
          ),
        ],
      ),
      body: viewModel.loading
          ? const PlanningLoadingState(message: 'Loading proposals…')
          : viewModel.errorMessage != null
              ? PlanningErrorState(
                  message: viewModel.errorMessage!,
                  onRetry: viewModel.load,
                )
              : SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: planningPagePadding,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            PlanningSectionTitle(
                              'Community proposals',
                              subtitle: 'Showing proposed charging locations in '
                                  '${viewModel.selectedState}.',
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: 'Search proposals',
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear search',
                                        onPressed: () {
                                          FocusScope.of(context).unfocus();
                                          _searchController.clear();
                                          setState(() {
                                            _query = '';
                                            _applyFilters();
                                          });
                                        },
                                        icon: const Icon(Icons.clear),
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (value) => setState(() {
                                _query = value;
                                _applyFilters();
                              }),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _status,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Status',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'All statuses',
                                        child: Text('All statuses'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Pending',
                                        child: Text('Pending'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Under Review',
                                        child: Text('Under Review'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Approved',
                                        child: Text('Approved'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'Rejected',
                                        child: Text('Rejected'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _status = value;
                                        _applyFilters();
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    '${_visible.length} result'
                                    '${_visible.length == 1 ? '' : 's'}',
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      color: planningMutedTextColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Sorted by community support',
                              style: TextStyle(
                                color: planningMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _visible.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  20,
                                ),
                                child: PlanningEmptyState(
                                  icon: Icons.ev_station_outlined,
                                  title: _source.isEmpty
                                      ? 'No proposals yet'
                                      : 'No matching proposals',
                                  message: _source.isEmpty
                                      ? 'Create the first proposed charging-station location.'
                                      : 'Try changing the search text or status filter.',
                                  action: _source.isEmpty
                                      ? ElevatedButton.icon(
                                          onPressed: _openNewProposal,
                                          icon: const Icon(
                                            Icons.add_location_alt_outlined,
                                          ),
                                          label:
                                              const Text('Add a proposal'),
                                        )
                                      : null,
                                ),
                              )
                            : ListView.builder(
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                itemCount: _visible.length,
                                itemBuilder: (context, index) {
                                  final proposal = _visible[index];
                                  return Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: ProposalCard(
                                      proposal: proposal,
                                      onDetails: () => Navigator.push(
                                        context,
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              ProposalDetailsScreen(
                                            proposal: proposal,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
      bottomNavigationBar: const FloatingBottomNav(),
    );
  }

  Future<void> _openNewProposal() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => const NewProposalScreen(),
      ),
    );
  }
}
