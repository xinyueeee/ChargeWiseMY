import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../auth/screens/change_password_screen.dart';
import '../../auth/screens/edit_profile_screen.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/widgets/profile_widgets.dart';
import '../../feedback/widgets/feedback_widgets.dart' show orange, purple, red;
import '../../planning/admin/screens/admin_proposal_list_screen.dart';
import '../../planning/admin/viewmodels/admin_planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../viewmodels/admin_feedback_viewmodel.dart';
import '../viewmodels/admin_user_viewmodel.dart';
import '../widgets/admin_feedback_widgets.dart';
import 'admin_feedback_history_screen.dart';
import 'admin_maintenance_list_screen.dart';
import 'admin_manage_users_screen.dart';

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _formatMemberSince(String? isoDate) {
  if (isoDate == null) return '-';
  final date = DateTime.tryParse(isoDate);
  if (date == null) return '-';
  return '${date.day} ${_monthNames[date.month - 1]} ${date.year}';
}

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _authService = AuthService();
  final _imagePicker = ImagePicker();

  late Future<Map<String, dynamic>?> _profileFuture;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authService.fetchProfile();
  }

  void _reload() {
    setState(() {
      _profileFuture = _authService.fetchProfile();
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      await _authService.uploadAvatar(file);
      _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not upload photo. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Log Out',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _authService.logout();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not log out. Please try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openHistory({int initialTabIndex = 0}) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AdminFeedbackHistoryScreen(initialTabIndex: initialTabIndex),
        ),
      );

  void _openMaintenance() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminMaintenanceListScreen(),
        ),
      );

  void _openProposals() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminProposalListScreen(),
        ),
      );

  void _openManageUsers() => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminManageUsersScreen(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const PlanningLoadingState(message: 'Loading admin profile…');
        }
        if (snapshot.hasError) {
          return Padding(
            padding: planningPagePadding,
            child: PlanningErrorState(
              message: 'Unable to load profile. Check your connection and '
                  'try again.',
              onRetry: _reload,
            ),
          );
        }

        final profile = snapshot.data ?? const {};
        final fullName =
            (profile['full_name'] as String?)?.trim().isNotEmpty == true
                ? profile['full_name'] as String
                : 'Admin';
        final email = (profile['email'] as String?) ??
            _authService.currentUser?.email ??
            '-';
        final phone = (profile['phone_number'] as String?)?.trim();
        final avatarUrl = (profile['avatar_url'] as String?)?.trim();
        final memberSince = _formatMemberSince(
          profile['created_at'] as String?,
        );

        return ListView(
          padding: planningPagePadding.copyWith(bottom: 100),
          children: [
            const PlanningSectionTitle(
              'Admin Profile',
              subtitle: 'Your account details and activity overview.',
            ),
            planningSectionGap,
            ProfileSectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              color: green.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: green,
                                    size: 30,
                                  )
                                : Image.network(
                                    avatarUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      color: green,
                                      size: 30,
                                    ),
                                  ),
                          ),
                          if (_uploadingAvatar)
                            Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap: _uploadingAvatar
                                  ? null
                                  : _pickAndUploadAvatar,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFE9EDF3),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt_outlined,
                                  size: 12,
                                  color: planningTextColor,
                                ),
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
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    fullName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: planningTextColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const AdminBadge(),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              email,
                              style: const TextStyle(
                                color: planningMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Member since $memberSince',
                              style: const TextStyle(
                                color: planningMutedTextColor,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final updated = await Navigator.of(context).push(
                            MaterialPageRoute<bool>(
                              builder: (_) => EditProfileScreen(
                                fullName: fullName,
                                phoneNumber: phone ?? '',
                              ),
                            ),
                          );
                          if (updated == true) _reload();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Profile'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            planningSectionGap,
            const PlanningSectionTitle('Admin Activity'),
            const SizedBox(height: 10),
            Consumer<AdminFeedbackViewModel>(
              builder: (context, feedbackVm, __) {
                final planningVm = context.watch<AdminPlanningViewModel>();
                final userVm = context.watch<AdminUserViewModel>();
                if (feedbackVm.loading) {
                  return const PlanningLoadingState(
                    message: 'Loading activity…',
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 10.0;
                    final columns = constraints.maxWidth >= 420 ? 4 : 2;
                    final tileWidth =
                        (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.assignment_turned_in_outlined,
                            value: '${feedbackVm.verifiedCount}',
                            label: 'Reports Verified',
                            color: blue,
                            onTap: () => _openHistory(initialTabIndex: 2),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.check_circle_outline,
                            value: '${feedbackVm.resolvedCount}',
                            label: 'Reports Resolved',
                            color: green,
                            onTap: () => _openHistory(initialTabIndex: 4),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.fact_check_outlined,
                            value:
                                '${planningVm.approvedProposalCount + planningVm.rejectedProposalCount}',
                            label: 'Proposals Reviewed',
                            color: purple,
                            onTap: _openProposals,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.build_outlined,
                            value: '${feedbackVm.maintenanceRecords.length}',
                            label: 'Maintenance Records',
                            color: orange,
                            onTap: _openMaintenance,
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: AdminStatTile(
                            icon: Icons.manage_accounts_outlined,
                            value: '${userVm.totalCount}',
                            label: 'Manage Users',
                            color: red,
                            onTap: _openManageUsers,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
            planningSectionGap,
            const PlanningSectionTitle('Personal Information'),
            const SizedBox(height: 10),
            ProfileSectionCard(
              children: [
                ProfileInfoRow(
                  icon: Icons.person_outline,
                  label: 'Full Name',
                  value: fullName,
                ),
                ProfileInfoRow(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  value: email,
                ),
                ProfileInfoRow(
                  icon: Icons.phone_outlined,
                  label: 'Phone Number',
                  value: (phone == null || phone.isEmpty) ? '-' : phone,
                ),
                ProfileInfoRow(
                  icon: Icons.calendar_today_outlined,
                  label: 'Member Since',
                  value: memberSince,
                  showDivider: false,
                ),
              ],
            ),
            planningSectionGap,
            const PlanningSectionTitle('Account'),
            const SizedBox(height: 10),
            ProfileSectionCard(
              children: [
                ProfileActionRow(
                  icon: Icons.lock_outline,
                  title: 'Change Password',
                  subtitle: 'Update your password for better security.',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChangePasswordScreen(),
                    ),
                  ),
                ),
                ProfileActionRow(
                  icon: Icons.logout,
                  title: 'Logout',
                  subtitle: 'Sign out from your account.',
                  onTap: _logout,
                  showDivider: false,
                  destructive: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
