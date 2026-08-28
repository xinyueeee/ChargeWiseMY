import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/models/fault_report.dart';
import '../../feedback/widgets/feedback_widgets.dart';
import '../../planning/screens/proposal_location_map_screen.dart';
import '../../planning/services/proposal_location_service.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../models/maintenance_record.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'new_maintenance_record_screen.dart';

/// Full report view for the admin side — mirrors the driver's
/// `ReportDetailsScreen` shape (photos, category/status card, description,
/// location) plus the admin-only priority selector and status-action
/// buttons gated by the current status (see
/// MODULE3_ADMIN_IMPLEMENTATION_PLAN.md §6.4).
class AdminReportDetailsScreen extends StatefulWidget {
  const AdminReportDetailsScreen({super.key, required this.report});

  final FaultReport report;

  @override
  State<AdminReportDetailsScreen> createState() =>
      _AdminReportDetailsScreenState();
}

class _AdminReportDetailsScreenState extends State<AdminReportDetailsScreen> {
  bool _updating = false;

  FaultReport get report => widget.report;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Report Details', style: planningAppBarTitleStyle),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: const [
            Padding(padding: EdgeInsets.only(right: 16), child: AdminBadge()),
          ],
        ),
        body: SafeArea(
          child: Consumer<AdminFeedbackViewModel>(
            builder: (context, vm, __) {
              final linkedRecords = vm.maintenanceRecords
                  .where((record) => record.reportId == report.id)
                  .toList()
                ..sort((a, b) => b.maintenanceDate.compareTo(a.maintenanceDate));

              return ListView(
                padding: planningPagePadding,
                children: [
                  if (report.photoUrls.isNotEmpty) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: report.photoUrls.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) => ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            report.photoUrls[index],
                            width: 220,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 220,
                              color: green.withValues(alpha: .08),
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: green,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    planningSectionGap,
                  ],
                  AppCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 52,
                          width: 52,
                          decoration: BoxDecoration(
                            color: green.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.ev_station, color: green, size: 30),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                report.category,
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      color: planningTextColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Reported by: ${report.reporterName ?? 'Unknown driver'}',
                                style: const TextStyle(color: planningMutedTextColor),
                              ),
                              Text(
                                submittedOnLabel(report.createdAt),
                                style: const TextStyle(color: planningMutedTextColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(child: ReportStatusChip(report.status)),
                      ],
                    ),
                  ),
                  planningSectionGap,
                  const PlanningSectionTitle('Description'),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Text(
                      report.description.trim().isEmpty
                          ? 'No description was provided.'
                          : report.description,
                      style: const TextStyle(color: planningMutedTextColor, height: 1.5),
                    ),
                  ),
                  planningSectionGap,
                  const PlanningSectionTitle('Location'),
                  const SizedBox(height: 10),
                  if (report.latitude == null || report.longitude == null)
                    const PlanningEmptyState(
                      icon: Icons.location_off_outlined,
                      title: 'Location unavailable',
                      message: 'This report does not contain valid map coordinates.',
                    )
                  else
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            report.locationLabel.isEmpty
                                ? 'Selected report location'
                                : report.locationLabel,
                            style: const TextStyle(
                              color: planningTextColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
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
                  const PlanningSectionTitle('Priority'),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Row(
                      children: [
                        for (final priority in kFaultReportPriorities) ...[
                          Expanded(
                            child: _PriorityOption(
                              label: priority,
                              selected: report.priority == priority,
                              enabled: !_updating,
                              onTap: () => _setPriority(vm, priority),
                            ),
                          ),
                          if (priority != kFaultReportPriorities.last)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  planningSectionGap,
                  const PlanningSectionTitle('Additional information'),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      children: [
                        InformationRow('Status', report.status),
                        const Divider(height: 1),
                        InformationRow('Category', report.category),
                        const Divider(height: 1),
                        InformationRow('Reported on', formatReportDate(report.createdAt)),
                        if ((report.contactInfo ?? '').isNotEmpty) ...[
                          const Divider(height: 1),
                          InformationRow('Contact', report.contactInfo!),
                        ],
                      ],
                    ),
                  ),
                  if (linkedRecords.isNotEmpty) ...[
                    planningSectionGap,
                    const PlanningSectionTitle('Maintenance Record'),
                    const SizedBox(height: 10),
                    for (final record in linkedRecords) ...[
                      _MaintenanceSummaryCard(
                        record: record,
                        onTap: () => _openEditRecord(context, record),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                  planningSectionGap,
                  _buildActions(context, vm),
                ],
              );
            },
          ),
        ),
      );

  Widget _buildActions(BuildContext context, AdminFeedbackViewModel vm) {
    switch (report.status) {
      case 'Submitted':
        return ElevatedButton.icon(
          onPressed: _updating ? null : () => _verify(vm),
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: _updating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.fact_check_outlined),
          label: const Text('Verify'),
        );
      case 'Verified':
        return ResponsiveButtonPair(
          first: OutlinedButton.icon(
            onPressed: _updating ? null : () => _openNewRecord(context),
            icon: const Icon(Icons.build_outlined),
            label: const Text('Log Maintenance Record'),
          ),
          second: ElevatedButton.icon(
            onPressed: _updating ? null : () => _resolve(vm),
            style: ElevatedButton.styleFrom(
              backgroundColor: green,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Mark Resolved'),
          ),
        );
      case 'In Progress':
        return ElevatedButton.icon(
          onPressed: _updating ? null : () => _resolve(vm),
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
          ),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Mark Resolved'),
        );
      default: // 'Resolved'
        return AppCard(
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: green),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'This report has been resolved.',
                  style: TextStyle(color: planningMutedTextColor),
                ),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _viewOnMap() async {
    final latitude = report.latitude;
    final longitude = report.longitude;
    if (latitude == null || longitude == null) return;
    final selection = ProposalLocationSelection(
      latitude: latitude,
      longitude: longitude,
      state: report.state ?? 'Malaysia',
      nearestTown: report.nearestTown ?? 'Selected location',
      locationLabel: report.locationLabel.isEmpty
          ? 'Selected report location'
          : report.locationLabel,
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

  Future<void> _setPriority(AdminFeedbackViewModel vm, String priority) async {
    if (report.priority == priority) return;
    setState(() => _updating = true);
    try {
      await vm.updatePriority(report, priority);
    } catch (error, stackTrace) {
      debugPrint('Update priority failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _verify(AdminFeedbackViewModel vm) => _runStatusAction(
        vm.verifyReport(report),
        successMessage: '"${report.category}" verified.',
      );

  Future<void> _resolve(AdminFeedbackViewModel vm) => _runStatusAction(
        vm.resolveReport(report),
        successMessage: '"${report.category}" marked resolved.',
      );

  Future<void> _runStatusAction(
    Future<void> action, {
    required String successMessage,
  }) async {
    setState(() => _updating = true);
    try {
      await action;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Report status update failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to update. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _openNewRecord(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewMaintenanceRecordScreen(
          reportId: report.id,
          stationId: report.stationId,
          reportSummary: '${report.category} · ${report.locationLabel}',
        ),
      ),
    );
  }

  void _openEditRecord(BuildContext context, MaintenanceRecord record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewMaintenanceRecordScreen(record: record),
      ),
    );
  }
}

class _PriorityOption extends StatelessWidget {
  const _PriorityOption({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = feedbackPriorityColor(label);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: .12) : Colors.transparent,
          border: Border.all(color: selected ? color : const Color(0xFFE0E4EA)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : planningMutedTextColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _MaintenanceSummaryCard extends StatelessWidget {
  const _MaintenanceSummaryCard({required this.record, required this.onTap});

  final MaintenanceRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = record.status == 'Delayed'
        ? red
        : record.status == 'Completed'
            ? green
            : orange;
    return AppCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            Icon(Icons.build_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.summary.isEmpty ? 'Maintenance task' : record.summary,
                    style: const TextStyle(
                      color: planningTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${record.status}'
                    '${record.technicianName == null ? '' : ' · ${record.technicianName}'}',
                    style: const TextStyle(color: planningMutedTextColor, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: planningMutedTextColor),
          ],
        ),
      ),
    );
  }
}
