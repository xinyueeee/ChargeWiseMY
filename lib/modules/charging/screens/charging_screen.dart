import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../services/notification_service.dart';
import '../../home/widgets/station_details_sheet.dart';
import '../../planning/models/proposal.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../services/charging_route_eta_service.dart';
import '../services/charging_service.dart';
import '../viewmodels/reminders_viewmodel.dart';
import '../widgets/charging_widgets.dart';
import 'create_reminder_sheet.dart';
import 'create_session_sheet.dart';

const _malaysiaFallback = LatLng(3.1390, 101.6869);

const _rateMinRm = 0.20;
const _rateMaxRm = 2.00;

const _weekdayShortNames = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

const _weekdayFullNames = {
  1: 'Monday',
  2: 'Tuesday',
  3: 'Wednesday',
  4: 'Thursday',
  5: 'Friday',
  6: 'Saturday',
  7: 'Sunday',
};

String _weeklyRepeatLabel(List<int> repeatDays) {
  if (repeatDays.length == 7) return 'Every day';
  if (repeatDays.isEmpty) return 'Every week';
  final sorted = repeatDays.toList()..sort();
  return sorted.map((d) => _weekdayShortNames[d]).join(', ');
}

String _formatHour12(int hour) {
  final period = hour >= 12 ? 'PM' : 'AM';
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return '$hour12 $period';
}

class _SessionInsights {
  const _SessionInsights({
    required this.typicalWeekday,
    required this.typicalHour,
    required this.avgCadenceDays,
    required this.daysSinceLastSession,
    required this.lastSessionStationName,
    required this.lastSessionEnergyKwh,
  });

  final String? typicalWeekday;
  final int? typicalHour;
  final double? avgCadenceDays;
  final int? daysSinceLastSession;
  final String? lastSessionStationName;
  final double? lastSessionEnergyKwh;

  static _SessionInsights? fromSessions(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return null;
    final at =
        sessions.map((s) => DateTime.parse(s['session_at'] as String)).toList();
    final last = sessions.first;
    final daysSinceLast = DateTime.now().difference(at.first).inDays;

    String? typicalWeekday;
    int? typicalHour;
    double? avgCadenceDays;
    if (sessions.length >= 3) {
      final weekdayCounts = <int, int>{};
      final hourCounts = <int, int>{};
      for (final t in at) {
        weekdayCounts[t.weekday] = (weekdayCounts[t.weekday] ?? 0) + 1;
        hourCounts[t.hour] = (hourCounts[t.hour] ?? 0) + 1;
      }
      final modeWeekday = weekdayCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      final modeHour =
          hourCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      typicalWeekday = _weekdayFullNames[modeWeekday];
      typicalHour = modeHour;

      final sortedAsc = at.toList()..sort();
      final gapsHours = <int>[
        for (var i = 1; i < sortedAsc.length; i++)
          sortedAsc[i].difference(sortedAsc[i - 1]).inHours,
      ];
      avgCadenceDays =
          gapsHours.reduce((a, b) => a + b) / gapsHours.length / 24;
    }

    return _SessionInsights(
      typicalWeekday: typicalWeekday,
      typicalHour: typicalHour,
      avgCadenceDays: avgCadenceDays,
      daysSinceLastSession: daysSinceLast,
      lastSessionStationName: last['station_name'] as String?,
      lastSessionEnergyKwh: (last['energy_kwh'] as num?)?.toDouble(),
    );
  }

  String? summaryLine() {
    final weekday = typicalWeekday;
    final hour = typicalHour;
    final cadence = avgCadenceDays;
    if (weekday == null || hour == null || cadence == null) return null;
    final cadenceLabel = cadence < 1.5
        ? 'about once a day'
        : 'about every ${cadence.round()} days';
    final due = daysSinceLastSession != null && daysSinceLastSession! >= cadence
        ? ' It\'s been $daysSinceLastSession days since your last session - '
            'you might be due soon.'
        : '';
    return 'You usually charge on ${weekday}s around ${_formatHour12(hour)}, '
        '$cadenceLabel.$due';
  }
}

