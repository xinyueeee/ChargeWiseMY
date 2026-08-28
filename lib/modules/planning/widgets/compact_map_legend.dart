import 'package:flutter/material.dart';

import 'planning_widgets.dart';

/// Floating "Layers" control drawn over the Interactive Map.
///
/// Extracted from `PlanningDashboardScreen` so it is directly constructible
/// in a widget test without a real `GoogleMap` platform view or a
/// `PlanningViewModel`/`Provider` tree.
///
/// [maxHeight] must be the exact height of the map `Stack` this legend is
/// positioned over (the same `height` passed to `MapPanel`) minus whatever
/// margin the caller leaves around it. The whole card — header included — is
/// hard-capped to that height, so it can never grow taller than the map it
/// floats on: a naturally-sized expanded `Column` was proven to exceed the
/// map's height in short landscape (as little as 96px), which is exactly
/// what produced the reported overflow. Only the toggle list below the
/// header scrolls; the header itself always stays reachable so the legend
/// can always be collapsed again.
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

  /// The exact height of the map region this legend floats over. A hard
  /// ceiling, never a fraction guessed in the abstract — the legend simply
  /// cannot be sized correctly without knowing the space it actually has.
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
      // A hard cap, not a suggestion: whatever this card's content wants to
      // be, it is never allowed to exceed the map it sits on top of.
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(0.0, maxHeight)),
      child: AppCard(
        padding: const EdgeInsets.all(6),
        child: Column(
          // `min`, not the Column default `max`: a collapsed legend must stay
          // its own natural (small) size rather than being stretched to fill
          // maxHeight, which would otherwise paint as a large empty card.
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            if (expanded) ...[
              const Divider(height: 10),
              // `Flexible` (loose), not `Expanded`: short content keeps the
              // card compact; content that would overflow scrolls instead
              // of pushing the card past `maxHeight`.
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
