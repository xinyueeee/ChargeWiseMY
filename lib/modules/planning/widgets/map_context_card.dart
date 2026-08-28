import 'package:flutter/material.dart';

import 'planning_widgets.dart';

/// Compact strip of metrics ("1,374 locations · 4,161 installed chargers …")
/// shown directly under the Interactive Map.
///
/// Extracted from `PlanningDashboardScreen` (alongside `CompactMapLegend`)
/// so it is directly constructible in a widget test, and so this file's
/// height can be measured honestly: it is a [Wrap], and a `Wrap` reflows to
/// however many lines its content needs at the width it is actually given —
/// anywhere from one line (a wide tablet pane) to three (a narrow phone-
/// landscape pane). That variability is exactly what the old fixed
/// `chromeHeight` constant in `_buildLandscapeDashboard` could not predict:
/// measured directly, this card's natural height ranges from about 81px
/// (550px wide) up to about 166px (260px wide) — nowhere close to a single
/// guessed constant.
class MapContextCard extends StatelessWidget {
  const MapContextCard({
    super.key,
    required this.locations,
    required this.chargers,
    required this.activeProposals,
    required this.priorityAreas,
    required this.plannedLocations,
  });

  final int locations;
  final int chargers;
  final int activeProposals;
  final int priorityAreas;
  final int plannedLocations;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Wrap(
          spacing: 16,
          runSpacing: 10,
          children: [
            MapContextMetric(value: '$locations', label: 'locations'),
            MapContextMetric(value: '$chargers', label: 'installed chargers'),
            MapContextMetric(
              value: '$activeProposals',
              label: 'active proposals',
            ),
            MapContextMetric(
              value: '$priorityAreas',
              label: 'priority areas',
            ),
            MapContextMetric(
              value: '$plannedLocations',
              label: 'MEVnet planned',
            ),
          ],
        ),
      );
}

class MapContextMetric extends StatelessWidget {
  const MapContextMetric({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => RichText(
        // A hand-built RichText does not automatically read the ambient
        // text scale the way a Text widget does — without this, the metric
        // ignores the device's text-size setting entirely, unlike every
        // other label on this screen. Fixed as part of this pass, not the
        // overflow itself, but found while extracting this widget.
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(
          style: const TextStyle(color: planningMutedTextColor, fontSize: 13),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(
                color: planningTextColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: label),
          ],
        ),
      );
}
