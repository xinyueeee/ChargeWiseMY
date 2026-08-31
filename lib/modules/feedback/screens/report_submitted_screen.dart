import 'package:flutter/material.dart';

import '../../planning/widgets/planning_widgets.dart';
import '../widgets/feedback_widgets.dart';
import 'my_reports_screen.dart';

class ReportSubmittedScreen extends StatelessWidget {
  const ReportSubmittedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: planningPagePadding,
            child: Column(
              children: [
                const SizedBox(height: 8),
                const ReportStepIndicator(currentStep: 3),
                const Spacer(),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: .1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: green,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Report Submitted!',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: planningTextColor,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Thank you for helping improve our charging network. '
                  "We'll review your report and update its status shortly.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: planningMutedTextColor,
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyReportsScreen(),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('View My Reports'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: const Text('Done'),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
}
