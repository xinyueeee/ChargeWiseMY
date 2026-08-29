import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/recent_login_emails_service.dart';
import '../widgets/auth_widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

const _labelColor = Color(0xFF1F2937);
const _hintColor = Color(0xFF9AA5B1);
const _primaryGreen = Color(0xFF00B894);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _recentEmailsService = RecentLoginEmailsService();
  final _emailController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;
  List<String> _recentEmails = const [];

  @override
  void initState() {
    super.initState();
    _loadRecentEmails();
  }

  Future<void> _loadRecentEmails() async {
    final emails = await _recentEmailsService.load();
    if (!mounted) return;
    setState(() => _recentEmails = emails);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocusNode.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await _authService.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // Only remember the email once login actually succeeds, so the
      // suggestion list stays real accounts, not typos.
      _recentEmailsService.remember(_emailController.text);
      // Navigation on success is handled by the auth-state listener in
      // AuthGate, so nothing further to do here.
    } catch (error, stackTrace) {
      debugPrint('Login error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(error))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('Invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    return 'Login failed. Please try again.';
  }

  Future<void> _forgetRecentEmail(String email) async {
    await _recentEmailsService.forget(email);
    if (!mounted) return;
    setState(() {
      _recentEmails = _recentEmails.where((e) => e != email).toList();
    });
  }

  String? _validateEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Email is required';
    if (!emailRegex.hasMatch(text)) return 'Enter a valid email';
    return null;
  }

  /// Email field with autocomplete over the last few addresses that were
  /// actually used to log in successfully on this device - tapping the
  /// field shows them immediately, typing narrows the list. Built on
  /// Autocomplete rather than AuthLabeledField since suggestions need
  /// their own controller wiring and a custom options dropdown.
  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text.rich(
          TextSpan(
            text: 'Email',
            style: TextStyle(
              color: _labelColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            children: [
              TextSpan(text: ' *', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Autocomplete<String>(
          textEditingController: _emailController,
          focusNode: _emailFocusNode,
          optionsBuilder: (value) {
            if (value.text.isEmpty) return _recentEmails;
            final query = value.text.toLowerCase();
            return _recentEmails.where(
              (email) => email.toLowerCase().contains(query),
            );
          },
          onSelected: (selection) => _emailController.text = selection,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: _validateEmail,
              onFieldSubmitted: (_) => onSubmitted(),
              decoration: const InputDecoration(
                hintText: 'Enter your email',
                prefixIcon: Icon(
                  Icons.mail_outline,
                  color: _primaryGreen,
                  size: 20,
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final list = options.toList();
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 220,
                    maxWidth: MediaQuery.sizeOf(context).width - 48,
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final email = list[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.history,
                          size: 18,
                          color: _hintColor,
                        ),
                        title: Text(
                          email,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: 'Remove from suggestions',
                          onPressed: () => _forgetRecentEmail(email),
                        ),
                        onTap: () => onSelected(email),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(
                  title: 'Welcome Back!',
                  subtitle: 'Login to continue your journey.',
                ),
                const SizedBox(height: 32),
                _buildEmailField(),
                const SizedBox(height: 16),
                AuthLabeledField(
                  label: 'Password',
                  controller: _passwordController,
                  hintText: 'Enter your password',
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                    ),
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').isEmpty) return 'Password is required';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const ForgotPasswordScreen(),
                              ),
                            ),
                    child: const Text('Forgot Password?'),
                  ),
                ),
                const SizedBox(height: 8),
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
                      : const Text('Login'),
                ),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        'or',
                        style: TextStyle(color: Color(0xFF9AA5B1)),
                      ),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    GestureDetector(
                      onTap: _submitting
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                      child: const Text(
                        'Register',
                        style: TextStyle(
                          color: Color(0xFF00B894),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
