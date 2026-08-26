import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChargingService {
  final SupabaseClient _client = Supabase.instance.client;

  String? get _userId => _client.auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> fetchSessions() async {
    final userId = _userId;
    if (userId == null) return [];
    final rows = await _client
        .from('charging_sessions')
        .select()
        .eq('user_id', userId)
        .order('session_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> createSession({
    String? stationId,
    required String stationName,
    required String chargerType,
    required double powerKw,
    required double energyKwh,
    required int durationMinutes,
    required double cost,
    required DateTime sessionAt,
    String? vehicleId,
    String? vehicleLabel,
    String? notes,
  }) async {
    final userId = _userId;
    if (userId == null) return;
    await _client.from('charging_sessions').insert({
      'user_id': userId,
      'station_id': stationId,
      'station_name': stationName.trim(),
      'charger_type': chargerType,
      'power_kw': powerKw,
      'energy_kwh': energyKwh,
      'duration_minutes': durationMinutes,
      'cost': cost,
      'session_at': sessionAt.toIso8601String(),
      'vehicle_id': vehicleId,
      'vehicle_label': vehicleLabel,
      'notes': notes,
    });
  }

  Future<void> updateSession(
    String id, {
    String? stationId,
    required String stationName,
    required String chargerType,
    required double powerKw,
    required double energyKwh,
    required int durationMinutes,
    required double cost,
    required DateTime sessionAt,
    String? vehicleId,
    String? vehicleLabel,
    String? notes,
  }) async {
    await _client.from('charging_sessions').update({
      'station_id': stationId,
      'station_name': stationName.trim(),
      'charger_type': chargerType,
      'power_kw': powerKw,
      'energy_kwh': energyKwh,
      'duration_minutes': durationMinutes,
      'cost': cost,
      'session_at': sessionAt.toIso8601String(),
      'vehicle_id': vehicleId,
      'vehicle_label': vehicleLabel,
      'notes': notes,
    }).eq('id', id);
  }

  Future<void> deleteSession(String id) async {
    await _client.from('charging_sessions').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchReminders() async {
    final userId = _userId;
    if (userId == null) return [];
    final rows = await _client
        .from('charging_reminders')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, dynamic>> createReminder({
    required String title,
    String? chargerType,
    String? locationLabel,
    required DateTime date,
    required TimeOfDay time,
    bool enabled = true,
  }) async {
    final userId = _userId!;
    final row = await _client
        .from('charging_reminders')
        .insert({
          'user_id': userId,
          'title': title.trim(),
          'charger_type': chargerType,
          'location_label': locationLabel,
          'reminder_date': _formatDate(date),
          'reminder_time': _formatTime(time),
          'enabled': enabled,
        })
        .select()
        .single();
    return row;
  }

  Future<void> updateReminder(
    String id, {
    required String title,
    String? chargerType,
    String? locationLabel,
    required DateTime date,
    required TimeOfDay time,
  }) async {
    await _client.from('charging_reminders').update({
      'title': title.trim(),
      'charger_type': chargerType,
      'location_label': locationLabel,
      'reminder_date': _formatDate(date),
      'reminder_time': _formatTime(time),
    }).eq('id', id);
  }

  Future<void> setReminderEnabled(String id, bool enabled) async {
    await _client
        .from('charging_reminders')
        .update({'enabled': enabled}).eq('id', id);
  }

  Future<void> deleteReminder(String id) async {
    await _client.from('charging_reminders').delete().eq('id', id);
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute:00';
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

TimeOfDay parseReminderTime(String value) {
  final parts = value.split(':');
  return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
}

DateTime parseReminderDate(String value) => DateTime.parse(value);

DateTime combineDateAndTime(DateTime date, TimeOfDay time) =>
    DateTime(date.year, date.month, date.day, time.hour, time.minute);
