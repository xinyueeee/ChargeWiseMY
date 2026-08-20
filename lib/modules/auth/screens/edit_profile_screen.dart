import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/auth_widgets.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.fullName,
    required this.phoneNumber,
  });

  final String fullName;
  final String phoneNumber;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  late final _fullNameController =
      TextEditingController(text: widget.fullName);
  late final _phoneController = TextEditingController(text: widget.phoneNumber);

  bool _submitting = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await _authService.updateProfile(
        fullName: _fullNameController.text,
        phoneNumber: _phoneController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update profile. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthLabeledField(
                  label: 'Full Name',
                  controller: _fullNameController,
                  hintText: 'Enter your full name',
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Full name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Phone Number',
                  controller: _phoneController,
                  hintText: 'e.g. 012-345 6789',
                  prefixIcon: Icons.phone_outlined,
                  required: false,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    if (!RegExp(r'^[0-9\-\s]+$').hasMatch(text)) {
                      return 'Enter a valid Malaysian phone number';
                    }
                    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
                    final validLength = digits.length == 10 ||
                        digits.length == 11;
                    if (!digits.startsWith('01') || !validLength) {
                      return 'Enter a valid Malaysian phone number '
                          '(e.g. 012-345 6789)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save Changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
