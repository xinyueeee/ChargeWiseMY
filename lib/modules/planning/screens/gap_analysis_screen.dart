import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../services/gap_ai_analysis_service.dart';
import '../viewmodels/planning_viewmodel.dart';
import '../widgets/planning_widgets.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../widgets/planning_destination_bottom_nav.dart';
import 'new_proposal_screen.dart';
import 'priority_area_map_screen.dart';

class GapAnalysisScreen extends StatefulWidget {
  const GapAnalysisScreen(
      {super.key, this.aiService = const SupabaseGapAiAnalysisService()});
  final GapAiAnalysisService aiService;

  @override
  State<GapAnalysisScreen> createState() => _GapAnalysisScreenState();
}

class _GapAnalysisScreenState extends State<GapAnalysisScreen> {
  String? _selectedAreaId;
  String? _aiAreaId;
  GapAiAnalysisResult? _aiResult;
  bool _generatingAi = false;
  bool _aiFailed = false;
  GapAiFailureReason _aiFailureReason = GapAiFailureReason.unavailable;
  bool _showAllAreas = false;

  GapArea? _selectedArea(List<GapArea> areas) {
    if (areas.isEmpty) return null;
    for (final area in areas) {
      if (area.id == _selectedAreaId) return area;
    }
    return areas.first;
  }

  Future<void> _generateAi(
    PlanningViewModel viewModel,
    GapArea area,
    String displayName,
  ) async {
    setState(() {
      _generatingAi = true;
      _aiFailed = false;
      _aiResult = null;
      _aiAreaId = area.id;
    });
    try {
      final result = await widget.aiService.generate(
        GapAiAnalysisContext.fromArea(
          area,
          displayName: displayName,
          plannedInfrastructure: area.latitude == null || area.longitude == null
              ? null
              : viewModel.plannedContextAt(
                  area.latitude!,
                  area.longitude!,
                  radiusKm: area.nearbyRadiusKm,
                ),
        ),
      );
      if (!mounted || _aiAreaId != area.id) return;
      setState(() => _aiResult = result);
    } catch (error, stackTrace) {
      debugPrint('Gap AI analysis unavailable: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || _aiAreaId != area.id) return;
      setState(() {
        _aiFailed = true;
        _aiFailureReason = error is GapAiAnalysisUnavailableException
            ? error.reason
            : GapAiFailureReason.unavailable;
      });
    } finally {
      if (mounted && _aiAreaId == area.id) {
        setState(() => _generatingAi = false);
      }
    }
  }

  void _openAreaMap(GapArea area) {
    if (area.latitude == null || area.longitude == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PriorityAreaMapScreen(area: area),
    ));
  }

