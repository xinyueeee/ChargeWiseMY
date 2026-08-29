import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the last few email addresses used to successfully log in on
/// this device, so the login screen can suggest them - a plain
/// autocomplete convenience, never used for authentication itself. Stored
/// locally only (SharedPreferences), never synced anywhere or sent to the
/// server; a different device or a fresh install starts with none.
class RecentLoginEmailsService {
  static const _key = 'recent_login_emails';
  static const maxEntries = 6;

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? const [];
  }

  /// Moves [email] to the front of the list (case-insensitive de-duped),
  /// trimmed to [maxEntries]. Call this only after a login actually
  /// succeeds, so the list stays a list of real accounts, not typos.
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

  /// Removes one remembered email (e.g. the user dismissed it from the
  /// suggestions list).
  Future<void> forget(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? const [];
    final updated = existing
        .where((e) => e.toLowerCase() != email.trim().toLowerCase())
        .toList();
    await prefs.setStringList(_key, updated);
  }
}
