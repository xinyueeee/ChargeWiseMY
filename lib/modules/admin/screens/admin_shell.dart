import 'package:flutter/material.dart';

import '../../auth/services/auth_service.dart';

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
      appBar: AppBar(
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
        actions: [
          Container(
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
          ),
          IconButton(
            onPressed: () => AuthService().logout(),
            icon: const Icon(Icons.logout, color: _mutedTextColor),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            const _ComingSoon(label: 'Dashboard'),
            const _ComingSoon(label: 'Proposals'),
            const _ComingSoon(label: 'AI Planning'),
            const _ComingSoon(label: 'Feedback Management'),
            const _ComingSoon(label: 'Admin'),
          ],
        ),
      ),
      bottomNavigationBar: _AdminBottomNav(
        selectedIndex: _tabIndex,
        tabs: _tabs,
        onTap: (index) => setState(() => _tabIndex = index),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.construction_outlined, size: 36, color: _mutedTextColor),
          const SizedBox(height: 10),
          Text(
            '$label - coming soon',
            style: const TextStyle(color: _mutedTextColor),
          ),
        ],
      ),
    );
  }
}

class _AdminTab {
  const _AdminTab({required this.icon, required this.label});
  final IconData icon;
  final String label;
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
