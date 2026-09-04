import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../auth/screens/add_vehicle_screen.dart';
import '../../auth/services/auth_service.dart';
import '../../planning/models/proposal.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../services/charging_service.dart';
import '../widgets/charging_widgets.dart';

Future<bool?> showCreateSessionSheet(
  BuildContext context, {
  Map<String, dynamic>? existing,
  Map<String, dynamic>? prefill,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CreateSessionSheet(existing: existing, prefill: prefill),
  );
}

class _CreateSessionSheet extends StatefulWidget {
  const _CreateSessionSheet({this.existing, this.prefill});

  final Map<String, dynamic>? existing;
  final Map<String, dynamic>? prefill;

  @override
  State<_CreateSessionSheet> createState() => _CreateSessionSheetState();
}

class _CreateSessionSheetState extends State<_CreateSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = ChargingService();
  final _authService = AuthService();

  late final TextEditingController _powerController;
  late final TextEditingController _energyController;
  late final TextEditingController _costController;
  late final TextEditingController _notesController;
  late String _chargerType;
  late String _stationName;
  String? _selectedStationId;
  String? _autoFilledStationName;
  late DateTime _sessionAt;
  int _durationHours = 1;
  int _durationMinutes = 0;
  bool _saving = false;

  List<Map<String, dynamic>> _vehicles = [];
  String? _selectedVehicleId;
  bool _loadingVehicles = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final source = existing ?? widget.prefill;
    _stationName = existing?['station_name'] as String? ?? '';
    _selectedStationId = existing?['station_id'] as String?;
    _autoFilledStationName = _selectedStationId != null ? _stationName : null;
    _powerController = TextEditingController(
      text: source?['power_kw'] == null
          ? ''
          : (source!['power_kw'] as num).toString(),
    );
    _energyController = TextEditingController(
      text: source?['energy_kwh'] == null
          ? ''
          : (source!['energy_kwh'] as num).toString(),
    );
    _costController = TextEditingController(
      text: source?['cost'] == null
          ? ''
          : (source!['cost'] as num).toStringAsFixed(2),
    );
    _notesController =
        TextEditingController(text: existing?['notes'] as String? ?? '');
    _chargerType = source?['charger_type'] as String? ?? chargerTypes[1];
    _sessionAt = existing == null
        ? DateTime.now()
        : DateTime.parse(existing['session_at'] as String);
    final totalMinutes = source?['duration_minutes'] as int? ?? 60;
    _durationHours = totalMinutes ~/ 60;
    _durationMinutes = totalMinutes % 60;
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    final vehicles = await _authService.fetchVehicles();
    if (!mounted) return;
    setState(() {
      _vehicles = vehicles;
      _loadingVehicles = false;
      _selectedVehicleId = widget.existing?['vehicle_id'] as String?;
    });
  }

  Future<void> _addVehicle() async {
    final added = await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const AddVehicleScreen()),
    );
    if (added == true) _loadVehicles();
  }

  @override
  void dispose() {
    _powerController.dispose();
    _energyController.dispose();
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _sessionAt,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_sessionAt),
    );
    if (time == null) return;
    setState(() {
      _sessionAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_stationName.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final power = double.parse(_powerController.text.trim());
      final energy = double.parse(_energyController.text.trim());
      final cost = double.parse(_costController.text.trim());
      final duration = _durationHours * 60 + _durationMinutes;
      final vehicle = _vehicles.firstWhere(
        (v) => v['id'] == _selectedVehicleId,
        orElse: () => const {},
      );
      final vehicleLabel = vehicle.isEmpty
          ? null
          : [vehicle['make'], vehicle['model']]
              .where((s) => (s as String?)?.isNotEmpty == true)
              .join(' ');
      final notes = _notesController.text.trim();

      if (widget.existing == null) {
        await _service.createSession(
          stationId: _selectedStationId,
          stationName: _stationName,
          chargerType: _chargerType,
          powerKw: power,
          energyKwh: energy,
          durationMinutes: duration,
          cost: cost,
          sessionAt: _sessionAt,
          vehicleId: _selectedVehicleId,
          vehicleLabel: vehicleLabel,
          notes: notes.isEmpty ? null : notes,
        );
      } else {
        await _service.updateSession(
          widget.existing!['id'] as String,
          stationId: _selectedStationId,
          stationName: _stationName,
          chargerType: _chargerType,
          powerKw: power,
          energyKwh: energy,
          durationMinutes: duration,
          cost: cost,
          sessionAt: _sessionAt,
          vehicleId: _selectedVehicleId,
          vehicleLabel: vehicleLabel,
          notes: notes.isEmpty ? null : notes,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save session. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final stations = context.watch<PlanningViewModel>().stations;
    return SafeArea(
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
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          isEditing ? 'Update Session' : 'Create Session',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: planningTextColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Autocomplete<ChargingStation>(
                          initialValue: TextEditingValue(text: _stationName),
                          displayStringForOption: (station) => station.name,
                          optionsBuilder: (textEditingValue) {
                            final query =
                                textEditingValue.text.trim().toLowerCase();
                            if (query.isEmpty) return const [];
                            return stations
                                .where(
                                    (s) => s.name.toLowerCase().contains(query))
                                .take(20);
                          },
                          onSelected: (station) {
                            setState(() {
                              _stationName = station.name;
                              _selectedStationId = station.id;
                              _autoFilledStationName = station.name;
                              _chargerType = station.chargerType;
                            });
                          },
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
                            return TextFormField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Station Name',
                                hintText: 'Search or type a station name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Enter a station name'
                                  : null,
                              onChanged: (value) {
                                _stationName = value;
                                if (value != _autoFilledStationName) {
                                  _selectedStationId = null;
                                }
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _chargerType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Charger Type',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final type in chargerTypes)
                              DropdownMenuItem(
                                value: type,
                                child:
                                    Text(type, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _chargerType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _powerController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Charging Power (kW)',
                            helperText:
                                'The charger\'s speed, e.g. 50, 120, 180',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              int.tryParse((value ?? '').trim()) == null
                                  ? 'Enter power in kW'
                                  : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _energyController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Energy (kWh)',
                                  helperText:
                                      'Electricity added to your vehicle',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    double.tryParse((value ?? '').trim()) ==
                                            null
                                        ? 'Enter kWh'
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _costController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [twoDecimalInputFormatter],
                                decoration: const InputDecoration(
                                  labelText: 'Cost (RM)',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (value) =>
                                    double.tryParse((value ?? '').trim()) ==
                                            null
                                        ? 'Enter cost'
                                        : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DurationPickerField(
                          label: 'Duration',
                          hours: _durationHours,
                          minutes: _durationMinutes,
                          onChanged: (h, m) => setState(() {
                            _durationHours = h;
                            _durationMinutes = m;
                          }),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: _pickDateTime,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Date & Time',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(formatSessionDate(_sessionAt)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                key: ValueKey(_loadingVehicles),
                                initialValue: _selectedVehicleId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: _loadingVehicles
                                      ? 'Loading vehicles…'
                                      : 'Vehicle (optional)',
                                  border: const OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Not specified'),
                                  ),
                                  for (final vehicle in _vehicles)
                                    DropdownMenuItem<String?>(
                                      value: vehicle['id'] as String,
                                      child: Text(
                                        '${vehicle['make']} ${vehicle['model']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _selectedVehicleId = value),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Add Vehicle',
                              onPressed: _addVehicle,
                              icon: const Icon(Icons.add_circle_outline,
                                  color: green),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Additional Info (optional)',
                            hintText: 'Any notes about this session',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: green,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(isEditing
                                  ? 'Update Session'
                                  : 'Create Session'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
