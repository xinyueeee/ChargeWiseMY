import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../planning/widgets/planning_widgets.dart';

final _rmFormat = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'RM',
  decimalDigits: 2,
);

String formatRm(num amount) => _rmFormat.format(amount);

final twoDecimalInputFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) {
    if (newValue.text.isEmpty) return newValue;
    final isValid = RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text);
    return isValid ? newValue : oldValue;
  },
);

const chargingDcColor = Colors.orange;
const chargingAcColor = Colors.deepPurple;

const chargingPowerMinKw = 1;
const chargingPowerMaxKw = 999;

String? validateChargingPowerKw(String? value) {
  final power = int.tryParse((value ?? '').trim());
  if (power == null) return 'Enter power in kW';
  if (power < chargingPowerMinKw || power > chargingPowerMaxKw) {
    return 'Charging power should be '
        '$chargingPowerMinKw-$chargingPowerMaxKw kW';
  }
  return null;
}

const chargerTypes = ['AC Charger', 'DC Fast Charger'];

Color colorForChargerType(String? chargerType) {
  final type = (chargerType ?? '').toLowerCase();
  if (type.contains('dc')) return chargingDcColor;
  return chargingAcColor;
}

class ChargerTypeIcon extends StatelessWidget {
  const ChargerTypeIcon({super.key, required this.chargerType, this.size = 40});

  final String? chargerType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorForChargerType(chargerType);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.bolt, color: Colors.white, size: size * 0.55),
    );
  }
}

class ChargingSectionHeader extends StatelessWidget {
  const ChargingSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: planningTextColor,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: planningMutedTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      );
}

String formatSessionDate(DateTime dateTime) {
  const months = [
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
  final local = dateTime.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  return '${local.day} ${months[local.month - 1]} ${local.year}, '
      '$hour12:$minute $period';
}

String relativeDateLabel(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  const months = [
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
  return '${date.day} ${months[date.month - 1]}';
}

String formatDuration(int totalMinutes) {
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

class DurationPickerField extends StatelessWidget {
  const DurationPickerField({
    super.key,
    required this.label,
    required this.hours,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int hours;
  final int minutes;
  final void Function(int hours, int minutes) onChanged;

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<(int, int)>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _DurationPickerSheet(
        initialHours: hours,
        initialMinutes: minutes,
      ),
    );
    if (result != null) onChanged(result.$1, result.$2);
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => _open(context),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: Text(formatDuration(hours * 60 + minutes)),
        ),
      );
}

class _DurationPickerSheet extends StatefulWidget {
  const _DurationPickerSheet({
    required this.initialHours,
    required this.initialMinutes,
  });

  final int initialHours;
  final int initialMinutes;

  @override
  State<_DurationPickerSheet> createState() => _DurationPickerSheetState();
}

class _DurationPickerSheetState extends State<_DurationPickerSheet> {
  late int _hours = widget.initialHours;
  late int _minutes = widget.initialMinutes;

  @override
  Widget build(BuildContext context) => SafeArea(
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Charging Duration',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 160,
                        child: Row(
                          children: [
                            Expanded(
                              child: CupertinoPicker(
                                itemExtent: 36,
                                scrollController: FixedExtentScrollController(
                                  initialItem: _hours,
                                ),
                                onSelectedItemChanged: (index) =>
                                    setState(() => _hours = index),
                                children: [
                                  for (var h = 0; h <= 23; h++)
                                    Center(child: Text('$h h')),
                                ],
                              ),
                            ),
                            Expanded(
                              child: CupertinoPicker(
                                itemExtent: 36,
                                scrollController: FixedExtentScrollController(
                                  initialItem: _minutes,
                                ),
                                onSelectedItemChanged: (index) =>
                                    setState(() => _minutes = index),
                                children: [
                                  for (var m = 0; m <= 59; m++)
                                    Center(child: Text('$m min')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: green,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () =>
                            Navigator.of(context).pop((_hours, _minutes)),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
