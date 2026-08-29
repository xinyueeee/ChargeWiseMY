import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/notification_service.dart';
import '../../planning/viewmodels/planning_viewmodel.dart';
import '../../planning/widgets/planning_widgets.dart';
import '../services/charging_service.dart';
import '../widgets/charging_widgets.dart';

const _frequencyModes = [
  ('weekly', 'Weekly'),
  ('once', 'Specific Date'),
];

// DateTime.weekday values (1=Monday..7=Sunday), ordered Sunday-first to
// match how phone alarm apps usually lay out a day-of-week picker.
const _weekdayChips = [
  (7, 'S'),
  (1, 'M'),
  (2, 'T'),
  (3, 'W'),
  (4, 'T'),
  (5, 'F'),
  (6, 'S'),
];

Future<bool?> showCreateReminderSheet(
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
    builder: (_) => _CreateReminderSheet(existing: existing, prefill: prefill),
  );
}

class _CreateReminderSheet extends StatefulWidget {
  const _CreateReminderSheet({this.existing, this.prefill});

  final Map<String, dynamic>? existing;

  /// Seeds initial field values (e.g. from the recommendation card's "remind
  /// me at off-peak" action) without switching the sheet into edit mode -
  /// only [existing] does that, so a prefilled reminder still inserts as
  /// new on save.
  final Map<String, dynamic>? prefill;

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
  String _repeatFrequency = 'once';
  late Set<int> _repeatDays;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final source = widget.existing ?? widget.prefill;
    _titleController =
        TextEditingController(text: source?['title'] as String? ?? '');
    _locationLabel = source?['location_label'] as String? ?? '';
    _chargerType = source?['charger_type'] as String?;
    _date = source?['reminder_date'] == null
        ? DateTime.now()
        : parseReminderDate(source!['reminder_date'] as String);
    _time = source?['reminder_time'] == null
        ? TimeOfDay.now()
        : parseReminderTime(source!['reminder_time'] as String);
    _repeatFrequency = source?['repeat_frequency'] as String? ?? 'once';
    final existingDays = source?['repeat_days'] as List<Object?>?;
    _repeatDays = existingDays == null || existingDays.isEmpty
        ? {_date.weekday}
        : existingDays.map((e) => e as int).toSet();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: _time);
    if (time != null) setState(() => _time = time);
  }

  static const _weekdayNames = {
    1: 'Mon',
    2: 'Tue',
    3: 'Wed',
    4: 'Thu',
    5: 'Fri',
    6: 'Sat',
    7: 'Sun',
  };

  String _repeatDescription() {
    switch (_repeatFrequency) {
      case 'weekly':
        final sortedDays = _repeatDays.toList()..sort();
        final names = sortedDays.map((d) => _weekdayNames[d]).join(', ');
        return names.isEmpty
            ? 'Pick at least one day of the week.'
            : 'You\'ll get a real notification at this time on: $names.';
      default:
        return 'You\'ll get a one-time notification on this device at '
            'this date and time. It\'ll turn itself off after that.';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final anchor = combineDateAndTime(_date, _time);
    if (_repeatFrequency == 'once' && anchor.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pick a date and time that hasn\'t passed yet.'),
        ),
      );
      return;
    }
    if (_repeatFrequency == 'weekly' && _repeatDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one day of the week.')),
      );
      return;
    }
    final repeatDays =
        _repeatFrequency == 'weekly' ? _repeatDays.toList() : const <int>[];

    setState(() => _saving = true);
    final title = _titleController.text.trim();
    final location = _locationLabel.trim();
    final locationLabel = location.isEmpty ? null : location;
    String reminderId;

    try {
      if (widget.existing == null) {
        final row = await _service.createReminder(
          title: title,
          chargerType: _chargerType,
          locationLabel: locationLabel,
          date: anchor,
          time: TimeOfDay.fromDateTime(anchor),
          repeatFrequency: _repeatFrequency,
          repeatDays: repeatDays,
        );
        reminderId = row['id'] as String;
      } else {
        reminderId = widget.existing!['id'] as String;
        await _service.updateReminder(
          reminderId,
          title: title,
          chargerType: _chargerType,
          locationLabel: locationLabel,
          date: anchor,
          time: TimeOfDay.fromDateTime(anchor),
          repeatFrequency: _repeatFrequency,
          repeatDays: repeatDays,
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
      final scheduledAt = rollReminderToFuture(
        anchor,
        _repeatFrequency,
        repeatDays: repeatDays,
      );
      try {
        await _notifications.scheduleReminder(
          reminderId: reminderId,
          title: title,
          body: 'Time to charge your EV.',
          dateTime: scheduledAt,
          repeatFrequency: _repeatFrequency,
          repeatDays: repeatDays,
        );
        if (scheduledAt != anchor) {
          await _service.updateReminderOccurrence(
            reminderId,
            date: scheduledAt,
            time: TimeOfDay.fromDateTime(scheduledAt),
          );
        }
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
        SnackBar(
          content: Text(notificationWarning),
          duration: const Duration(seconds: 6),
        ),
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
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? 'Enter a title'
                              : null,
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
                          onChanged: (value) =>
                              setState(() => _chargerType = value),
                        ),
                        const SizedBox(height: 12),
                        Autocomplete<String>(
                          initialValue: TextEditingValue(text: _locationLabel),
                          optionsBuilder: (textEditingValue) {
                            final query =
                                textEditingValue.text.trim().toLowerCase();
                            if (query.isEmpty) return const [];
                            return stationNames
                                .where(
                                  (name) => name.toLowerCase().contains(query),
                                )
                                .take(20);
                          },
                          onSelected: (value) =>
                              setState(() => _locationLabel = value),
                          fieldViewBuilder: (context, controller, focusNode,
                              onFieldSubmitted) {
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
                            if (_repeatFrequency == 'once') ...[
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
                            ],
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
                        const SizedBox(height: 12),
                        const Text(
                          'Repeat',
                          style: TextStyle(
                            fontSize: 12,
                            color: planningMutedTextColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final mode in _frequencyModes)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    right: mode == _frequencyModes.last ? 0 : 8,
                                  ),
                                  child: _FrequencyModeButton(
                                    label: mode.$2,
                                    selected: _repeatFrequency == mode.$1,
                                    onTap: () => setState(() {
                                      _repeatFrequency = mode.$1;
                                      if (mode.$1 == 'weekly' &&
                                          _repeatDays.isEmpty) {
                                        _repeatDays = {_date.weekday};
                                      }
                                    }),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_repeatFrequency == 'weekly') ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final chip in _weekdayChips)
                                _WeekdayChip(
                                  label: chip.$2,
                                  selected: _repeatDays.contains(chip.$1),
                                  onTap: () => setState(() {
                                    if (_repeatDays.contains(chip.$1)) {
                                      _repeatDays.remove(chip.$1);
                                    } else {
                                      _repeatDays.add(chip.$1);
                                    }
                                  }),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _repeatDescription(),
                          style: const TextStyle(
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
                                  isEditing
                                      ? 'Update Reminder'
                                      : 'Create Reminder',
                                ),
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

class _FrequencyModeButton extends StatelessWidget {
  const _FrequencyModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? green : const Color(0xFFF1F3F6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : planningMutedTextColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      );
}

class _WeekdayChip extends StatelessWidget {
  const _WeekdayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? green : const Color(0xFFF1F3F6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : planningMutedTextColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      );
}
