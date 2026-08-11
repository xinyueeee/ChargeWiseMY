import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
  }) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
      data: {'full_name': fullName.trim()},
    );

    final userId = response.user?.id;
    if (userId != null) {
      await _client.from('users').upsert({
        'id': userId,
        'full_name': fullName.trim(),
        'email': email.trim(),
        'role': 'driver',
      });
    }

    // With email confirmation off, signUp() logs the user in immediately.
    // Sign back out so they land on Login and authenticate deliberately,
    // instead of being dropped straight into the app.
    if (_client.auth.currentSession != null) {
      await _client.auth.signOut();
    }
  }

  Future<void> logout() => _client.auth.signOut();

  Future<Map<String, dynamic>?> fetchProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return await _client.from('users').select().eq('id', userId).maybeSingle();
  }

  Future<void> updateProfile({
    required String fullName,
    String? phoneNumber,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await _client.from('users').update({
      'full_name': fullName.trim(),
      'phone_number': phoneNumber?.trim(),
    }).eq('id', userId);
  }

  Future<List<Map<String, dynamic>>> fetchVehicles() async {
    final userId = currentUser?.id;
    if (userId == null) return [];
    final rows = await _client
        .from('vehicles')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> addVehicle({
    required String make,
    required String model,
  }) async {
    final userId = currentUser?.id;
    if (userId == null) return;
    await _client.from('vehicles').insert({
      'user_id': userId,
      'make': make.trim(),
      'model': model.trim(),
    });
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _client.from('vehicles').delete().eq('id', vehicleId);
  }

  Future<void> updatePassword(String newPassword) async {
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<String?> uploadAvatar(XFile file) async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    final bytes = await file.readAsBytes();
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final path = '$userId/avatar.$extension';

    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: file.mimeType),
        );

    // Cache-bust so a previously cached image doesn't hide the new upload.
    final publicUrl =
        '${_client.storage.from('avatars').getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';

    await _client
        .from('users')
        .update({'avatar_url': publicUrl}).eq('id', userId);

    return publicUrl;
  }
}
