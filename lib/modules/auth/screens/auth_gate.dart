import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'login_screen.dart';


class AuthGate extends StatelessWidget {
  const AuthGate({
    super.key,
    required this.authenticatedChild,
    this.adminChild,
  });

  final Widget authenticatedChild;
  final Widget? adminChild;

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
        if (session == null) return const LoginScreen();
        if (adminChild == null) return authenticatedChild;

        return FutureBuilder<String?>(
          key: ValueKey(session.user.id),
          future: AuthService().fetchRole(),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return roleSnapshot.data == 'admin'
                ? adminChild!
                : authenticatedChild;
          },
        );
      },
    );
  }
}
