import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/driver_navigation_shell.dart';
import '../../auth/services/auth_service.dart';
import '../../planning/admin/screens/admin_planning_dashboard_screen.dart';
import '../../planning/admin/screens/admin_proposal_details_screen.dart';
import '../../planning/admin/screens/admin_proposal_list_screen.dart';
import '../../planning/admin/models/proposal_assessment.dart';
import '../../planning/admin/viewmodels/admin_planning_viewmodel.dart';
import 'admin_feedback_dashboard_screen.dart';
import 'admin_profile_screen.dart';

const _green = Color(0xFF00B894);
const _textColor = Color(0xFF101B40);
const _mutedTextColor = Color(0xFF5F6B82);

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tabIndex = 0;

  static const _tabs = [
    _AdminTab(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _AdminTab(icon: Icons.description_outlined, label: 'Proposals'),
    _AdminTab(icon: Icons.psychology_outlined, label: 'AI Planning'),
    _AdminTab(icon: Icons.flag_outlined, label: 'Feedback'),
    _AdminTab(icon: Icons.shield_outlined, label: 'Admin'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: _tabIndex >= 3
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              foregroundColor: _textColor,
              titleSpacing: 20,
              title: const Text(
                'Admin Portal',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
              ),
              actions: [_adminBadge(), _logoutButton()],
            )
          : null,
      body: SafeArea(
        child: useDriverNavigationRail(context)
            ? Row(
                children: [
                  _AdminNavigationRail(
                    selectedIndex: _tabIndex,
                    tabs: _tabs,
                    onTap: (index) => setState(() => _tabIndex = index),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFE9EDF3)),
                  Expanded(child: _adminTabs()),
                ],
              )
            : _adminTabs(),
      ),
      bottomNavigationBar: useDriverNavigationRail(context)
          ? null
          : _AdminBottomNav(
              selectedIndex: _tabIndex,
              tabs: _tabs,
              onTap: (index) => setState(() => _tabIndex = index),
            ),
    );
  }

  Widget _adminTabs() => IndexedStack(
        index: _tabIndex,
        children: [
          const AdminPlanningDashboardScreen(),
          const AdminProposalListScreen(),
          const _AdminAssistantEntry(),
          const AdminFeedbackDashboardScreen(),
          const AdminProfileScreen(),
        ],
      );

  Widget _adminBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
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

  Widget _logoutButton() => IconButton(
        onPressed: () => AuthService().logout(),
        icon: const Icon(Icons.logout, color: _mutedTextColor),
        tooltip: 'Logout',
      );
}

class _AdminAssistantEntry extends StatelessWidget {
  const _AdminAssistantEntry();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('AI Planning Assistant'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: _textColor,
          elevation: 0,
        ),
        body: Consumer<AdminPlanningViewModel>(
          builder: (context, viewModel, _) {
            final proposals = viewModel.proposals;
            if (proposals.isEmpty) {
              return const Center(
                child: Text(
                  'No proposals are available for assessment.',
                  style: TextStyle(color: _mutedTextColor),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: proposals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final proposal = proposals[index];
                final assessment = viewModel.assessmentFor(proposal);
                return Card(
                  child: ListTile(
                    leading:
                        const Icon(Icons.psychology_outlined, color: _green),
                    title: Text(
                      proposal.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      assessment == null
                          ? 'Assessment is being prepared'
                          : '${assessment.outcome.label} · ${assessment.score}/100',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdminProposalDetailsScreen(
                          proposalId: proposal.id,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class _AdminTab {
  const _AdminTab({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

class _AdminNavigationRail extends StatelessWidget {
  const _AdminNavigationRail({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_AdminTab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => SafeArea(
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: 0,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0x1A00B894),
                  selectedIconTheme: const IconThemeData(color: _green),
                  selectedLabelTextStyle: const TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  unselectedIconTheme:
                      const IconThemeData(color: _mutedTextColor),
                  unselectedLabelTextStyle: const TextStyle(
                    color: _mutedTextColor,
                    fontSize: 12,
                  ),
                  destinations: [
                    for (final tab in tabs)
                      NavigationRailDestination(
                        icon: Icon(tab.icon),
                        label: Text(tab.label),
                      ),
                  ],
                  onDestinationSelected: onTap,
                ),
              ),
            ),
          ),
        ),
      );
}

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.selectedIndex,
    required this.tabs,
    required this.onTap,
  });

  final int selectedIndex;
  final List<_AdminTab> tabs;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9EDF3)),
          boxShadow: const [BoxShadow(color: Color(0x10000000), blurRadius: 8)],
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: _NavItem(tabs[i], selected: i == selectedIndex),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem(this.tab, {required this.selected});

  final _AdminTab tab;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _green : Colors.blueGrey;
    return Semantics(
      selected: selected,
      label: tab.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tab.icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(
            tab.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}
