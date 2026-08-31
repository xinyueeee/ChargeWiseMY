import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../planning/widgets/planning_widgets.dart';
import '../services/auth_service.dart';
import '../widgets/profile_widgets.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'saved_stations_screen.dart';
import 'vehicle_list_screen.dart';

const _labelColor = Color(0xFF1F2937);
const _hintColor = Color(0xFF9AA5B1);
const _primaryGreen = Color(0xFF00B894);

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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FC),
      appBar: AppBar(
        title: const Text('Profile', style: planningAppBarTitleStyle),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _profileFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      const Text(
                        'Unable to load profile. Check your connection and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final profile = snapshot.data ?? const {};
            final fullName =
                (profile['full_name'] as String?)?.trim().isNotEmpty == true
                    ? profile['full_name'] as String
                    : 'Driver';
            final email = (profile['email'] as String?) ??
                _authService.currentUser?.email ??
                '-';
            final phone = (profile['phone_number'] as String?)?.trim();
            final avatarUrl = (profile['avatar_url'] as String?)?.trim();
            final memberSince = _formatMemberSince(
              profile['created_at'] as String?,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: Text(
                      'View and manage your personal information.',
                      style: TextStyle(color: _hintColor, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                                    color: _primaryGreen.withValues(
                                      alpha: 0.1,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: avatarUrl == null || avatarUrl.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          color: _primaryGreen,
                                          size: 30,
                                        )
                                      : Image.network(
                                          avatarUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              const Icon(
                                            Icons.person,
                                            color: _primaryGreen,
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
                                        color: _labelColor,
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
                                  Text(
                                    fullName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: _labelColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    email,
                                    style: const TextStyle(
                                      color: _hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Member since $memberSince',
                                    style: const TextStyle(
                                      color: _hintColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final updated =
                                    await Navigator.of(context).push(
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
                  const SizedBox(height: 24),
                  const Text(
                    'Personal Information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _labelColor,
                    ),
                  ),
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
                  const SizedBox(height: 24),
                  const Text(
                    'Vehicles',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _labelColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProfileSectionCard(
                    children: [
                      ProfileActionRow(
                        icon: Icons.directions_car_outlined,
                        title: 'My Vehicles',
                        subtitle: 'Manage your registered vehicles.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const VehicleListScreen(),
                          ),
                        ),
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Saved Stations',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _labelColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ProfileSectionCard(
                    children: [
                      ProfileActionRow(
                        icon: Icons.favorite_border,
                        title: 'Saved Stations',
                        subtitle: 'View charging stations you\'ve saved.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SavedStationsScreen(),
                          ),
                        ),
                        showDivider: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Account',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _labelColor,
                    ),
                  ),
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
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _primaryGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: _primaryGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your Information',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _labelColor,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Keep your information updated to enjoy a '
                                'better experience.',
                                style: TextStyle(
                                  color: _hintColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
