import 'package:flutter/material.dart';

import '../../planning/widgets/planning_widgets.dart'
    show AppCard, green, blue, planningTextColor, planningMutedTextColor;
import '../models/fault_report.dart';

// Reuses the app's existing design tokens (green/blue/text colors, AppCard)
// from planning_widgets.dart rather than redefining them — see
// MODULE3_USER_IMPLEMENTATION_PLAN.md §2 for why that cross-module import is
// consistent with the rest of the codebase.

const orange = Color(0xFFFF9F43);
const purple = Color(0xFF8B5CF6);
const red = Color(0xFFE74C3C);

/// Display label for a report's status. Identity function today (the four
/// statuses — Submitted/Verified/In Progress/Resolved, see
/// `FaultReport._displayStatus` — are shown as-is on both sides of the app),
/// kept as a named call so call sites read the same whether or not a future
/// relabeling is needed again.
String feedbackStatusLabel(String status) => status;

/// Matches the admin dashboard's 4-stage pipeline coloring
/// (MODULE3_ADMIN_IMPLEMENTATION_PLAN.md): Submitted = red (new, unreviewed),
/// Verified = orange (admin-confirmed), In Progress = blue (maintenance
/// underway), Resolved = green (done). Shared by the driver's
/// `ReportStatusChip` and every admin status pill/marker, so a status means
/// the same color everywhere in the app.
Color feedbackStatusColor(String status) {
  switch (status) {
    case 'Verified':
      return orange;
    case 'In Progress':
      return blue;
    case 'Resolved':
      return green;
    default: // 'Submitted'
      return red;
  }
}

IconData feedbackStatusIcon(String status) {
  switch (status) {
    case 'Verified':
      return Icons.fact_check_outlined;
    case 'In Progress':
      return Icons.build_outlined;
    case 'Resolved':
      return Icons.check_circle_outline;
    default: // 'Submitted'
      return Icons.mark_email_unread_outlined;
  }
}

/// Admin-only triage priority coloring — High/Medium/Low, drivers never see
/// this. Same red/orange/green family as status, but priority and status are
/// independent axes (a report can be High priority and still Submitted).
Color feedbackPriorityColor(String priority) {
  switch (priority) {
    case 'High':
      return red;
    case 'Low':
      return green;
    default: // 'Medium'
      return orange;
  }
}