  void _createProposal(GapArea area, String displayName) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => NewProposalScreen(
        sourceGap: area,
        sourceGapDisplayName: displayName,
      ),
    ));
  }

  void _selectArea(GapArea area) {
    if (_selectedAreaId == area.id) return;
    setState(() {
      _selectedAreaId = area.id;
      _aiAreaId = null;
      _aiResult = null;
      _aiFailed = false;
      _aiFailureReason = GapAiFailureReason.unavailable;
      _generatingAi = false;
    });
  }

  @override
  Widget build(BuildContext context) => Consumer<PlanningViewModel>(
        builder: (context, viewModel, _) {
          final areas = viewModel.priorityAreas;
          final selectedArea = _selectedArea(areas);
          debugPrint('GapAnalysisScreen reads state analysis: '
              'viewModel=${identityHashCode(viewModel)}, state=${viewModel.selectedState}, '
              'resultCount=${areas.length}.');
          return Scaffold(
            appBar: AppBar(
              title:
                  const Text('Gap Analysis', style: planningAppBarTitleStyle),
              centerTitle: true,
              backgroundColor: Colors.white,
              elevation: 0,
              foregroundColor: Colors.black,
            ),
            body: DriverNavigationShell(
              config: planningDriverNavConfig(context),
              child: viewModel.loading
                  ? const PlanningLoadingState(
                      message: 'Loading charging infrastructure…')
                  : viewModel.errorMessage != null
                      ? PlanningErrorState(
                          message: viewModel.errorMessage!,
                          onRetry: viewModel.load)
                      : SafeArea(child: LayoutBuilder(
                          builder: (context, constraints) {
                            final landscape = constraints.maxWidth >= 700 &&
                                constraints.maxWidth > constraints.maxHeight;
                            final controls = _controls(viewModel);
                            final details =
                                _details(viewModel, areas, selectedArea);
                            if (landscape) {
                              return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            14, 10, 8, 14),
                                        child: Column(children: [
                                          controls,
                                          const SizedBox(height: 8),
                                          Expanded(
                                              child: LayoutBuilder(
                                            builder:
                                                (context, mapConstraints) =>
                                                    _analysisMap(
                                              viewModel,
                                              areas,
                                              selectedArea,
                                              height: mapConstraints.maxHeight,
                                            ),
                                          )),
                                        ]),
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      flex: 2,
                                      child: ListView(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 10, 14, 18),
                                        children: [
                                          _rankedAreaSelector(areas,
                                              landscape: true),
                                          const SizedBox(height: 10),
                                          details,
                                        ],
                                      ),
                                    ),
                                  ]);
                            }
                            return ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 22),
                              children: [
                                controls,
                                const SizedBox(height: 10),
                                _analysisMap(viewModel, areas, selectedArea,
                                    height: 250),
                                const SizedBox(height: 10),
                                _rankedAreaSelector(areas),
                                const SizedBox(height: 10),
                                details,
                              ],
                            );
                          },
                        )),
            ),
            bottomNavigationBar:
                planningDriverNavConfig(context).bottomBarFor(context),
          );
        },
      );

  Widget _controls(PlanningViewModel viewModel) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
              key: ValueKey('gap-state-${viewModel.selectedState}'),
              initialValue: viewModel.selectedState,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Planning region',
                prefixIcon: Icon(Icons.map_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final state in viewModel.stateOptions)
                  DropdownMenuItem(
                      value: state,
                      child: Text(state, overflow: TextOverflow.ellipsis))
              ],
              onChanged: (state) {
                if (state != null) {
                  viewModel.selectState(state, source: 'gap-analysis-dropdown');
                }
              },
            )),
            const SizedBox(width: 8),
            Flexible(
                child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F8F6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD7E9E3)),
              ),
              child: Text(
                viewModel.selectedAnalysisProfile.displayName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: green, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            )),
          ]),
          if (viewModel.analyzingGaps ||
              viewModel.analysisErrorMessage != null) ...[
            const SizedBox(height: 8),
            AnalysisStatusPanel(
              message: viewModel.analysisStatusMessage ?? 'Preparing analysis…',
              analyzing: viewModel.analyzingGaps,
              hasError: viewModel.analysisErrorMessage != null,
              onRetry: viewModel.analysisErrorMessage == null
                  ? null
                  : viewModel.retrySelectedStateAnalysis,
            ),
          ],
        ],
      );

  Widget _analysisMap(
    PlanningViewModel vm,
    List<GapArea> areas,
    GapArea? selectedArea, {
    required double height,
  }) =>
      MapPanel(
        height: height,
        gaps: true,
        priorityAreas: areas,
        selectedPriorityAreaId: selectedArea?.id,
        stateRegions: vm.stateRegions,
        selectedState: vm.selectedState,
        focusBounds: vm.selectedMapBounds,
      );

  Widget _rankedAreaSelector(
    List<GapArea> areas, {
    bool landscape = false,
  }) {
    if (areas.isEmpty) return const SizedBox.shrink();
    final labels = _areaDisplayLabels(areas);
    final visibleCount =
        landscape || _showAllAreas ? areas.length : areas.length.clamp(0, 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Expanded(
              child: Text('Ranked Priority Areas',
                  style: TextStyle(
                      color: planningTextColor, fontWeight: FontWeight.w800))),
          Text('${areas.length} results',
              style:
                  const TextStyle(color: planningMutedTextColor, fontSize: 12)),
        ]),
        const SizedBox(height: 7),
        for (var index = 0; index < visibleCount; index++) ...[
          _RankedAreaTile(
            rank: index + 1,
            area: areas[index],
            label: labels[areas[index].id]!,
            selected: _selectedArea(areas)?.id == areas[index].id,
            onTap: () => _selectArea(areas[index]),
          ),
          if (index + 1 < visibleCount) const SizedBox(height: 6),
        ],
        if (!landscape && areas.length > 3)
          TextButton.icon(
            onPressed: () => setState(() => _showAllAreas = !_showAllAreas),
            icon: Icon(_showAllAreas ? Icons.expand_less : Icons.expand_more),
            label: Text(_showAllAreas
                ? 'Show top 3'
                : 'View all ${areas.length} areas'),
          ),
      ],
    );
  }

  Map<String, String> _areaDisplayLabels(List<GapArea> areas) {
    final bases = <String>[];
    final totals = <String, int>{};
    for (final area in areas) {
      final settlement = area.nearestSettlementName?.trim();
      final base =
          settlement != null && settlement.isNotEmpty ? settlement : area.state;
      bases.add(base);
      totals[base] = (totals[base] ?? 0) + 1;
    }
    final occurrences = <String, int>{};
    return {
      for (var index = 0; index < areas.length; index++)
        areas[index].id: () {
          final base = bases[index];
          final occurrence = (occurrences[base] ?? 0) + 1;
          occurrences[base] = occurrence;
          return totals[base] == 1 ? '$base Area' : '$base Area $occurrence';
        }(),
    };
  }

  Widget _details(PlanningViewModel vm, List<GapArea> areas, GapArea? area) {
    if (vm.analyzingGaps) {
      return PlanningLoadingState(
          message: 'Analyzing ${vm.selectedState} coverage…');
    }
    if (vm.analysisErrorMessage != null) {
      return PlanningErrorState(
          message: vm.analysisErrorMessage!,
          onRetry: vm.retrySelectedStateAnalysis);
    }
    if (area == null) {
      return const PlanningEmptyState(
        icon: Icons.check_circle_outline,
        title: 'No infrastructure gaps detected',
        message:
            'No sampled land location met the configured geographical coverage-gap criteria. No thresholds were relaxed.',
      );
    }

    final priorityColor = _priorityColor(area.priority);
    final displayName = _areaDisplayLabels(areas)[area.id] ?? area.name;
    final aiResult = _aiAreaId == area.id ? _aiResult : null;
    final aiFailed = _aiAreaId == area.id && _aiFailed;
    final planned = area.latitude == null || area.longitude == null
        ? null
        : vm.plannedContextAt(
            area.latitude!,
            area.longitude!,
            radiusKm: area.nearbyRadiusKm,
          );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('${area.priority.toUpperCase()} PRIORITY',
                      style: TextStyle(
                          color: priorityColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5)),
                  const SizedBox(height: 3),
                  Text(displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: planningTextColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                ])),
            const SizedBox(width: 10),
            Text('${area.priorityScore.toStringAsFixed(0)}/100',
                style: TextStyle(
                    color: priorityColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 10),
          _EvidenceStrip(area: area),
        ]),
      ),
      const SizedBox(height: 10),
      if (_generatingAi && _aiAreaId == area.id)
        const _AiLoadingCard()
      else if (aiResult != null)
        _AiResultCard(result: aiResult)
      else if (aiFailed)
        _AiFailureCard(
          reason: _aiFailureReason,
          onRetry: () => _generateAi(vm, area, displayName),
        )
      else
        OutlinedButton.icon(
          onPressed: () => _generateAi(vm, area, displayName),
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Generate AI Analysis'),
        ),
      const SizedBox(height: 10),
      AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Official Planned Infrastructure',
                style: TextStyle(
                    color: planningTextColor, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _BreakdownRow(
              label: 'Nearest MEVnet Proposed',
              value: planned?.nearestDistanceKm == null
                  ? 'Not available'
                  : '${planned!.nearestDistanceKm!.toStringAsFixed(1)} km',
            ),
            _BreakdownRow(
              label: 'Proposed locations nearby',
              value: '${planned?.nearbyLocationCount ?? 0}',
            ),
            _BreakdownRow(
              label: 'Proposed EVCB nearby',
              value: '${planned?.nearbyProposedChargerCount ?? 0}',
            ),
            const SizedBox(height: 5),
            const Text(
              'MEVnet Proposed locations are future planning context and do not '
              'count as current coverage or alter this priority score.',
              style: TextStyle(
                  color: planningMutedTextColor, fontSize: 12, height: 1.35),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      const Text('Recommended Actions',
          style:
              TextStyle(color: planningTextColor, fontWeight: FontWeight.w800)),
      const SizedBox(height: 7),
      ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46)),
        onPressed: () => _createProposal(area, displayName),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Create Proposal'),
      ),
      TextButton.icon(
        onPressed: area.latitude == null || area.longitude == null
            ? null
            : () => _openAreaMap(area),
        icon: const Icon(Icons.map_outlined),
        label: const Text('View focused map'),
      ),
      AppCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            title: const Text('View analysis breakdown',
                style: TextStyle(fontWeight: FontWeight.w700)),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              _BreakdownRow(
                  label: 'Coverage score',
                  value: area.coverageScore.toStringAsFixed(1)),
              _BreakdownRow(
                  label: 'Analysis profile',
                  value: vm.selectedAnalysisProfile.displayName),
              _BreakdownRow(
                  label: 'Nearby radius',
                  value: '${area.nearbyRadiusKm.toStringAsFixed(1)} km'),
              if (area.localStationLocationCount > 0)
                _BreakdownRow(
                    label: 'Locations in analysis cell',
                    value: '${area.localStationLocationCount}'),
              if (area.nearestSettlementName != null)
                _BreakdownRow(
                    label: 'Nearest settlement',
                    value: area.nearestSettlementName!),
              const SizedBox(height: 8),
              Align(
                  alignment: Alignment.centerLeft,
                  child: Text(area.reason,
                      style: const TextStyle(
                          color: planningMutedTextColor, height: 1.35))),
              const SizedBox(height: 8),
              const Text(
                'This is a charging-infrastructure coverage assessment, not a demand or site-feasibility prediction. Road access, parking, grid capacity, land ownership, and approval require review.',
                style: TextStyle(
                    color: planningMutedTextColor, fontSize: 12, height: 1.35),
              ),
            ],
          ),
        ),
      ),
      if (areas.length > 1) ...[
        const SizedBox(height: 8),
        Text('${areas.length} ranked gaps available in ${vm.selectedState}',
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: planningMutedTextColor, fontSize: 12)),
      ],
    ]);
  }
}

