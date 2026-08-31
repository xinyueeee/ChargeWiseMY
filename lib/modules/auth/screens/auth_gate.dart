import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.authenticatedChild,
    this.adminChild,
    @visibleForTesting Stream<AuthState>? authStateStream,
    @visibleForTesting AuthState? initialAuthState,
    @visibleForTesting Future<String?> Function()? fetchRole,
  })  : _authStateStreamOverride = authStateStream,
        _initialAuthStateOverride = initialAuthState,
        _fetchRoleOverride = fetchRole;

  final Widget authenticatedChild;
  final Widget? adminChild;

  final Stream<AuthState>? _authStateStreamOverride;
  final AuthState? _initialAuthStateOverride;
  final Future<String?> Function()? _fetchRoleOverride;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _cachedRoleUserId;
  Future<String?>? _cachedRoleFuture;

  Future<String?> _roleFutureFor(String userId) {
    if (_cachedRoleUserId != userId || _cachedRoleFuture == null) {
      _cachedRoleUserId = userId;
      _cachedRoleFuture =
          (widget._fetchRoleOverride ?? AuthService().fetchRole)();
    }
    return _cachedRoleFuture!;
  }

  void _retryRoleFetch(String userId) {
    setState(() {
      _cachedRoleUserId = userId;
      _cachedRoleFuture =
          (widget._fetchRoleOverride ?? AuthService().fetchRole)();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget._authStateStreamOverride ??
        Supabase.instance.client.auth.onAuthStateChange;
    final initial = widget._initialAuthStateOverride ??
        AuthState(
          Supabase.instance.client.auth.currentSession == null
              ? AuthChangeEvent.signedOut
              : AuthChangeEvent.signedIn,
          Supabase.instance.client.auth.currentSession,
        );

    return StreamBuilder<AuthState>(
      stream: stream,
      initialData: initial,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        if (session == null) {
          _cachedRoleUserId = null;
          _cachedRoleFuture = null;
          return const LoginScreen();
        }
        if (widget.adminChild == null) return widget.authenticatedChild;

        final userId = session.user.id;
        return FutureBuilder<String?>(
          key: ValueKey(userId),
          future: _roleFutureFor(userId),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (roleSnapshot.hasError) {
              return _RoleLookupErrorScreen(
                onRetry: () => _retryRoleFetch(userId),
              );
            }
            return roleSnapshot.data == 'admin'
                ? widget.adminChild!
                : widget.authenticatedChild;
          },
        );
      },
    );
  }
}

class _RoleLookupErrorScreen extends StatelessWidget {
  const _RoleLookupErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.red),
                const SizedBox(height: 12),
                const Text(
                  'Unable to verify your account. Please check your '
                  'connection and try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
}
