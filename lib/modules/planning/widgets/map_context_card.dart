import 'package:flutter/material.dart';

import 'planning_widgets.dart';

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