class _EvidenceStrip extends StatelessWidget {
  const _EvidenceStrip({required this.area});
  final GapArea area;
  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 18, runSpacing: 10, children: [
        _EvidenceMetric(
            label: 'Nearest', value: '${area.distance.toStringAsFixed(1)} km'),
        _EvidenceMetric(
            label: 'Nearby',
            value:
                '${area.nearbyStationCount} location${area.nearbyStationCount == 1 ? '' : 's'}'),
        _EvidenceMetric(
            label: 'Coverage', value: area.coverageScore.toStringAsFixed(1)),
      ]);
}

class _RankedAreaTile extends StatelessWidget {
  const _RankedAreaTile({
    required this.rank,
    required this.area,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final int rank;
  final GapArea area;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _priorityColor(area.priority);
    return Material(
      color: selected ? color.withValues(alpha: .08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? color : const Color(0xFFE1E6EC),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: Text('$rank',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: planningTextColor,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                      '${area.priority} Priority · ${area.distance.toStringAsFixed(1)} km nearest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: planningMutedTextColor, fontSize: 12)),
                ])),
            const SizedBox(width: 8),
            Text(area.priorityScore.toStringAsFixed(0),
                style: TextStyle(
                    color: color, fontSize: 17, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _EvidenceMetric extends StatelessWidget {
  const _EvidenceMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 76),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: planningMutedTextColor, fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: planningTextColor, fontWeight: FontWeight.w800)),
            ]),
      );
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: planningMutedTextColor))),
          const SizedBox(width: 12),
          Flexible(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      );
}

