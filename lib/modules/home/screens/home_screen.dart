import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/navigation/driver_navigation.dart';
import '../../auth/services/auth_service.dart';
import '../../charging/services/charging_service.dart';
import '../../charging/widgets/charging_widgets.dart';
import '../../planning/models/proposal.dart';
import '../../planning/services/state_boundary_service.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../widgets/station_details_sheet.dart';

const _malaysiaFallback = LatLng(3.1390, 101.6869); // Kuala Lumpur
const _dcColor = Colors.orange;
const _acColor = Colors.deepPurple;

enum _ChargerGroup { ac, dc }

/// Groups thousands so large location counts stay readable.
String _formatCount(int value) => value.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]},',
    );

_ChargerGroup _chargerGroup(ChargingStation station) {
  final type = station.chargerType.toLowerCase();
  if (type.contains('dc')) return _ChargerGroup.dc;
  return _ChargerGroup.ac;
}

BitmapDescriptor _iconForStation(ChargingStation station) {
  switch (_chargerGroup(station)) {
    case _ChargerGroup.dc:
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
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

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final _authService = AuthService();
  final _chargingService = ChargingService();

  String _driverName = 'Driver';
  String _chargerFilter = 'All';
  String _searchQuery = '';
  LatLng? _userLocation;
  bool _autoLocated = false;
  bool _autoLocateDone = false;
  List<Map<String, dynamic>>? _reminders;
  PageRoute<dynamic>? _subscribedRoute;
  bool _mapMounted = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadLocation();
    _reloadReminders();
  }

  Future<void> _reloadReminders() async {
    final reminders = await _chargingService.fetchReminders();
    if (!mounted) return;
    setState(() => _reminders = reminders);
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
  void didPushNext() => _setMapMounted(false);

  @override
  void didPopNext() {
    _setMapMounted(true);
    // Returning here from Charging (create/edit/delete/toggle a reminder)
    // shouldn't leave this card showing stale data until the next cold
    // start, so refresh it every time Home comes back into view.
    _reloadReminders();
  }

  void _setMapMounted(bool value) {
    if (!mounted || value == _mapMounted) return;
    setState(() => _mapMounted = value);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
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
      });
    } catch (_) {}
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

      // A fresh GPS fix can take anywhere from ~1s to 30+s (cold start,
      // weak signal, indoors, right after login) - during which the map
      // sat on its default wide Malaysia view instead of the auto-locate
      // zoom, since _userLocation stayed null the whole time. Grab
      // whatever position the OS already has cached first, near-instantly,
      // so auto-locate has something to zoom to right away.
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
    } catch (_) {}
  }

  void _maybeAutoLocate(PlanningViewModel vm) {
    if (_autoLocateDone || _userLocation == null || vm.stations.isEmpty) {
      return;
    }
    if (vm.selectedState != malaysiaSelection) return;
    ChargingStation? nearest;
    var nearestDistance = double.infinity;
    for (final station in vm.stations) {
      final distance = _distanceKm(
        _userLocation!,
        LatLng(station.latitude, station.longitude),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = station;
      }
    }
    final state = nearest == null ? null : vm.stateForStation(nearest.id);
    if (state == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _autoLocated = true;
        _autoLocateDone = true;
      });
      vm.selectState(state, source: 'home-auto-locate');
    });
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
            state != malaysiaSelection &&
            state.toLowerCase().contains(lowerQuery))
        .map(_SearchSuggestion.state);
    final stationMatches = vm.stations
        .where((station) => station.name.toLowerCase().contains(lowerQuery))
        .take(15)
        .map(_SearchSuggestion.station);
    return [...stateMatches, ...stationMatches];
  }

  void _applySuggestion(PlanningViewModel vm, _SearchSuggestion suggestion) {
    if (suggestion.type == _SuggestionType.state) {
      setState(() {
        _autoLocated = false;
        _autoLocateDone = true;
      });
      vm.selectState(suggestion.label, source: 'home-search');
      return;
    }
    final station = suggestion.station!;
    final stationState = vm.stateForStation(station.id);
    setState(() {
      _autoLocated = false;
      _autoLocateDone = true;
      _searchQuery = station.name.toLowerCase();
    });
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
          (_chargerFilter == 'DC' &&
              _chargerGroup(station) == _ChargerGroup.dc) ||
          (_chargerFilter == 'AC' &&
              _chargerGroup(station) == _ChargerGroup.ac);
      final matchesSearch =
          query.isEmpty || station.name.toLowerCase().contains(query);
      return matchesFilter && matchesSearch;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    // No Scaffold/DriverNavigationShell here anymore - DriverShell now owns
    // the one Scaffold, bottom nav, and rail shared by all five tabs; this
    // just needs to return its own content.
    return SafeArea(
      child: Consumer<PlanningViewModel>(
        builder: (context, vm, __) {
          if (vm.errorMessage != null && vm.stations.isEmpty) {
            return PlanningErrorState(
              message: vm.errorMessage!,
              onRetry: vm.load,
            );
          }
          if (!vm.homeInfrastructureReady && vm.stations.isEmpty) {
            return const PlanningLoadingState(message: 'Loading dashboard…');
          }

          _maybeAutoLocate(vm);

          // One logical Existing-only dataset feeds both the overview and
          // the map. Rendering optimisations (clustering, viewport limits)
          // are applied downstream by the map widget, never here, so the
          // statistics always describe the full selection rather than the
          // markers that happen to be drawn.
          final homeStations = _applyFilter(vm.mapStations);
          final dcCount = homeStations
              .where((s) => _chargerGroup(s) == _ChargerGroup.dc)
              .length;
          final acCount = homeStations
              .where((s) => _chargerGroup(s) == _ChargerGroup.ac)
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
              if (vm.infrastructureWarningMessage != null) ...[
                const SizedBox(height: 12),
                InfrastructureDataNotice(
                  message: vm.infrastructureWarningMessage!,
                ),
              ],
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
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                shrinkWrap: true,
                                itemCount: list.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final option = list[index];
                                  final isState =
                                      option.type == _SuggestionType.state;
                                  return Material(
                                    color: Colors.white,
                                    child: ListTile(
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
                                    ),
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
                      onDeleted: () {
                        setState(() {
                          _autoLocated = false;
                          _autoLocateDone = true;
                        });
                        vm.selectState(
                          malaysiaSelection,
                          source: 'home-chip-clear',
                        );
                      },
                    ),
                  ),
                ),
              if (_mapMounted)
                MapPanel(
                  height: 220,
                  stations: homeStations,
                  stateRegions: vm.stateRegions,
                  stateOverviews: vm.stateOverviewSummaries,
                  selectedState: vm.selectedState,
                  focusBounds: _autoLocated ? null : vm.selectedMapBounds,
                  focusTarget: _autoLocated ? _userLocation : null,
                  focusZoom: 14.5,
                  myLocationEnabled: _userLocation != null,
                  onStateSelected: (state, source) {
                    setState(() {
                      _autoLocated = false;
                      _autoLocateDone = true;
                    });
                    vm.selectState(state, source: source);
                  },
                  showNationalStateBadges: false,
                  showStationsInNationalView: true,
                  stationIconResolver: _iconForStation,
                  onStationTap: (station) => showStationDetailsSheet(
                    context,
                    station: station,
                    distanceKm: _distanceKm(
                      _referencePoint,
                      LatLng(station.latitude, station.longitude),
                    ),
                  ),
                )
              else
                const SizedBox(height: 300),
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
              const SizedBox(height: 4),
              // States the size of the dataset behind these figures, so a
              // clustered map is not mistaken for missing locations.
              Text(
                '${_formatCount(homeStations.length)} existing '
                '${homeStations.length == 1 ? 'location' : 'locations'} in '
                '${vm.selectedState}. The map groups nearby markers when '
                'zoomed out.',
                style: const TextStyle(
                  color: planningMutedTextColor,
                  fontSize: 12,
                  height: 1.35,
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
              _buildReminderSummaryCard(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReminderSummaryCard(BuildContext context) {
    final reminders = _reminders ?? const <Map<String, dynamic>>[];
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
      onTap: () => switchDriverTab(context, DriverTab.charging),
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
  }
}