/// Status pill for a [FaultReport] — same rounded-pill shape as
/// `StatusChip` in planning_widgets.dart, plus a leading icon to match the
/// "Report an Issue" mockups.
class ReportStatusChip extends StatelessWidget {
  const ReportStatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = feedbackStatusColor(status);
    final label = feedbackStatusLabel(status);
    return Semantics(
      label: 'Report status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(feedbackStatusIcon(status), size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Priority pill for a [FaultReport] — admin-only (High/Medium/Low triage),
/// same rounded-pill shape as `ReportStatusChip` but without a leading icon,
/// matching the plain colored pills in the "Verify Reports" mockup.
class PriorityChip extends StatelessWidget {
  const PriorityChip(this.priority, {super.key});
  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = feedbackPriorityColor(priority);
    return Semantics(
      label: 'Priority: $priority',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: .24)),
        ),
        child: Text(
          priority,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The 4-node progress header on "Report an Issue": Location → Issue
/// Details → Review → Submitted. The visible form combines the mockup's
/// numbered Location/Issue-Details/Photo/Contact sections onto one
/// scrollable page rather than separate step screens (there's no design for
/// a distinct interactive "Review" step), so this indicator instead tracks
/// real progress through that one page: 0 while filling it in, 1 once the
/// location is confirmed, 2 while submitting, 3 on the success screen.
class ReportStepIndicator extends StatelessWidget {
  const ReportStepIndicator({super.key, required this.currentStep});

  /// 0 = Location, 1 = Issue Details, 2 = Review, 3 = Submitted.
  final int currentStep;

  static const _labels = ['Location', 'Issue Details', 'Review', 'Submitted'];

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i <= currentStep
                                ? green
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: i <= currentStep ? green : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i <= currentStep
                                ? green
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: i <= currentStep
                                ? Colors.white
                                : planningMutedTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (i < _labels.length - 1)
                        Expanded(
                          child: Container(
                            height: 2,
                            color: i < currentStep
                                ? green
                                : const Color(0xFFE0E0E0),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          i == currentStep ? FontWeight.w700 : FontWeight.w500,
                      color: i <= currentStep ? green : planningMutedTextColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

/// A row item in the "Report Overview" stat strip: icon in a tinted
/// circle, a number + label on one line, and a muted subtitle beneath.
class ReportOverviewStat extends StatelessWidget {
  const ReportOverviewStat({
    super.key,
    required this.value,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String value, label, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 5,
                        children: [
                          Text(
                            value,
                            style: TextStyle(
                              color: color,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            label,
                            style: const TextStyle(
                              color: planningTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// A tappable tinted card in the "Quick Actions" grid.
class QuickActionCard extends StatelessWidget {
  const QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: planningTextColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: planningMutedTextColor,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Icon(Icons.chevron_right, color: color, size: 18),
                ),
              ],
            ),
          ),
        ),
      );
}

/// Green hero card on the Feedback dashboard. There's no illustration asset
/// in the repo (the app otherwise relies entirely on Material icons rather
/// than custom art — see e.g. `ProposalCard`), so this substitutes a
/// stylized icon composition for the mockup's car-at-charger illustration.
class FeedbackHeroBanner extends StatelessWidget {
  const FeedbackHeroBanner({super.key, required this.onReportIssue});
  final VoidCallback onReportIssue;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFE3F5EE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.ev_station, color: green, size: 38),
                ),
                Positioned(
                  top: -6,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: green,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.priority_high,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Help improve our charging network',
                    style: TextStyle(
                      color: planningTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your feedback helps us keep charging stations '
                    'reliable for everyone.',
                    style: TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: onReportIssue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Report an Issue',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A row in a report list — thumbnail, title/location/date, status pill.
/// Used for both the dashboard's "My Recent Reports" preview and the full
/// "My Reports" list.
class ReportCard extends StatelessWidget {
  const ReportCard({
    super.key,
    required this.report,
    required this.onTap,
    this.trailingTime,
  });

  final FaultReport report;
  final VoidCallback onTap;

  /// Relative-time label ("10 mins ago") shown above the chevron on the
  /// full "My Reports" list; omitted on the dashboard preview.
  final String? trailingTime;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AppCard(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: report.photoUrls.isEmpty
                    ? Container(
                        width: 56,
                        height: 56,
                        color: green.withValues(alpha: .1),
                        child: const Icon(
                          Icons.ev_station,
                          color: green,
                          size: 24,
                        ),
                      )
                    : Image.network(
                        report.photoUrls.first,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          color: green.withValues(alpha: .1),
                          child: const Icon(
                            Icons.ev_station,
                            color: green,
                            size: 24,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      report.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: planningTextColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (report.locationLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: planningMutedTextColor,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              report.locationLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: planningMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      'Reported on ${formatReportDate(report.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReportStatusChip(report.status),
                  if (trailingTime != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      trailingTime!,
                      style: const TextStyle(
                        color: planningMutedTextColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const Icon(
                Icons.chevron_right,
                color: planningMutedTextColor,
                size: 20,
              ),
            ],
          ),
        ),
      );
}

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// No `intl` dependency in this project (see pubspec.yaml), so this hand
/// rolls the "15 Jul 2025, 10:30 AM" format the mockups use rather than
/// adding a new package just for this.
String formatReportDate(DateTime? date) {
  if (date == null) return 'an unknown date';
  final local = date.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${_monthNames[local.month - 1]} ${local.year}, '
      '$hour12:$minute $period';
}

/// "10 mins ago" / "2 hours ago" / "3 days ago" style relative time, used
/// on the full "My Reports" list.
String formatRelativeTime(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} min${diff.inMinutes == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
  }
  return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
}