class _AiLoadingCard extends StatelessWidget {
  const _AiLoadingCard();
  @override
  Widget build(BuildContext context) => const AppCard(
        padding: EdgeInsets.all(14),
        child: Row(children: [
          SizedBox.square(
              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Expanded(child: Text('Generating planning insight…')),
        ]),
      );
}

class _AiFailureCard extends StatelessWidget {
  const _AiFailureCard({required this.reason, required this.onRetry});
  final GapAiFailureReason reason;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final message = switch (reason) {
      GapAiFailureReason.rateLimited =>
        'AI service is temporarily busy. Please try again shortly.',
      GapAiFailureReason.timeout =>
        'AI analysis took too long. Please try again.',
      GapAiFailureReason.authentication =>
        'Sign in again to generate an AI planning insight.',
      GapAiFailureReason.unavailable =>
        "AI analysis couldn't be generated right now.",
    };
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 4),
                TextButton(onPressed: onRetry, child: const Text('Try Again')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AiResultCard extends StatelessWidget {
  const _AiResultCard({required this.result});
  final GapAiAnalysisResult result;
  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome_outlined, color: green, size: 20),
            SizedBox(width: 8),
            Text('AI Planning Insight',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          Text(result.interpretation),
          if (result.keyConsiderations.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Key considerations',
                style: TextStyle(fontWeight: FontWeight.w700)),
            for (final item in result.keyConsiderations) Text('• $item'),
          ],
          const SizedBox(height: 8),
          const Text('Suggested next step',
              style: TextStyle(fontWeight: FontWeight.w700)),
          Text(result.suggestedNextStep),
          const SizedBox(height: 8),
          const Text(
            'Generated from the current Gap Analysis results. Verify site-specific conditions before making planning decisions.',
            style: TextStyle(color: planningMutedTextColor, fontSize: 11),
          ),
        ]),
      );
}

Color _priorityColor(String priority) {
  switch (priority.toLowerCase()) {
    case 'high':
      return Colors.red;
    case 'medium':
      return Colors.orange;
    default:
      return green;
  }
}
