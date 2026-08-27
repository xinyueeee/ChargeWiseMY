import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/driver_navigation.dart';
import '../../../services/notification_service.dart';
import '../../auth/screens/profile_screen.dart';
import '../../feedback/screens/feedback_dashboard_screen.dart';
import '../../home/widgets/station_details_sheet.dart';
import '../../planning/models/proposal.dart';
import '../../planning/screens/planning_dashboard_screen.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../services/charging_service.dart';
import '../widgets/charging_widgets.dart';
import 'create_reminder_sheet.dart';
import 'create_session_sheet.dart';

const _offPeakRateSen = 24.43;
const _peakRateSen = 28.52;
const _malaysiaFallback = LatLng(3.1390, 101.6869);

class ChargingScreen extends StatefulWidget {
  const ChargingScreen({super.key});

  @override
  State<ChargingScreen> createState() => _ChargingScreenState();
}

class _ChargingScreenState extends State<ChargingScreen> {
  final _service = ChargingService();
  final _notifications = NotificationService();

  // Calculator state
  String _calcChargerType = chargerTypes[1];
  final _calcPowerController = TextEditingController(text: '180');
  final _calcRateController = TextEditingController(text: '1.20');
  int _calcHours = 1;
  int _calcMinutes = 30;
  double? _calcResult;

  Future<List<Map<String, dynamic>>>? _sessionsFuture;
  Future<List<Map<String, dynamic>>>? _remindersFuture;

  LatLng? _userLocation;

  @override
  void initState() {
    super.initState();
    _reloadSessions();
    _reloadReminders();
    _loadLocation();
  }

  @override
  void dispose() {
    _calcPowerController.dispose();
    _calcRateController.dispose();
    super.dispose();
  }

  void _reloadSessions() {
    setState(() {
      _sessionsFuture = _service.fetchSessions();
    });
  }

  void _reloadReminders() {
    setState(() {
      _remindersFuture = _service.fetchReminders();
    });
  }

  Future<void> _loadLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {}
  }

  double _distanceKm(LatLng a, LatLng b) {
    final dx = (a.latitude - b.latitude) * 111;
    final dy = (a.longitude - b.longitude) * 111;
    return math.sqrt(dx * dx + dy * dy);
  }

  void _calculate() {
    final rate = double.tryParse(_calcRateController.text.trim());
    final power = int.tryParse(_calcPowerController.text.trim());
    if (rate == null || power == null) return;
    final hours = _calcHours + _calcMinutes / 60;
    setState(() => _calcResult = power * hours * rate);
  }

  bool get _isWeekendNow {
    final now = DateTime.now();
    return now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  }

  bool get _isPeakNow {
    if (_isWeekendNow) return false;
    final hour = DateTime.now().hour;
    return hour >= 14 && hour < 22;
  }

  String get _bestTimeToCharge {
    if (!_isPeakNow) return 'Now (off-peak rate)';
    return '10:00 PM - 2:00 PM';
  }

  int get _savingsPercent =>
      (((_peakRateSen - _offPeakRateSen) / _peakRateSen) * 100).round();

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
    _reloadReminders();
  }

  Future<void> _toggleReminder(
      Map<String, dynamic> reminder, bool enabled) async {
    final id = reminder['id'] as String;
    await _service.setReminderEnabled(id, enabled);
    if (enabled) {
      await _notifications.scheduleReminder(
        reminderId: id,
        title: reminder['title'] as String,
        body: 'Time to charge your EV.',
        dateTime: combineDateAndTime(
          parseReminderDate(reminder['reminder_date'] as String),
          parseReminderTime(reminder['reminder_time'] as String),
        ),
      );
    } else {
      await _notifications.cancel(id);
    }
    _reloadReminders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
                _buildRemindersCard(),
                const SizedBox(height: 20),
                _buildRecommendationCard(vm),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: FloatingBottomNav(
        currentTab: 'Charging',
        onHomeTap: () => returnToDriverHome(context),
        onPlanningTap: () => _switchTo(
          const PlanningDashboardScreen(),
          DriverRouteNames.planning,
        ),
        onProfileTap: () => _switchTo(
          const ProfileScreen(),
          DriverRouteNames.profile,
        ),
        onFeedbackTap: () => _switchTo(
          const FeedbackDashboardScreen(),
          DriverRouteNames.feedback,
        ),
      ),
    );
  }

  void _switchTo(Widget page, String routeName) {
    openDriverModule(
      context,
      routeName: routeName,
      builder: (_) => page,
    );
  }

  Widget _buildCalculatorCard() {
    return AppCard(
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
                    if (value != null) setState(() => _calcChargerType = value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _calcPowerController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Charging Power (kW)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _calcRateController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Electricity Rate (RM/kWh)',
              border: OutlineInputBorder(),
            ),
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
                      _calcResult == null
                          ? 'RM --'
                          : 'RM${_calcResult!.toStringAsFixed(2)}',
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
        ],
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

  Widget _buildRemindersCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChargingSectionHeader(
            icon: Icons.notifications_active_outlined,
            title: 'My Reminders',
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _remindersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final reminders = snapshot.data ?? const [];
              if (reminders.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No reminders set yet.',
                    style: TextStyle(color: planningMutedTextColor),
                  ),
                );
              }
              return Column(
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
                        if (saved == true) _reloadReminders();
                      },
                      onDelete: () => _deleteReminder(reminder['id'] as String),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              final saved = await showCreateReminderSheet(context);
              if (saved == true) _reloadReminders();
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
    ChargingStation? nearest;
    var nearestDistance = double.infinity;
    for (final station in vm.stations) {
      final distance = _distanceKm(
        referencePoint,
        LatLng(station.latitude, station.longitude),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }

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
                    'the nearest real charging station, and Malaysia\'s '
                    'TNB off-peak electricity hours.',
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
                      zoom: 11,
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
                      '${nearestDistance.toStringAsFixed(1)} km away · '
                      '${station.chargerType} · Tap for details',
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
                    icon: Icons.schedule,
                    label: 'Best Time',
                    value: _bestTimeToCharge,
                  ),
                ),
                Expanded(
                  child: _RecommendationStat(
                    icon: Icons.savings_outlined,
                    label: 'Off-Peak Savings',
                    value: 'Up to $_savingsPercent%',
                  ),
                ),
                Expanded(
                  child: _RecommendationStat(
                    icon: Icons.ev_station_outlined,
                    label: 'Nearest Charger',
                    value: '${nearestDistance.toStringAsFixed(1)} km',
                  ),
                ),
              ],
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
    final energy = (session['energy_kwh'] as num).toDouble();
    final duration = session['duration_minutes'] as int;
    final sessionAt = DateTime.parse(session['session_at'] as String);
    return Padding(
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
                  '$chargerType · ${(session['power_kw'] as num).toStringAsFixed(0)} kW',
                  style: const TextStyle(
                    fontSize: 12,
                    color: planningMutedTextColor,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM${cost.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                '${energy.toStringAsFixed(1)} kWh · ${formatDuration(duration)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: planningMutedTextColor,
                ),
              ),
            ],
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
                  leading: Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: Text('Delete Session'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
    final time = parseReminderTime(reminder['reminder_time'] as String);
    final date = parseReminderDate(reminder['reminder_date'] as String);
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
