import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../feedback/widgets/feedback_widgets.dart' show formatReportDate;
import '../../planning/widgets/planning_widgets.dart'
    show AppCard, planningTextColor, planningMutedTextColor;

/// Circular-icon stat tile for the admin feedback dashboard — mirrors the
/// four-tile row in the design mockup (icon in a tinted circle, big colored
/// number, label underneath). Deliberately doesn't show a "+X% vs last 7
/// days" trend caption like the mockup: that would need historical
/// snapshots the app doesn't collect, and a fabricated delta would be worse
/// than none.
class AdminStatTile extends StatelessWidget {
  const AdminStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: planningMutedTextColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class DonutSegment {
  const DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

/// "Reports by Status" donut — hand-rolled with `CustomPainter` rather than
/// adding a charting package for one chart (no `fl_chart`/similar dependency
/// exists in pubspec.yaml today).
class AdminDonutChart extends StatelessWidget {
  const AdminDonutChart({super.key, required this.segments});

  final List<DonutSegment> segments;

  int get _total => segments.fold(0, (sum, s) => sum + s.value);

  @override
  Widget build(BuildContext context) {
    final total = _total;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, 220.0);
        return Column(
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CustomPaint(
                painter: _DonutPainter(segments: segments, total: total),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: planningTextColor,
                        ),
                      ),
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: planningMutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final segment in segments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: segment.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            segment.label,
                            style: const TextStyle(
                              color: planningTextColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          total == 0
                              ? '${segment.value}'
                              : '${segment.value} '
                                  '(${(segment.value / total * 100).toStringAsFixed(1)}%)',
                          style: const TextStyle(
                            color: planningMutedTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.segments, required this.total});

  final List<DonutSegment> segments;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.shortestSide * .16;
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    if (total == 0) {
      final paint = Paint()
        ..color = const Color(0xFFE9EDF3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(rect, 0, 2 * math.pi, false, paint);
      return;
    }
    var startAngle = -math.pi / 2;
    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweep = (segment.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.total != total;
}

/// Shared list-item shape for admin report browsing — the dashboard's
/// "Recent Fault Reports", "Verify Reports", and "History" all show the
/// same photo/title/location/date row, just with different trailing chips
/// and (optionally) an action-button row underneath.
class AdminReportListTile extends StatelessWidget {
  const AdminReportListTile({
    super.key,
    required this.title,
    required this.location,
    required this.dateLabel,
    required this.chip,
    this.photoUrl,
    this.subtitle,
    this.actions,
    this.onTap,
  });

  final String title;
  final String location;
  final String dateLabel;
  final Widget chip;
  final String? photoUrl;
  final String? subtitle;
  final Widget? actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: photoUrl == null
                          ? Container(
                              color: planningMutedTextColor.withValues(alpha: .1),
                              child: const Icon(
                                Icons.ev_station,
                                color: planningMutedTextColor,
                              ),
                            )
                          : Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color:
                                    planningMutedTextColor.withValues(alpha: .1),
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: planningMutedTextColor,
                                ),
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
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: planningTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                                location.isEmpty ? 'Unknown location' : location,
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
                        const SizedBox(height: 2),
                        Text(
                          dateLabel,
                          style: const TextStyle(
                            color: planningMutedTextColor,
                            fontSize: 11,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: planningMutedTextColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  chip,
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: planningMutedTextColor,
                  ),
                ],
              ),
              if (actions != null) ...[
                const SizedBox(height: 10),
                actions!,
              ],
            ],
          ),
        ),
      );
}

/// "Maintenance Ongoing" list item — the report/station header row plus the
/// colored technician/ETA bar underneath (green while on site or scheduled,
/// red once delayed).
class AdminMaintenanceListTile extends StatelessWidget {
  const AdminMaintenanceListTile({
    super.key,
    required this.title,
    required this.location,
    required this.reportedOnLabel,
    required this.statusChip,
    required this.statusColor,
    this.photoUrl,
    this.technicianName,
    this.etaLabel,
    this.delayed = false,
    this.onTap,
  });

  final String title;
  final String location;
  final String reportedOnLabel;
  final Widget statusChip;
  final Color statusColor;
  final String? photoUrl;
  final String? technicianName;
  final String? etaLabel;
  final bool delayed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: photoUrl == null
                          ? Container(
                              color: planningMutedTextColor.withValues(alpha: .1),
                              child: const Icon(
                                Icons.build_outlined,
                                color: planningMutedTextColor,
                              ),
                            )
                          : Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color:
                                    planningMutedTextColor.withValues(alpha: .1),
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: planningMutedTextColor,
                                ),
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
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: planningTextColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                                location.isEmpty ? 'Unknown location' : location,
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
                        const SizedBox(height: 2),
                        Text(
                          reportedOnLabel,
                          style: const TextStyle(
                            color: planningMutedTextColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  statusChip,
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: planningMutedTextColor,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Technician: ${technicianName ?? '--'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: statusColor, fontSize: 12),
                      ),
                    ),
                    Text(
                      etaLabel == null || etaLabel!.isEmpty
                          ? ''
                          : delayed
                              ? 'Delayed by $etaLabel'
                              : 'ETA: $etaLabel',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Compact numbered-page control shared by the admin list screens — same
/// idea as the driver `_Pagination` in `my_reports_screen.dart`, duplicated
/// (not exported — that one's file-private) rather than reworked into a
/// shared widget across driver/admin modules for one small control.
class AdminPagination extends StatelessWidget {
  const AdminPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
  });

  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        for (var i = 0; i < pageCount; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              onTap: () => onPageChanged(i),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == page
                      ? planningTextColor
                      : Colors.transparent,
                  border: Border.all(
                    color: i == page
                        ? planningTextColor
                        : const Color(0xFFE0E4EA),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: i == page ? Colors.white : planningTextColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          onPressed: page < pageCount - 1 ? () => onPageChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// Small "Admin" pill shown in the corner of every admin feedback screen —
/// same shape as `AdminShell`'s own badge (that one's file-private), reused
/// here so pushed sub-screens (Verify Reports, Maintenance Ongoing, Report
/// Details) carry the same chrome as the tab's root dashboard.
class AdminBadge extends StatelessWidget {
  const AdminBadge({super.key});

  static const _green = Color(0xFF00B894);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined, color: _green, size: 14),
            SizedBox(width: 4),
            Text(
              'Admin',
              style: TextStyle(
                color: _green,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

/// "Submitted on {date}" label used across the admin list screens — thin
/// wrapper over the shared `formatReportDate` so call sites read intent.
String submittedOnLabel(DateTime? date) => 'Submitted on ${formatReportDate(date)}';

/// "Reported on {date}" — same date formatter, different verb for the
/// maintenance-tracking context.
String reportedOnLabel(DateTime? date) => 'Reported on ${formatReportDate(date)}';
