import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/navigation/app_route_observer.dart';
import 'modules/planning/admin/screens/admin_planning_dashboard_screen.dart';
import 'modules/planning/admin/viewmodels/admin_planning_viewmodel.dart';
import 'modules/planning/screens/planning_dashboard_screen.dart';
import 'modules/planning/services/planning_repository.dart';
import 'modules/planning/viewmodels/planning_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ffqtkpoeuqjuihqdzmsc.supabase.co',
    publishableKey: 'sb_publishable_RZVErCEwcPADZuWBWqGtKg_BxkWHRj1',
  );

  runApp(const ChargeWiseApp());
}

class ChargeWiseApp extends StatelessWidget {
  const ChargeWiseApp({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => PlanningViewModel(PlanningRepository())..load(),
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
          routes: {
            '/admin': (_) => const _AdminPlanningEntry(),
          },
          home: const _PlanningEntry(),
        ),
      );
}

class _PlanningEntry extends StatelessWidget {
  const _PlanningEntry();

  static const bool _adminMode = bool.fromEnvironment(
    'CHARGEWISE_ADMIN',
    defaultValue: false,
  );

  @override
  Widget build(BuildContext context) => _adminMode
      ? const _AdminPlanningEntry()
      : const PlanningDashboardScreen();
}

class _AdminPlanningEntry extends StatelessWidget {
  const _AdminPlanningEntry();

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => AdminPlanningViewModel(
          context.read<PlanningViewModel>(),
        ),
        child: const AdminPlanningDashboardScreen(),
      );
}
