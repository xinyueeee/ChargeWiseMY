import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'login_screen.dart';

/// Shows the login flow until a Supabase session exists, then hands off to
/// [authenticatedChild]. Keeps the module boundary clean: other modules
/// don't need to know how auth state is determined.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.authenticatedChild});

  final Widget authenticatedChild;

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return StreamBuilder<AuthState>(
      stream: client.auth.onAuthStateChange,
      initialData: AuthState(
        client.auth.currentSession == null
            ? AuthChangeEvent.signedOut
            : AuthChangeEvent.signedIn,
        client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? client.auth.currentSession;
        return session == null ? const LoginScreen() : authenticatedChild;
      },
    );
  }
}
