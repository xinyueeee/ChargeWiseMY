import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user_summary.dart';
import '../services/user_admin_repository.dart';

class AdminUserViewModel extends ChangeNotifier {
  AdminUserViewModel(this._repository);
  final UserAdminRepository _repository;

  List<AdminUserSummary> users = const [];
  bool loading = true;
  String? errorMessage;
  final Set<String> _updatingUserIds = {};

  int get totalCount => users.length;
  int get activeCount => users.where((u) => u.isActive).length;
  int get deactivatedCount => users.where((u) => !u.isActive).length;

  bool isUpdating(AdminUserSummary user) => _updatingUserIds.contains(user.id);

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      users = await _repository.getAllUsers();
    } catch (error, stackTrace) {
      debugPrint('AdminUserViewModel.load failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      errorMessage = 'Unable to load users. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> setStatus(AdminUserSummary user, String status) async {
    if (status == 'deactivated' &&
        user.id == Supabase.instance.client.auth.currentUser?.id) {
      return "You can't deactivate your own account.";
    }
    _updatingUserIds.add(user.id);
    notifyListeners();
    try {
      await _repository.setStatus(user.id, status);
      await load();
      return null;
    } on PostgrestException catch (error, stackTrace) {
      debugPrint('AdminUserViewModel.setStatus rejected: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      return error.message;
    } catch (error, stackTrace) {
      debugPrint('AdminUserViewModel.setStatus failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return 'Unable to update this user. Please try again.';
    } finally {
      _updatingUserIds.remove(user.id);
      notifyListeners();
    }
  }
}
