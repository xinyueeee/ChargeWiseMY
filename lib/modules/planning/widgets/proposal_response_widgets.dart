import 'package:flutter/material.dart';

import '../models/proposal.dart';
import 'planning_widgets.dart';

class CommunityResponseSummary extends StatelessWidget {
  const CommunityResponseSummary({
    super.key,
    required this.proposal,
    this.compact = false,
  });

  final Proposal proposal;
  final bool compact;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: compact ? 12 : 18,
        runSpacing: 6,
        children: [
          _ResponseCount(
            icon: Icons.thumb_up_alt_outlined,
            count: proposal.supportCount,
            label: 'Support',
            compact: compact,
          ),
          _ResponseCount(
            icon: Icons.thumb_down_alt_outlined,
            count: proposal.opposeCount,
            label: 'Not Support',
            compact: compact,
          ),
        ],
      );
}

class ProposalReactionButtons extends StatelessWidget {
  const ProposalReactionButtons({
    super.key,
    required this.selected,
    required this.busy,
    required this.onChanged,
  });

  final ProposalReaction? selected;
  final bool busy;
  final ValueChanged<ProposalReaction?> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final vertical = constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final support = _ReactionButton(
            reaction: ProposalReaction.support,
            selected: selected == ProposalReaction.support,
            busy: busy,
            onPressed: () => onChanged(
              selected == ProposalReaction.support
                  ? null
                  : ProposalReaction.support,
            ),
          );
          final oppose = _ReactionButton(
            reaction: ProposalReaction.oppose,
            selected: selected == ProposalReaction.oppose,
            busy: busy,
            onPressed: () => onChanged(
              selected == ProposalReaction.oppose
                  ? null
                  : ProposalReaction.oppose,
            ),
          );
          if (vertical) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [support, const SizedBox(height: 10), oppose],
            );
          }
          return Row(
            children: [
              Expanded(child: support),
              const SizedBox(width: 10),
              Expanded(child: oppose),
            ],
          );
        },
      );
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.reaction,
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final ProposalReaction reaction;
  final bool selected;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final support = reaction == ProposalReaction.support;
    final color = support ? green : const Color(0xFFB04444);
    return Semantics(
      selected: selected,
      button: true,
      label: '${support ? 'Support' : 'Not Support'} proposal'
          '${selected ? ', selected' : ''}',
      child: OutlinedButton.icon(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: selected ? color.withValues(alpha: .1) : null,
          side: BorderSide(color: selected ? color : const Color(0xFFD5DCE4)),
          minimumSize: const Size(0, 48),
        ),
        icon: busy && selected
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                support
                    ? selected
                        ? Icons.thumb_up_alt
                        : Icons.thumb_up_alt_outlined
                    : selected
                        ? Icons.thumb_down_alt
                        : Icons.thumb_down_alt_outlined,
              ),
        label: Text(
          support ? 'Support' : 'Not Support',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ResponseCount extends StatelessWidget {
  const _ResponseCount({
    required this.icon,
    required this.count,
    required this.label,
    required this.compact,
  });

  final IconData icon;
  final int count;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 16 : 19, color: green),
          const SizedBox(width: 5),
          Text(
            '$count $label',
            style: TextStyle(
              color: planningTextColor,
              fontSize: compact ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
