import 'package:flutter/foundation.dart';

import '../services/charging_service.dart';

class RemindersViewModel extends ChangeNotifier {
  RemindersViewModel(this._service);

  final ChargingService _service;

  List<Map<String, dynamic>>? _reminders;
  List<Map<String, dynamic>>? get reminders => _reminders;

  Future<void> load() async {
    final reminders = await _service.fetchReminders();
    _reminders = reminders;
    notifyListeners();
  }

  void applyLocal(String id, Map<String, dynamic> patch) {
    final current = _reminders;
    if (current == null) return;
    _reminders = [
      for (final r in current)
        if (r['id'] == id) {...r, ...patch} else r,
    ];
    notifyListeners();
  }
}
