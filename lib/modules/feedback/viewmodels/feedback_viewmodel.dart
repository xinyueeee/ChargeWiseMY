import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/fault_report.dart';
import '../services/feedback_repository.dart';

/// Mirrors `PlanningViewModel`'s shape: a single `ChangeNotifier` the
/// screens read via `Consumer`/`context.watch`, backed by
/// [FeedbackRepository].
class FeedbackViewModel extends ChangeNotifier {
  FeedbackViewModel(this._repository);
  final FeedbackRepository _repository;

  List<FaultReport> myReports = const [];
  List<FaultReport> nearbyReports = const [];
  bool loading = true;
  String? errorMessage;

  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final reports = await _repository.getReports();
      final userId = _repository.currentUserId;
      myReports = reports.where((r) => r.userId == userId).toList();
      nearbyReports = reports;
    } catch (error) {
      errorMessage = 'Unable to load fault reports. Please try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
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