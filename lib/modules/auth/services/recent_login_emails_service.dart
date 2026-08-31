import 'package:shared_preferences/shared_preferences.dart';

class RecentLoginEmailsService {
  static const _key = 'recent_login_emails';
  static const maxEntries = 6;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  Future<void> remember(String email) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const [];
    final updated = [
      trimmed,
      for (final e in existing)
        if (e.toLowerCase() != trimmed.toLowerCase()) e,
    ].take(maxEntries).toList();
    await prefs.setStringList(_key, updated);
  }

  Future<void> forget(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const [];
    final updated = existing
        .where((e) => e.toLowerCase() != email.trim().toLowerCase())
        .toList();
    await prefs.setStringList(_key, updated);
  }
}