const _monthShortNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

class _MonthlyTotal {
  const _MonthlyTotal({required this.monthLabel, required this.rm});

  final String monthLabel;
  final double rm;
}

List<_MonthlyTotal> _monthlyTotals(List<Map<String, dynamic>> sessions) {
  final now = DateTime.now();
  final months = [
    for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
  ];
  final totals = {for (final m in months) m: 0.0};
  for (final session in sessions) {
    final at = DateTime.parse(session['session_at'] as String);
    final bucket = DateTime(at.year, at.month, 1);
    final existing = totals[bucket];
    if (existing != null) {
      totals[bucket] = existing + (session['cost'] as num).toDouble();
    }
  }
  return [
    for (final m in months)
      _MonthlyTotal(monthLabel: _monthShortNames[m.month - 1], rm: totals[m]!),
  ];
}

class ChargingScreen extends StatefulWidget {
  const ChargingScreen({super.key});

  @override
  State<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends State<ChargingScreen> with RouteAware {
  final _service = ChargingService();
  final _notifications = NotificationService();
  final _routeEtaService = const SupabaseChargingRouteEtaService();

  Map<String, RouteEtaResult>? _routeEtaResults;
  List<String>? _routeEtaCandidateIds;
  bool _routeEtaLoading = false;

  final _calcFormKey = GlobalKey<FormState>();
  String _calcChargerType = chargerTypes[1];
  final _calcPowerController = TextEditingController(text: '180');
  final _calcRateController = TextEditingController(text: '1.20');
  int _calcHours = 1;
  int _calcMinutes = 30;
  double? _calcResult;

  Future<List<Map<String, dynamic>>>? _sessionsFuture;
  late final RemindersViewModel _remindersVm;

  LatLng? _userLocation;
  bool _locationUnavailable = false;

  PageRoute<dynamic>? _subscribedRoute;
  final _fireTimers = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _reloadSessions();
    _loadLocation();
    _remindersVm = context.read<RemindersViewModel>();
    _remindersVm.addListener(_scheduleFireTimers);
    if (_remindersVm.reminders != null) {
      _scheduleFireTimers();
    } else {
      _remindersVm.load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is! PageRoute<dynamic> || identical(route, _subscribedRoute)) {
      return;
    }
    if (_subscribedRoute != null) appRouteObserver.unsubscribe(this);
    _subscribedRoute = route;
    appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() => _remindersVm.load();

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _remindersVm.removeListener(_scheduleFireTimers);
    for (final timer in _fireTimers.values) {
      timer.cancel();
    }
    _calcPowerController.dispose();
    _calcRateController.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    setState(() {
      _sessionsFuture = _service.fetchSessions();
    });
  }

  void _scheduleFireTimers() {
    for (final timer in _fireTimers.values) {
      timer.cancel();
    }
    _fireTimers.clear();
    for (final reminder
        in _remindersVm.reminders ?? const <Map<String, dynamic>>[]) {
      final enabled = reminder['enabled'] as bool? ?? true;
      final repeatFrequency = reminder['repeat_frequency'] as String? ?? 'once';
      if (!enabled || repeatFrequency != 'once') continue;
      final id = reminder['id'] as String;
      final anchor = combineDateAndTime(
        parseReminderDate(reminder['reminder_date'] as String),
        parseReminderTime(reminder['reminder_time'] as String),
      );
      final delay = anchor.difference(DateTime.now());
      _fireTimers[id] = Timer(
        delay.isNegative ? Duration.zero : delay,
        () => _handleReminderFired(id),
      );
    }
  }

  Future<void> _handleReminderFired(String id) async {
    _fireTimers.remove(id);
    if (!mounted) return;
    final reminders = _remindersVm.reminders ?? const <Map<String, dynamic>>[];
    final stillEnabled = reminders.any(
      (r) => r['id'] == id && (r['enabled'] as bool? ?? true),
    );
    if (!stillEnabled) return;
    _remindersVm.applyLocal(id, {'enabled': false});
    await _service.setReminderEnabled(id, false);
  }

