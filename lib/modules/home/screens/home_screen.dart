import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../auth/screens/profile_screen.dart';
import '../../auth/services/auth_service.dart';
import '../../charging/screens/charging_screen.dart';
import '../../charging/services/charging_service.dart';
import '../../charging/widgets/charging_widgets.dart';
import '../../planning/models/proposal.dart';
import '../../planning/screens/planning_dashboard_screen.dart';
import '../../planning/services/state_boundary_service.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../widgets/station_details_sheet.dart';

const _malaysiaFallback = LatLng(3.1390, 101.6869); // Kuala Lumpur
const _nearbyRadiusKm = 20.0;
const _dcColor = Colors.orange;
const _ultraColor = Colors.cyan;
const _acColor = Colors.deepPurple;

enum _ChargerGroup { ac, dc, ultra }

_ChargerGroup _chargerGroup(ChargingStation station) {
  final type = station.chargerType.toLowerCase();
  if (type.contains('ultra')) return _ChargerGroup.ultra;
  if (type.contains('dc')) return _ChargerGroup.dc;
  return _ChargerGroup.ac;
}

BitmapDescriptor _iconForStation(ChargingStation station) {
  switch (_chargerGroup(station)) {
    case _ChargerGroup.dc:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
    case _ChargerGroup.ultra:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    case _ChargerGroup.ac:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
  }
}

enum _SuggestionType { state, station }

class _SearchSuggestion {
  _SearchSuggestion.state(String name)
      : label = name,
        type = _SuggestionType.state,
        station = null;

  _SearchSuggestion.station(ChargingStation station)
      : label = station.name,
        type = _SuggestionType.station,
        station = station;

  final String label;
  final _SuggestionType type;
  final ChargingStation? station;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _chargingService = ChargingService();

