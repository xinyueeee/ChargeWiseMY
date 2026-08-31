import 'dart:async';

import 'package:chargewise_my/modules/auth/screens/auth_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void _mockEmptySharedPreferences() {
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getAll') return <String, Object>{};
    return null;
  });
}

User _fakeUser(String id) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.utc(2026).toIso8601String(),
    );

Session _fakeSession(String userId) => Session(
      accessToken: 'fake-access-token-not-a-real-jwt',
      tokenType: 'bearer',
      user: _fakeUser(userId),
    );

AuthState _signedIn(String userId) =>
    AuthState(AuthChangeEvent.signedIn, _fakeSession(userId));

AuthState _initialSession(String userId) =>
    AuthState(AuthChangeEvent.initialSession, _fakeSession(userId));

const _signedOut = AuthState(AuthChangeEvent.signedOut, null);

class _FakeRoleFetcher {
  _FakeRoleFetcher(this._roleFor);

  final String? Function() _roleFor;
  int callCount = 0;
  bool throwOnNextCall = false;

  Future<String?> call() async {
    callCount++;
    if (throwOnNextCall) {
      throwOnNextCall = false;
      throw Exception('role lookup failed');
    }
    return _roleFor();
  }
}

Widget _harness({
  required Stream<AuthState> stream,
  required AuthState initial,
  required Future<String?> Function() fetchRole,
}) =>
    MaterialApp(
      home: AuthGate(
        authenticatedChild: const Scaffold(body: Text('HOME')),
        adminChild: const Scaffold(body: Text('ADMIN')),
        authStateStream: stream,
        initialAuthState: initial,
        fetchRole: fetchRole,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _mockEmptySharedPreferences();
    await Supabase.initialize(
      url: 'https://example.invalid',
      publishableKey: 'test-publishable-key',
    );
  });

  group('A/B: exactly one fetchRole call across initialData + initialSession',
      () {
    testWidgets(
      'initial authenticated build followed by the real initialSession '
      'event calls fetchRole exactly once',
      (tester) async {
        final controller = StreamController<AuthState>.broadcast();
        addTearDown(controller.close);
        final role = _FakeRoleFetcher(() => 'driver');

        await tester.pumpWidget(
          _harness(
            stream: controller.stream,
            initial: _signedIn('user-1'),
            fetchRole: role.call,
          ),
        );
        await tester.pump();

        controller.add(_initialSession('user-1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));

        expect(
          role.callCount,
          1,
          reason: 'both builds are for the same user id; the second must '
              'reuse the cached Future rather than firing a new query',
        );
      },
    );

    testWidgets(
      'further rebuilds for the same user still call fetchRole exactly once',
      (tester) async {
        final controller = StreamController<AuthState>.broadcast();
        addTearDown(controller.close);
        final role = _FakeRoleFetcher(() => 'driver');

        await tester.pumpWidget(
          _harness(
            stream: controller.stream,
            initial: _signedIn('user-1'),
            fetchRole: role.call,
          ),
        );
        await tester.pump();

        for (var i = 0; i < 3; i++) {
          controller.add(_signedIn('user-1'));
          await tester.pump();
        }

        expect(role.callCount, 1);
      },
    );
  });

  group('C: logout clears the cached role', () {
    testWidgets('signing out shows LoginScreen, not a stale role',
        (tester) async {
      final controller = StreamController<AuthState>.broadcast();
      addTearDown(controller.close);
      final role = _FakeRoleFetcher(() => 'admin');

      await tester.pumpWidget(
        _harness(
          stream: controller.stream,
          initial: _signedIn('user-1'),
          fetchRole: role.call,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('ADMIN'), findsOneWidget);

      controller.add(_signedOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('ADMIN'), findsNothing);
      expect(find.text('HOME'), findsNothing);
    });
  });

  group('D: a different user signing in fetches a fresh role', () {
    testWidgets('user switch invalidates the cache and refetches',
        (tester) async {
      final controller = StreamController<AuthState>.broadcast();
      addTearDown(controller.close);
      final roles = {'user-1': 'driver', 'user-2': 'admin'};

      var callCount = 0;
      Future<String?> fetchRole() async {
        callCount++;
        return callCount == 1 ? roles['user-1'] : roles['user-2'];
      }

      await tester.pumpWidget(
        _harness(
          stream: controller.stream,
          initial: _signedIn('user-1'),
          fetchRole: fetchRole,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(callCount, 1);

      controller.add(_initialSession('user-1'));
      await tester.pump();
      expect(callCount, 1);

      controller.add(_signedIn('user-2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(callCount, 2);
    });

    testWidgets('Admin -> logout -> Driver resolves the new role correctly',
        (tester) async {
      final controller = StreamController<AuthState>.broadcast();
      addTearDown(controller.close);
      var whichUser = 'admin-user';
      Future<String?> fetchRole() async =>
          whichUser == 'admin-user' ? 'admin' : 'driver';

      await tester.pumpWidget(
        _harness(
          stream: controller.stream,
          initial: _signedIn('admin-user'),
          fetchRole: fetchRole,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('ADMIN'), findsOneWidget);

      controller.add(_signedOut);
      await tester.pump();

      whichUser = 'driver-user';
      controller.add(_signedIn('driver-user'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ADMIN'), findsNothing);
    });

    testWidgets('Driver -> logout -> Admin resolves the new role correctly',
        (tester) async {
      final controller = StreamController<AuthState>.broadcast();
      addTearDown(controller.close);
      var whichUser = 'driver-user';
      Future<String?> fetchRole() async =>
          whichUser == 'driver-user' ? 'driver' : 'admin';

      await tester.pumpWidget(
        _harness(
          stream: controller.stream,
          initial: _signedIn('driver-user'),
          fetchRole: fetchRole,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('HOME'), findsOneWidget);

      controller.add(_signedOut);
      await tester.pump();

      whichUser = 'admin-user';
      controller.add(_signedIn('admin-user'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });
  });

  group('E/F: role resolution', () {
    testWidgets('admin role resolves to adminChild', (tester) async {
      await tester.pumpWidget(
        _harness(
          stream: const Stream<AuthState>.empty(),
          initial: _signedIn('user-1'),
          fetchRole: () async => 'admin',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });

    testWidgets('driver role resolves to authenticatedChild', (tester) async {
      await tester.pumpWidget(
        _harness(
          stream: const Stream<AuthState>.empty(),
          initial: _signedIn('user-1'),
          fetchRole: () async => 'driver',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('ADMIN'), findsNothing);
    });
  });

  group('G/H: a failed role lookup never grants or silently denies access', () {
    testWidgets('failed lookup does not resolve to adminChild', (tester) async {
      await tester.pumpWidget(
        _harness(
          stream: const Stream<AuthState>.empty(),
          initial: _signedIn('user-1'),
          fetchRole: () async => throw Exception('network error'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('ADMIN'), findsNothing);
    });

    testWidgets(
      'failed lookup does not silently fall through to authenticatedChild '
      'either — it shows an explicit retry state',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            stream: const Stream<AuthState>.empty(),
            initial: _signedIn('user-1'),
            fetchRole: () async => throw Exception('network error'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));

        expect(find.text('HOME'), findsNothing);
        expect(find.text('ADMIN'), findsNothing);
        expect(find.text('Retry'), findsOneWidget);
      },
    );

    testWidgets('retry after a failure re-fetches and can then succeed',
        (tester) async {
      var attempt = 0;
      Future<String?> fetchRole() async {
        attempt++;
        if (attempt == 1) throw Exception('network error');
        return 'admin';
      }

      await tester.pumpWidget(
        _harness(
          stream: const Stream<AuthState>.empty(),
          initial: _signedIn('user-1'),
          fetchRole: fetchRole,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(find.text('ADMIN'), findsOneWidget);
      expect(attempt, 2);
    });
  });

  group('unauthenticated', () {
    testWidgets('no session shows LoginScreen without calling fetchRole',
        (tester) async {
      final role = _FakeRoleFetcher(() => 'admin');

      await tester.pumpWidget(
        _harness(
          stream: const Stream<AuthState>.empty(),
          initial: _signedOut,
          fetchRole: role.call,
        ),
      );
      await tester.pump();

      expect(find.text('HOME'), findsNothing);
      expect(find.text('ADMIN'), findsNothing);
      expect(role.callCount, 0);
    });
  });
}
