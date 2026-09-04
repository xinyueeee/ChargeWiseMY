import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/fault_report.dart';
import '../services/feedback_repository.dart';

class FeedbackViewModel extends ChangeNotifier {
  FeedbackViewModel(this._repository) {
    _unsubscribe = _repository.subscribeToReports(_onRemoteChange);
  }
  final FeedbackRepository _repository;

  /// Coalesce a burst of realtime events (e.g. an admin editing several
  /// fields) into a single re-fetch.
  static const _realtimeDebounce = Duration(milliseconds: 500);

  VoidCallback? _unsubscribe;
  Timer? _refreshTimer;
  bool _disposed = false;

  List<FaultReport> myReports = const [];
  List<FaultReport> nearbyReports = const [];
  bool loading = true;
  String? errorMessage;

  void _onRemoteChange() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_realtimeDebounce, () {
      if (!_disposed) load(silent: true);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _unsubscribe?.call();
    super.dispose();
  }

  /// [silent] skips the full-screen loading state — used for background
  /// refreshes (returning to the Feedback tab, opening a child screen,
  /// pull-to-refresh) so admin-driven status changes propagate without the
  /// list flashing a spinner every time.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    errorMessage = null;
    try {
      final reports = await _repository.getReports();
      final userId = _repository.currentUserId;
      myReports = reports.where((r) => r.userId == userId).toList();
      nearbyReports = reports;
    } catch (error) {
      errorMessage = 'Unable to load fault reports. Please try again.';
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Latest server copy of a report by id, falling back to [fallback] when it
  /// isn't in the loaded list (e.g. another user's report opened from the map).
  FaultReport reportById(String id, {required FaultReport fallback}) {
    for (final report in nearbyReports) {
      if (report.id == id) return report;
    }
    return fallback;
  }

  Future<void> submitReport(FaultReport draft, List<XFile> photos) async {
    await _repository.createReport(draft, photos);
    await load();
  }

  Future<void> updateReport(
    FaultReport report,
    List<XFile>? newPhotos, {
    List<String> keepPhotoUrls = const [],
  }) async {
    await _repository.updateReport(
      report,
      newPhotos,
      keepPhotoUrls: keepPhotoUrls,
    );
    await load();
  }

  Future<void> deleteReport(String id) async {
    await _repository.deleteReport(id);
    await load();
  }
}
