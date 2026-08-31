import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/navigation/app_route_observer.dart';
import 'core/navigation/driver_shell.dart';
import 'modules/admin/screens/admin_shell.dart';
import 'modules/admin/services/feedback_admin_repository.dart';
import 'modules/admin/services/user_admin_repository.dart';
import 'modules/admin/viewmodels/admin_feedback_viewmodel.dart';
import 'modules/admin/viewmodels/admin_user_viewmodel.dart';
import 'modules/auth/screens/auth_gate.dart';
import 'modules/feedback/services/feedback_repository.dart';
import 'modules/feedback/viewmodels/feedback_viewmodel.dart';
import 'modules/planning/admin/viewmodels/admin_planning_viewmodel.dart';
import 'modules/planning/services/planning_repository.dart';
import 'modules/planning/viewmodels/planning_viewmodel.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ffqtkpoeuqjuihqdzmsc.supabase.co',
    publishableKey: 'sb_publishable_RZVErCEwcPADZuWBWqGtKg_BxkWHRj1',
  );

  runApp(const ChargeWiseApp());

  unawaited(NotificationService().init());
}

class ChargeWiseApp extends StatelessWidget {
  const ChargeWiseApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => PlanningViewModel(PlanningRepository())..load(),
          ),
          ChangeNotifierProvider(
            create: (_) => FeedbackViewModel(FeedbackRepository())..load(),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                AdminFeedbackViewModel(FeedbackAdminRepository())..load(),
          ),
          ChangeNotifierProvider(
            create: (_) => AdminUserViewModel(UserAdminRepository())..load(),
          ),
        ],
        child: Builder(
          builder: (planningContext) => ChangeNotifierProvider(
            create: (_) => AdminPlanningViewModel(
              planningContext.read<PlanningViewModel>(),
            ),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'ChargeWise MY',
              theme: ThemeData(
                useMaterial3: false,
                scaffoldBackgroundColor: Colors.white,
                fontFamily: 'Arial',
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF00B894),
                ),
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xFFF8F9FC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFDDE3EA)),
                  ),
                ),
                elevatedButtonTheme: ElevatedButtonThemeData(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                snackBarTheme: const SnackBarThemeData(
                  behavior: SnackBarBehavior.floating,
                ),
              ),
              navigatorObservers: [appRouteObserver],
              home: AuthGate(
                authenticatedChild: DriverShell(),
                adminChild: const AdminShell(),
              ),
            ),
          ),
        ),
      );
}
