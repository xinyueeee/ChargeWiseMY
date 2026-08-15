import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/notification_service.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../services/charging_service.dart';
import '../widgets/charging_widgets.dart';

Future<bool?> showCreateReminderSheet(
  BuildContext context, {
  Map<String, dynamic>? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CreateReminderSheet(existing: existing),
  );
}

class _CreateReminderSheet extends StatefulWidget {
  const _CreateReminderSheet({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_CreateReminderSheet> createState() => _CreateReminderSheetState();
}

class _CreateReminderSheetState extends State<_CreateReminderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = ChargingService();
  final _notifications = NotificationService();

  late final TextEditingController _titleController;
  String _locationLabel = '';
  String? _chargerType;
  late DateTime _date;
  late TimeOfDay _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController =
        TextEditingController(text: existing?['title'] as String? ?? '');
    _locationLabel = existing?['location_label'] as String? ?? '';
    _chargerType = existing?['charger_type'] as String?;
    _date = existing == null
        ? DateTime.now()
        : parseReminderDate(existing['reminder_date'] as String);
    _time = existing == null
        ? TimeOfDay.now()
        : parseReminderTime(existing['reminder_time'] as String);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) setState(() => _time = time);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final title = _titleController.text.trim();
    final location = _locationLabel.trim();
    final locationLabel = location.isEmpty ? null : location;
    final dateTime = combineDateAndTime(_date, _time);
    String reminderId;

    try {
      if (widget.existing == null) {
        final row = await _service.createReminder(
          title: title,
          chargerType: _chargerType,
          locationLabel: locationLabel,
          date: _date,
          time: _time,
        );
        reminderId = row['id'] as String;
      } else {
        reminderId = widget.existing!['id'] as String;
        await _service.updateReminder(
          reminderId,
          title: title,
          chargerType: _chargerType,
          locationLabel: locationLabel,
          date: _date,
          time: _time,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save reminder. Please try again.'),
          ),
        );
        setState(() => _saving = false);
      }
      return;
    }

    // The reminder itself is saved at this point. A notification-scheduling
    // failure shouldn't hide that or block the user from seeing it saved.
    final enabled = widget.existing == null
        ? true
        : widget.existing!['enabled'] as bool? ?? true;
    String? notificationWarning;
    if (enabled) {
      try {
        await _notifications.scheduleReminder(
          reminderId: reminderId,
          title: title,
          body: 'Time to charge your EV.',
          dateTime: dateTime,
        );
      } catch (error) {
        notificationWarning =
            'Reminder saved, but the phone notification could not be '
            'scheduled ($error). Check notification/alarm permissions in '
            'system settings.';
      }
    }

    if (!mounted) return;
    if (notificationWarning != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notificationWarning), duration: const Duration(seconds: 6)),
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final stationNames = context
        .watch<PlanningViewModel>()
        .stations
        .map((s) => s.name)
        .toSet()
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEditing ? 'Update Reminder' : 'Create Reminder',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: planningTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Reminder Title',
                      hintText: 'e.g. Charge my car',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Enter a title' : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _chargerType,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Charger Type (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Not specified'),
                      ),
                      for (final type in chargerTypes)
                        DropdownMenuItem<String?>(
                          value: type,
                          child: Text(type),
                        ),
                    ],
                    onChanged: (value) => setState(() => _chargerType = value),
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: _locationLabel),
                    optionsBuilder: (textEditingValue) {
                      final query = textEditingValue.text.trim().toLowerCase();
                      if (query.isEmpty) return const [];
                      return stationNames
                          .where((name) => name.toLowerCase().contains(query))
                          .take(20);
                    },
                    onSelected: (value) =>
                        setState(() => _locationLabel = value),
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                          hintText: 'Search a station or type e.g. Home',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _locationLabel = value,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Date',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              '${_date.day}/${_date.month}/${_date.year}',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickTime,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Time',
                              border: OutlineInputBorder(),
                            ),
                            child: Text(_time.format(context)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'You\'ll get a real notification on this device at this '
                    'date and time.',
                    style: TextStyle(
                      fontSize: 12,
                      color: planningMutedTextColor,
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
                        : Text(
                            isEditing ? 'Update Reminder' : 'Create Reminder',
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