  bool _loadingProfile = true;
  String _driverName = 'Driver';
  String _chargerFilter = 'All';
  String _searchQuery = '';
  LatLng? _userLocation;
  Future<List<Map<String, dynamic>>>? _remindersFuture;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadLocation();
    _remindersFuture = _chargingService.fetchReminders();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _authService.fetchProfile();
      if (!mounted) return;
      final fullName = (profile?['full_name'] as String?)?.trim();
      setState(() {
        _driverName = fullName == null || fullName.isEmpty
            ? 'Driver'
            : fullName.split(' ').first;
        _loadingProfile = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProfile = false);
    }
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
    } catch (_) {
      // No location available; stats fall back to Kuala Lumpur.
    }
  }

  double _distanceKm(LatLng a, LatLng b) {
    final dx = (a.latitude - b.latitude) * 111;
    final dy = (a.longitude - b.longitude) * 111;
    return math.sqrt(dx * dx + dy * dy);
  }

  LatLng get _referencePoint => _userLocation ?? _malaysiaFallback;

  Iterable<_SearchSuggestion> _buildSuggestions(
    PlanningViewModel vm,
    String query,
  ) {
    if (query.isEmpty) return const [];
    final lowerQuery = query.toLowerCase();
    final stateMatches = vm.stateOptions
        .where((state) =>
            state != malaysiaSelection && state.toLowerCase().contains(lowerQuery))
        .map(_SearchSuggestion.state);
    final stationMatches = vm.stations
        .where((station) => station.name.toLowerCase().contains(lowerQuery))
        .take(15)
        .map(_SearchSuggestion.station);
    return [...stateMatches, ...stationMatches];
  }

  void _applySuggestion(PlanningViewModel vm, _SearchSuggestion suggestion) {
    if (suggestion.type == _SuggestionType.state) {
      vm.selectState(suggestion.label, source: 'home-search');
      return;
    }
    final station = suggestion.station!;
    final stationState = vm.stateForStation(station.id);
    setState(() => _searchQuery = station.name.toLowerCase());
    if (stationState != null && stationState != vm.selectedState) {
      vm.selectState(stationState, source: 'home-search-station');
    }
  }

  void _handleSearchSubmit(
    BuildContext context,
    PlanningViewModel vm,
    String value,
  ) {
    final query = value.trim();
    if (query.isEmpty) return;
    final matches = _buildSuggestions(vm, query);
    if (matches.isNotEmpty) {
      _applySuggestion(vm, matches.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'No matching state or charging station found.',
        ),
      ),
    );
  }

  List<ChargingStation> _applyFilter(List<ChargingStation> stations) {
    final query = _searchQuery;
    return stations.where((station) {
      final matchesFilter = _chargerFilter == 'All' ||
          (_chargerFilter == 'DC' && _chargerGroup(station) == _ChargerGroup.dc) ||
          (_chargerFilter == 'AC' && _chargerGroup(station) == _ChargerGroup.ac) ||
          (_chargerFilter == 'Ultra' &&
              _chargerGroup(station) == _ChargerGroup.ultra);
      final matchesSearch =
          query.isEmpty || station.name.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Consumer<PlanningViewModel>(
          builder: (context, vm, __) {
            if (vm.loading || _loadingProfile) {
              return const PlanningLoadingState(message: 'Loading dashboard…');
            }
            if (vm.errorMessage != null) {
              return PlanningErrorState(
                message: vm.errorMessage!,
                onRetry: vm.load,
              );
            }

            final nearby = vm.stations.where((station) {
              return _distanceKm(
                    _referencePoint,
                    LatLng(station.latitude, station.longitude),
                  ) <=
                  _nearbyRadiusKm;
            }).toList(growable: false);
            final dcCount = nearby
                .where((s) => _chargerGroup(s) == _ChargerGroup.dc)
                .length;
            final acCount = nearby
                .where((s) => _chargerGroup(s) == _ChargerGroup.ac)
                .length;
            final ultraCount = nearby
                .where((s) => _chargerGroup(s) == _ChargerGroup.ultra)
                .length;

            return ListView(
              padding: planningPagePadding,
              children: [
                const Text(
                  'Dashboard',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: planningTextColor,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Hello, $_driverName! 👋',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: planningTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Find, charge and manage your EV charging easily.',
                  style: TextStyle(color: planningMutedTextColor),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Autocomplete<_SearchSuggestion>(
                      optionsBuilder: (textEditingValue) =>
                          _buildSuggestions(vm, textEditingValue.text.trim()),
                      displayStringForOption: (option) => option.label,
                      onSelected: (option) => _applySuggestion(vm, option),
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(
                            () => _searchQuery = value.trim().toLowerCase(),
                          ),
                          onSubmitted: (value) {
                            onFieldSubmitted();
                            _handleSearchSubmit(context, vm, value);
                          },
                          decoration: InputDecoration(
                            hintText: 'Search state or charging station',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => _handleSearchSubmit(
                                context,
                                vm,
                                controller.text,
                              ),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        final list = options.toList();
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 260),
                                child: ListView.separated(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shrinkWrap: true,
                                  itemCount: list.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final option = list[index];
                                    final isState =
                                        option.type == _SuggestionType.state;
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        isState
                                            ? Icons.map_outlined
                                            : Icons.ev_station_outlined,
                                        color: isState ? green : blue,
                                        size: 20,
                                      ),
                                      title: Text(option.label),
                                      subtitle: isState
                                          ? null
                                          : Text(
                                              option.station!.chargerType,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                      onTap: () => onSelected(option),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (vm.selectedState != malaysiaSelection)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        avatar: const Icon(
                          Icons.location_on_outlined,
                          size: 17,
                          color: green,
                        ),
                        label: Text(vm.selectedState),
                        deleteIcon: const Icon(Icons.close, size: 17),
                        deleteButtonTooltipMessage: 'Return to Malaysia Overview',
                        onDeleted: () => vm.selectState(
                          malaysiaSelection,
                          source: 'home-chip-clear',
                        ),
                      ),
                    ),
                  ),
                MapPanel(
                  height: 300,
                  stations: _applyFilter(vm.mapStations),
                  stateRegions: vm.stateRegions,
                  stateOverviews: vm.stateOverviewSummaries,
                  selectedState: vm.selectedState,
                  focusBounds: vm.selectedMapBounds,
                  onStateSelected: (state, source) =>
                      vm.selectState(state, source: source),
                  stationIconResolver: _iconForStation,
                  onStationTap: (station) => showStationDetailsSheet(
                    context,
                    station: station,
                    distanceKm: _distanceKm(
                      _referencePoint,
                      LatLng(station.latitude, station.longitude),
                    ),
                  ),
                ),
                if (vm.selectedState == malaysiaSelection) ...[
                  const SizedBox(height: 8),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 17,
                        color: planningMutedTextColor,
                      ),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Tap a state to see its charging stations',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: planningMutedTextColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Filter by',
                  style: TextStyle(
                    color: planningTextColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _chargerFilter,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.ev_station_outlined),
                    labelText: 'Charger type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'All', child: Text('All')),
                    DropdownMenuItem(value: 'AC', child: Text('AC Charger')),
                    DropdownMenuItem(value: 'DC', child: Text('DC Fast Charger')),
                    DropdownMenuItem(
                      value: 'Ultra',
                      child: Text('Ultra Fast Charger'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _chargerFilter = value);
                    }
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'Charging Overview',
                  style: TextStyle(
                    color: planningTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: StatisticCard(
                        value: '$dcCount',
                        label: 'DC Fast',
                        icon: Icons.bolt,
                        color: _dcColor,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatisticCard(
                        value: '$acCount',
                        label: 'AC',
                        icon: Icons.bolt,
                        color: _acColor,
                        width: double.infinity,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: StatisticCard(
                        value: '$ultraCount',
                        label: 'Ultra Fast',
                        icon: Icons.bolt,
                        color: _ultraColor,
                        width: double.infinity,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Reminders',
                  style: TextStyle(
                    color: planningTextColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _remindersFuture,
                  builder: (context, snapshot) {
                    final reminders = snapshot.data ?? const [];
                    final now = DateTime.now();
                    final upcoming = reminders.where((r) {
                      if (r['enabled'] != true) return false;
                      final dateTime = combineDateAndTime(
                        parseReminderDate(r['reminder_date'] as String),
                        parseReminderTime(r['reminder_time'] as String),
                      );
                      return !dateTime.isBefore(now);
                    }).toList()
                      ..sort((a, b) {
                        final aTime = combineDateAndTime(
                          parseReminderDate(a['reminder_date'] as String),
                          parseReminderTime(a['reminder_time'] as String),
                        );
                        final bTime = combineDateAndTime(
                          parseReminderDate(b['reminder_date'] as String),
                          parseReminderTime(b['reminder_time'] as String),
                        );
                        return aTime.compareTo(bTime);
                      });
                    final next = upcoming.isEmpty ? null : upcoming.first;

                    return InkWell(
                      onTap: () => _switchTo(const ChargingScreen()),
                      child: AppCard(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.event_available_outlined,
                              color: green,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    next == null
                                        ? 'No upcoming reminders'
                                        : next['title'] as String,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: planningTextColor,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    next == null
                                        ? 'Tap to set a charging reminder.'
                                        : '${relativeDateLabel(parseReminderDate(next['reminder_date'] as String))}, '
                                            '${parseReminderTime(next['reminder_time'] as String).format(context)}',
                                    style: const TextStyle(
                                      color: planningMutedTextColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              color: planningMutedTextColor,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: FloatingBottomNav(
        currentTab: 'Home',
        onChargingTap: () => _switchTo(const ChargingScreen()),
        onPlanningTap: () => _switchTo(const PlanningDashboardScreen()),
        onProfileTap: () => _switchTo(const ProfileScreen()),
      ),
    );
  }

  void _switchTo(Widget page) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}