  Future<void> _loadLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _locationUnavailable = true);
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationUnavailable = true);
        return;
      }

      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null && mounted) {
          setState(() {
            _userLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
          });
        }
      } catch (_) {}

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      if (mounted && _userLocation == null) {
        setState(() => _locationUnavailable = true);
      }
    }
  }

  double _distanceKm(LatLng a, LatLng b) {
    final dx = (a.latitude - b.latitude) * 111;
    final dy = (a.longitude - b.longitude) * 111;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _previewZoomForDistanceKm(double km) {
    if (km < 0.5) return 16;
    if (km < 1) return 15;
    if (km < 2) return 14;
    if (km < 5) return 13;
    if (km < 10) return 12;
    if (km < 20) return 11;
    return 10;
  }

  String? _validateCalcPower(String? value) => validateChargingPowerKw(value);

  String? _validateCalcRate(String? value) {
    final rate = double.tryParse((value ?? '').trim());
    if (rate == null) return 'Enter a rate';
    if (rate < _rateMinRm || rate > _rateMaxRm) {
      return 'Rate should be ${formatRm(_rateMinRm)}-${formatRm(_rateMaxRm)} per kWh';
    }
    return null;
  }

  bool _validateCalcForm() {
    if (_calcFormKey.currentState!.validate()) return true;
    FocusScope.of(context).unfocus();
    final error = _validateCalcPower(_calcPowerController.text) ??
        _validateCalcRate(_calcRateController.text);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
    return false;
  }

  void _calculate() {
    if (!_validateCalcForm()) return;
    final rate = double.parse(_calcRateController.text.trim());
    final power = int.parse(_calcPowerController.text.trim());
    final hours = _calcHours + _calcMinutes / 60;
    setState(() => _calcResult = power * hours * rate);
  }

  Future<void> _recordCalculatedSession() async {
    if (!_validateCalcForm()) return;
    final power = int.parse(_calcPowerController.text.trim());
    if (_calcResult == null) return;
    final saved = await showCreateSessionSheet(
      context,
      prefill: {
        'charger_type': _calcChargerType,
        'power_kw': power,
        'cost': _calcResult,
        'duration_minutes': _calcHours * 60 + _calcMinutes,
      },
    );
    if (saved == true) _reloadSessions();
  }

  Future<void> _fetchRouteEta(
    LatLng origin,
    List<ChargingStation> candidates,
  ) async {
    final candidateIds = [for (final c in candidates) c.id];
    setState(() {
      _routeEtaLoading = true;
      _routeEtaCandidateIds = candidateIds;
    });
    try {
      final results = await _routeEtaService.generate(
        RouteEtaContext(
          originLat: origin.latitude,
          originLng: origin.longitude,
          candidates: [
            for (final station in candidates)
              RouteEtaCandidate(
                id: station.id,
                lat: station.latitude,
                lng: station.longitude,
              ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _routeEtaResults = {for (final r in results) r.id: r};
        _routeEtaLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _routeEtaLoading = false);
    }
  }

  Future<void> _deleteSession(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text('This charging session record will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteSession(id);
    _reloadSessions();
  }

  Future<void> _deleteReminder(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: const Text('This reminder will be removed and cancelled.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _notifications.cancel(id);
    await _service.deleteReminder(id);
    await _remindersVm.load();
  }

  Future<void> _toggleReminder(
      Map<String, dynamic> reminder, bool enabled) async {
    final id = reminder['id'] as String;
    final repeatFrequency = reminder['repeat_frequency'] as String? ?? 'once';
    final repeatDays = (reminder['repeat_days'] as List<Object?>?)
            ?.map((e) => e as int)
            .toList() ??
        const <int>[];
    final anchor = combineDateAndTime(
      parseReminderDate(reminder['reminder_date'] as String),
      parseReminderTime(reminder['reminder_time'] as String),
    );

    if (enabled &&
        repeatFrequency == 'once' &&
        !anchor.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              "This reminder's date and time have passed. Edit it to "
              'set a new time before turning it back on.',
            ),
          ),
        );
      return;
    }

    _remindersVm.applyLocal(id, {'enabled': enabled});

    await _service.setReminderEnabled(id, enabled);
    if (enabled) {
      final scheduledAt = rollReminderToFuture(
        anchor,
        repeatFrequency,
        repeatDays: repeatDays,
      );
      await _notifications.scheduleReminder(
        reminderId: id,
        title: reminder['title'] as String,
        body: 'Time to charge your EV.',
        dateTime: scheduledAt,
        repeatFrequency: repeatFrequency,
        repeatDays: repeatDays,
      );
      if (scheduledAt != anchor) {
        await _service.updateReminderOccurrence(
          id,
          date: scheduledAt,
          time: TimeOfDay.fromDateTime(scheduledAt),
        );
      }
    } else {
      await _notifications.cancel(id);
    }
    await _remindersVm.load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer<PlanningViewModel>(
        builder: (context, vm, __) {
          return ListView(
            padding: planningPagePadding,
            children: [
              const Text(
                'Charging',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: planningTextColor,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Charge Smarter, Save More',
                textAlign: TextAlign.center,
                style: TextStyle(color: planningMutedTextColor),
              ),
              const SizedBox(height: 20),
              _buildCalculatorCard(),
              const SizedBox(height: 20),
              _buildSessionsCard(),
              const SizedBox(height: 20),
              _buildSpendingTrendCard(),
              const SizedBox(height: 20),
              _buildRemindersCard(),
              const SizedBox(height: 20),
              _buildRecommendationCard(vm),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCalculatorCard() {
    return AppCard(
      child: Form(
        key: _calcFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChargingSectionHeader(
              icon: Icons.calculate_outlined,
              title: 'Charging Cost Calculator',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _calcChargerType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Charger Type',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final type in chargerTypes)
                        DropdownMenuItem(
                          value: type,
                          child: Text(type, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _calcChargerType = value);
                        _calcFormKey.currentState?.validate();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _calcPowerController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Charging Power (kW)',
                      border: OutlineInputBorder(),
                      errorMaxLines: 2,
                    ),
                    validator: _validateCalcPower,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _calcRateController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [twoDecimalInputFormatter],
              decoration: const InputDecoration(
                labelText: 'Electricity Rate (RM/kWh)',
                border: OutlineInputBorder(),
                errorMaxLines: 2,
              ),
              validator: _validateCalcRate,
            ),
            const SizedBox(height: 12),
            DurationPickerField(
              label: 'Charging Time',
              hours: _calcHours,
              minutes: _calcMinutes,
              onChanged: (h, m) => setState(() {
                _calcHours = h;
                _calcMinutes = m;
              }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated Cost',
                        style: TextStyle(
                          fontSize: 12,
                          color: planningMutedTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _calcResult == null ? 'RM --' : formatRm(_calcResult!),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: green,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _calculate,
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                  label: const Text('Calculate'),
                ),
              ],
            ),
            if (_calcResult != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _recordCalculatedSession,
                icon: const Icon(Icons.receipt_long_outlined, color: green),
                label: const Text('Record This as a Session'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChargingSectionHeader(
            icon: Icons.receipt_long_outlined,
            title: 'Charging Sessions',
            subtitle: 'Manage your charging sessions.',
            action: IconButton(
              tooltip: 'Create Session',
              onPressed: () async {
                final saved = await showCreateSessionSheet(context);
                if (saved == true) _reloadSessions();
              },
              icon: const Icon(Icons.add_circle_outline, color: green),
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final sessions = snapshot.data ?? const [];
              if (sessions.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No charging sessions logged yet.',
                    style: TextStyle(color: planningMutedTextColor),
                  ),
                );
              }
              return Column(
                children: [
                  for (final session in sessions)
                    _SessionTile(
                      session: session,
                      onEdit: () async {
                        final saved = await showCreateSessionSheet(
                          context,
                          existing: session,
                        );
                        if (saved == true) _reloadSessions();
                      },
                      onDelete: () => _deleteSession(session['id'] as String),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSpendingTrendCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChargingSectionHeader(
            icon: Icons.bar_chart_outlined,
            title: 'Spending Trend',
            subtitle: 'Your charging cost over the last 6 months.',
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _sessionsFuture,
            builder: (context, snapshot) {
              final sessions = snapshot.data ?? const [];
              if (sessions.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Log a few sessions to see your spending trend here.',
                    style: TextStyle(color: planningMutedTextColor),
                  ),
                );
              }
              final totals = _monthlyTotals(sessions);
              final maxRm =
                  totals.map((t) => t.rm).fold(0.0, (a, b) => a > b ? a : b);
              final totalRm = totals.fold(0.0, (a, t) => a + t.rm);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 140,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final t in totals)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (t.rm > 0)
                                    Text(
                                      t.rm.toStringAsFixed(0),
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: planningMutedTextColor,
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  Container(
                                    height: maxRm <= 0
                                        ? 4
                                        : 8 + (t.rm / maxRm) * 70,
                                    decoration: BoxDecoration(
                                      color: t.rm > 0
                                          ? green
                                          : const Color(0xFFE9EDF3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    t.monthLabel,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: planningMutedTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${formatRm(totalRm)} over the last '
                    '6 months',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: planningTextColor,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRemindersCard() {
    final reminders = context.watch<RemindersViewModel>().reminders;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChargingSectionHeader(
            icon: Icons.notifications_active_outlined,
            title: 'My Reminders',
          ),
          const SizedBox(height: 8),
          if (reminders == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (reminders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No reminders set yet.',
                style: TextStyle(color: planningMutedTextColor),
              ),
            )
          else
            Column(
              children: [
                for (final reminder in reminders)
                  _ReminderTile(
                    reminder: reminder,
                    onToggle: (value) => _toggleReminder(reminder, value),
                    onEdit: () async {
                      final saved = await showCreateReminderSheet(
                        context,
                        existing: reminder,
                      );
                      if (saved == true) _remindersVm.load();
                    },
                    onDelete: () => _deleteReminder(reminder['id'] as String),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final saved = await showCreateReminderSheet(context);
              if (saved == true) _remindersVm.load();
            },
            icon: const Icon(Icons.add, color: green),
            label: const Text('Create Reminder'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(PlanningViewModel vm) {
    final referencePoint = _userLocation ?? _malaysiaFallback;
    final ranked = [
      for (final station in vm.stations)
        (
          station: station,
          straightLineKm: _distanceKm(
            referencePoint,
            LatLng(station.latitude, station.longitude),
          ),
        ),
    ]..sort((a, b) => a.straightLineKm.compareTo(b.straightLineKm));
    final candidates = ranked.take(5).toList();

    ChargingStation? nearest;
    var nearestDistance = double.infinity;
    double? nearestDurationMinutes;
    if (candidates.isNotEmpty) {
      nearest = candidates.first.station;
      nearestDistance = candidates.first.straightLineKm;

      final etaResults = _routeEtaResults;
      if (etaResults != null) {
        ChargingStation? bestStation;
        double? bestDistanceKm;
        double? bestDurationMinutes;
        for (final candidate in candidates) {
          final result = etaResults[candidate.station.id];
          final distanceKm = result?.distanceKm;
          final durationMinutes = result?.durationMinutes;
          if (distanceKm == null || durationMinutes == null) continue;
          if (bestDurationMinutes == null ||
              durationMinutes < bestDurationMinutes) {
            bestStation = candidate.station;
            bestDistanceKm = distanceKm;
            bestDurationMinutes = durationMinutes;
          }
        }
        if (bestStation != null) {
          nearest = bestStation;
          nearestDistance = bestDistanceKm!;
          nearestDurationMinutes = bestDurationMinutes;
        }
      }

      final candidateIds = [for (final c in candidates) c.station.id];
      if (_userLocation != null &&
          !_routeEtaLoading &&
          !listEquals(candidateIds, _routeEtaCandidateIds)) {
        final stations = [for (final c in candidates) c.station];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fetchRouteEta(referencePoint, stations);
        });
      }
    }
    final distanceLabel = nearestDurationMinutes != null
        ? '${nearestDistance.toStringAsFixed(1)} km · '
            '${nearestDurationMinutes.round()} min drive'
        : '${nearestDistance.toStringAsFixed(1)} km';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: ChargingSectionHeader(
                  icon: Icons.auto_awesome_outlined,
                  title: 'Smart Charging Recommendation',
                ),
              ),
              const Tooltip(
                message: 'Rule-based recommendation using your location, '
                    'the nearest real charging station, and real driving '
                    'time from OpenRouteService.',
                child: Icon(Icons.info_outline,
                    size: 18, color: planningMutedTextColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (nearest == null)
            const Text(
              'Loading station data…',
              style: TextStyle(color: planningMutedTextColor),
            )
          else if (_userLocation == null && !_locationUnavailable)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Getting your location…',
                    style: TextStyle(color: planningMutedTextColor),
                  ),
                ),
              ],
            )
          else ...[
            Builder(builder: (context) {
              final station = nearest!;
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 130,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(
                        (referencePoint.latitude + station.latitude) / 2,
                        (referencePoint.longitude + station.longitude) / 2,
                      ),
                      zoom: _previewZoomForDistanceKm(nearestDistance),
                    ),
                    markers: {
                      if (_userLocation != null)
                        Marker(
                          markerId: const MarkerId('user'),
                          position: _userLocation!,
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueAzure,
                          ),
                          infoWindow: const InfoWindow(title: 'Your location'),
                        ),
                      Marker(
                        markerId: MarkerId('rec_${station.id}'),
                        position: LatLng(station.latitude, station.longitude),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueOrange,
                        ),
                        onTap: () => showStationDetailsSheet(
                          context,
                          station: station,
                          distanceKm: nearestDistance,
                        ),
                      ),
                    },
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            Builder(builder: (context) {
              final station = nearest!;
              return InkWell(
                onTap: () => showStationDetailsSheet(
                  context,
                  station: station,
                  distanceKm: nearestDistance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: planningTextColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$distanceLabel · ${station.chargerType} · '
                      'Tap for details',
                      style: const TextStyle(
                        fontSize: 12,
                        color: planningMutedTextColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _RecommendationStat(
                    icon: Icons.ev_station_outlined,
                    label: 'Nearest Charger',
                    value: distanceLabel,
                  ),
                ),
                Expanded(
                  child: _RecommendationStat(
                    icon: Icons.power_outlined,
                    label: 'Charging Points',
                    value: nearest.chargerCount?.toString() ?? 'Not listed',
                  ),
                ),
              ],
            ),
            if (_locationUnavailable) ...[
              const SizedBox(height: 12),
              const Text(
                "Couldn't get your location, so this is ranked from a "
                'general Malaysia reference point instead of where you '
                "actually are - it likely isn't your true nearest station.",
                style: TextStyle(
                  fontSize: 11,
                  color: planningMutedTextColor,
                  height: 1.3,
                ),
              ),
            ],
            if (nearest.source != null && nearest.source!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  nearest.dataDate == null
                      ? 'Location data: ${nearest.source}'
                      : 'Location data: ${nearest.source}, as of '
                          '${nearest.dataDate!.day}/${nearest.dataDate!.month}/${nearest.dataDate!.year}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: planningMutedTextColor,
                  ),
                ),
              ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _sessionsFuture,
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? const [];
                final patternLine =
                    _SessionInsights.fromSessions(sessions)?.summaryLine();
                if (patternLine == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    patternLine,
                    style: const TextStyle(
                      fontSize: 12,
                      color: planningTextColor,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> session;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final chargerType = session['charger_type'] as String? ?? '';
    final cost = (session['cost'] as num).toDouble();
    final sessionAt = DateTime.parse(session['session_at'] as String);
    return InkWell(
      onTap: () => _showSessionDetails(context, session),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ChargerTypeIcon(chargerType: chargerType),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session['station_name'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: planningTextColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatSessionDate(sessionAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: planningMutedTextColor,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              formatRm(cost),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Update Session'),
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading:
                        Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text('Delete Session'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showSessionDetails(BuildContext context, Map<String, dynamic> session) {
  final chargerType = session['charger_type'] as String? ?? '';
  final power = (session['power_kw'] as num).toDouble();
  final energy = (session['energy_kwh'] as num).toDouble();
  final duration = session['duration_minutes'] as int;
  final cost = (session['cost'] as num).toDouble();
  final sessionAt = DateTime.parse(session['session_at'] as String);
  final vehicleLabel = session['vehicle_label'] as String?;
  final notes = session['notes'] as String?;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE3EA),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ChargerTypeIcon(chargerType: chargerType),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session['station_name'] as String,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: planningTextColor,
                                ),
                              ),
                              Text(
                                formatSessionDate(sessionAt),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: planningMutedTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _SessionDetailRow(
                        label: 'Charger Type', value: chargerType),
                    _SessionDetailRow(
                      label: 'Charging Power',
                      value: '${power.toStringAsFixed(0)} kW',
                    ),
                    _SessionDetailRow(
                      label: 'Energy Added',
                      value: '${energy.toStringAsFixed(1)} kWh',
                    ),
                    _SessionDetailRow(
                      label: 'Duration',
                      value: formatDuration(duration),
                    ),
                    _SessionDetailRow(
                      label: 'Cost',
                      value: formatRm(cost),
                    ),
                    if (vehicleLabel != null && vehicleLabel.isNotEmpty)
                      _SessionDetailRow(label: 'Vehicle', value: vehicleLabel),
                    if (notes != null && notes.isNotEmpty)
                      _SessionDetailRow(label: 'Additional Info', value: notes),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SessionDetailRow extends StatelessWidget {
  const _SessionDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  color: planningMutedTextColor,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: planningTextColor,
                ),
              ),
            ),
          ],
        ),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final enabled = reminder['enabled'] as bool? ?? true;
    final chargerType = reminder['charger_type'] as String?;
    final locationLabel = reminder['location_label'] as String?;
    final repeatFrequency = reminder['repeat_frequency'] as String? ?? 'once';
    final repeatDays = (reminder['repeat_days'] as List<Object?>?)
            ?.map((e) => e as int)
            .toList() ??
        const <int>[];
    final anchor = combineDateAndTime(
      parseReminderDate(reminder['reminder_date'] as String),
      parseReminderTime(reminder['reminder_time'] as String),
    );
    final displayAt = rollReminderToFuture(
      anchor,
      repeatFrequency,
      repeatDays: repeatDays,
    );
    final time = TimeOfDay.fromDateTime(displayAt);
    final date = displayAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder['title'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: planningTextColor,
                  ),
                ),
                Text(
                  '${relativeDateLabel(date)}, ${time.format(context)}',
                  style: const TextStyle(color: green, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (repeatFrequency != 'once')
                      _ReminderTag(
                        icon: Icons.repeat,
                        label: switch (repeatFrequency) {
                          'daily' => 'Every day',
                          'weekly' => _weeklyRepeatLabel(repeatDays),
                          _ => repeatFrequency,
                        },
                      ),
                    if (chargerType != null)
                      _ReminderTag(icon: Icons.bolt, label: chargerType),
                    if (locationLabel != null && locationLabel.isNotEmpty)
                      _ReminderTag(
                        icon: Icons.location_on_outlined,
                        label: locationLabel,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle, activeThumbColor: green),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Update Reminder'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Delete Reminder'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReminderTag extends StatelessWidget {
  const _ReminderTag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: const BoxConstraints(maxWidth: 160),
        decoration: BoxDecoration(
          color: green.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: green),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      );
}

class _RecommendationStat extends StatelessWidget {
  const _RecommendationStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Icon(icon, size: 18, color: green),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: planningMutedTextColor),
          ),
        ],
      );
}
