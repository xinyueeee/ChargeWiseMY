import 'package:flutter/material.dart';

import 'planning_widgets.dart';

class CompactMapLegend extends StatelessWidget {
  const CompactMapLegend({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.showExisting,
    required this.showMevnetProposed,
    required this.showCommunityProposals,
    required this.onExistingChanged,
    required this.onMevnetProposedChanged,
    required this.onCommunityProposalsChanged,
    required this.maxHeight,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final bool showExisting;
  final bool showMevnetProposed;
  final bool showCommunityProposals;
  final ValueChanged<bool> onExistingChanged;
  final ValueChanged<bool> onMevnetProposedChanged;
  final ValueChanged<bool> onCommunityProposalsChanged;

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final header = InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 20),
            const SizedBox(width: 6),
            const Text(
              'Layers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 3),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
            ),
          ],
        ),
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(0.0, maxHeight)),
      child: AppCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (expanded) ...[
              const Divider(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(6, 2, 8, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MapLayerToggle(
                          asset: 'assets/icons/station_lightning.png',
                          label: 'Existing',
                          value: showExisting,
                          onChanged: onExistingChanged,
                        ),
                        const SizedBox(height: 7),
                        MapLayerToggle(
                          icon: Icons.location_on_outlined,
                          iconColor: const Color(0xFF4F6EF7),
                          label: 'MEVnet Proposed',
                          value: showMevnetProposed,
                          onChanged: onMevnetProposedChanged,
                        ),
                        const SizedBox(height: 7),
                        MapLayerToggle(
                          asset: 'assets/icons/proposed_station.png',
                          label: 'Community Proposals',
                          value: showCommunityProposals,
                          onChanged: onCommunityProposalsChanged,
                        ),
                        const Padding(
                          padding: EdgeInsets.only(left: 25, top: 2),
                          child: Text(
                            'Blue active · Violet approved',
                            style: TextStyle(
                              color: planningMutedTextColor,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MapLayerToggle extends StatelessWidget {
  const MapLayerToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.asset,
    this.icon,
    this.iconColor,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? asset;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 20,
              child: Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: (next) => onChanged(next ?? value),
              ),
            ),
            const SizedBox(width: 5),
            if (asset != null)
              Image.asset(asset!, width: 17, height: 17)
            else
              Icon(icon, size: 17, color: iconColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
