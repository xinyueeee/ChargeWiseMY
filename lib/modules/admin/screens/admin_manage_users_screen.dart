import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../feedback/widgets/feedback_widgets.dart' show red;
import '../../planning/widgets/planning_widgets.dart';
import '../models/admin_user_summary.dart';
import '../viewmodels/admin_user_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';

class AdminManageUsersScreen extends StatefulWidget {
  const AdminManageUsersScreen({super.key});

  @override
  State<AdminManageUsersScreen> createState() => _AdminManageUsersScreenState();
}

class _AdminManageUsersScreenState extends State<AdminManageUsersScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = ['All', 'Active', 'Deactivated'];

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabController.indexIsChanging) setState(() {});
      });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUserSummary> _applyFilters(List<AdminUserSummary> source) {
    final tabLabel = _tabs[_tabController.index];
    final query = _query.trim().toLowerCase();
    return source.where((user) {
      final matchesTab = switch (tabLabel) {
        'Active' => user.isActive,
        'Deactivated' => !user.isActive,
        _ => true,
      };
      final matchesQuery = query.isEmpty ||
          user.fullName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query);
      return matchesTab && matchesQuery;
    }).toList();
  }

  Future<void> _confirmDeactivate(
    BuildContext context,
    AdminUserViewModel vm,
    AdminUserSummary user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: Text(
          '${user.fullName} will no longer be able to log in until '
          'reactivated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Deactivate',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await vm.setStatus(user, 'deactivated');
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _activate(
    BuildContext context,
    AdminUserViewModel vm,
    AdminUserSummary user,
  ) async {
    final error = await vm.setStatus(user, 'active');
    if (!context.mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: const BackButton(),
          titleSpacing: 0,
          title: const Text(
            'Manage Users',
            style: TextStyle(
              color: planningTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          backgroundColor: Colors.white,
          foregroundColor: planningTextColor,
          elevation: 0,
          actions: const [
            Padding(padding: EdgeInsets.only(right: 16), child: AdminBadge()),
          ],
        ),
        body: Consumer<AdminUserViewModel>(
          builder: (context, vm, __) {
            if (vm.loading) {
              return const PlanningLoadingState(message: 'Loading users…');
            }
            if (vm.errorMessage != null) {
              return Padding(
                padding: planningPagePadding,
                child: PlanningErrorState(
                  message: vm.errorMessage!,
                  onRetry: vm.load,
                ),
              );
            }

            final filtered = _applyFilters(vm.users);

            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: planningPagePadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search by name or email',
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TabBar(
                          controller: _tabController,
                          isScrollable: true,
                          labelColor: green,
                          unselectedLabelColor: planningMutedTextColor,
                          indicatorColor: green,
                          tabAlignment: TabAlignment.start,
                          tabs: [for (final tab in _tabs) Tab(text: tab)],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'No users match this filter.',
                              style: TextStyle(color: planningMutedTextColor),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: vm.load,
                            child: ListView.separated(
                              padding: planningPagePadding,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final user = filtered[index];
                                return _UserTile(
                                  user: user,
                                  busy: vm.isUpdating(user),
                                  onActivate: () =>
                                      _activate(context, vm, user),
                                  onDeactivate: () =>
                                      _confirmDeactivate(context, vm, user),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      );
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.busy,
    required this.onActivate,
    required this.onDeactivate,
  });

  final AdminUserSummary user;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline, color: green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: planningTextColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: planningMutedTextColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _RoleTag(user.isAdmin ? 'Admin' : 'Driver'),
                      _StatusTag(isActive: user.isActive),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 108,
              child: busy
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : user.isActive
                      ? OutlinedButton.icon(
                          onPressed: onDeactivate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: red,
                            side: const BorderSide(color: red),
                          ),
                          icon: const Icon(Icons.block_outlined, size: 16),
                          label: const Text('Deactivate'),
                        )
                      : OutlinedButton.icon(
                          onPressed: onActivate,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: green,
                            side: const BorderSide(color: green),
                          ),
                          icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                          label: const Text('Activate'),
                        ),
            ),
          ],
        ),
      );
}

class _RoleTag extends StatelessWidget {
  const _RoleTag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: blue.withValues(alpha: .24)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: blue,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.isActive});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? green : red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle_outline : Icons.block_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            isActive ? 'Active' : 'Deactivated',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
