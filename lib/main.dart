import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          ),
          home: const PlanningDashboardScreen(),
        ),
      );
}
