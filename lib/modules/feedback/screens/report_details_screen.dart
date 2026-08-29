import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../core/navigation/driver_navigation_shell.dart';
import '../../planning/screens/proposal_location_map_screen.dart';
import '../../planning/services/proposal_location_service.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../models/fault_report.dart';
import '../viewmodels/feedback_viewmodel.dart';
import '../widgets/feedback_widgets.dart';
import 'new_report_screen.dart';

/// View / edit / delete a single [FaultReport] — mirrors
/// `proposal_details_screen.dart`'s shape and reuses `ProposalLocationMapScreen`
/// (readOnly) for the map preview. Edit/Delete are only offered while the
/// report is still `Submitted`; once an admin has verified or resolved it,
/// RLS itself would reject a driver-side update/delete anyway (see
/// `supabase/sql/fault_reports.sql`), so the UI matches that boundary
/// instead of offering actions that would just fail.
class ReportDetailsScreen extends StatefulWidget {
  const ReportDetailsScreen({super.key, required this.report});

  final FaultReport report;

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  bool _deleting = false;

  FaultReport get report => widget.report;
  bool get _editable => report.status == 'Submitted';

  /// Destinations for this screen, shared by the bottom bar and the

  /// side rail so both surfaces stay identical.

  DriverNavigationConfig _navConfig(BuildContext context) =>
      DriverNavigationConfig(
        currentTab: 'Feedback',
        onHomeTap: () => switchDriverTab(context, DriverTab.home),
        onChargingTap: () => switchDriverTab(context, DriverTab.charging),
        onFeedbackTap: () => Navigator.of(context).pop(),
        onPlanningTap: () => switchDriverTab(context, DriverTab.planning),
        onProfileTap: () => switchDriverTab(context, DriverTab.profile),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Report Details', style: planningAppBarTitleStyle),
          centerTitle: true,
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        body: DriverNavigationShell(
          config: _navConfig(context),
          child: SafeArea(
            child: ListView(
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
                        child: const Icon(Icons.ev_station,
                            color: green, size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.category,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: planningTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Reported on ${formatReportDate(report.createdAt)}',
                              style: const TextStyle(
                                  color: planningMutedTextColor),
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
                    style: const TextStyle(
                        color: planningMutedTextColor, height: 1.5),
                  ),
                ),
                planningSectionGap,
                const PlanningSectionTitle('Location'),
                const SizedBox(height: 10),
                if (report.latitude == null || report.longitude == null)
                  const PlanningEmptyState(
                    icon: Icons.location_off_outlined,
                    title: 'Location unavailable',
                    message:
                        'This report does not contain valid map coordinates.',
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
                const PlanningSectionTitle('Additional information'),
                const SizedBox(height: 10),
                AppCard(
                  child: Column(
                    children: [
                      InformationRow(
                          'Status', feedbackStatusLabel(report.status)),
                      const Divider(height: 1),
                      InformationRow('Category', report.category),
                      const Divider(height: 1),
                      InformationRow(
                        'Reported on',
                        formatReportDate(report.createdAt),
                      ),
                      if ((report.contactInfo ?? '').isNotEmpty) ...[
                        const Divider(height: 1),
                        InformationRow('Contact', report.contactInfo!),
                      ],
                    ],
                  ),
                ),
                planningSectionGap,
                if (_editable)
                  ResponsiveButtonPair(
                    first: OutlinedButton.icon(
                      onPressed: _deleting ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                    second: OutlinedButton.icon(
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: _deleting ? null : _confirmDelete,
                      icon: _deleting
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                      label: Text(_deleting ? 'Deleting…' : 'Delete'),
                    ),
                  )
                else
                  AppCard(
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: feedbackStatusColor(report.status),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusBannerMessage(report.status),
                            style:
                                const TextStyle(color: planningMutedTextColor),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: _navConfig(context).bottomBarFor(context),
      );

  String _statusBannerMessage(String status) {
    switch (status) {
      case 'Verified':
        return 'An administrator has verified this report and will begin '
            'work soon. You can no longer edit or delete it.';
      case 'In Progress':
        return 'Maintenance is underway for this report. You can no longer '
            'edit or delete it.';
      default: // 'Resolved'
        return 'This report has been resolved. Thank you for helping keep '
            'charging stations reliable.';
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

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => NewReportScreen(report: report),
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
        title: const Text('Delete Report?'),
        content: Text(
          '"${report.category}" will be removed permanently. '
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
      await context.read<FeedbackViewModel>().deleteReport(report.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Report deleted.'),
        ),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Fault report deletion failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to delete the report. Please try again.'),
        ),
      );
    }
  }
}
