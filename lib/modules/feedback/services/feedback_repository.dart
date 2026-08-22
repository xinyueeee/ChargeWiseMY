import 'package:image_picker/image_picker.dart';

import '../../../services/supabase_service.dart';
import '../models/fault_report.dart';

/// Wraps [SupabaseService] the same way `PlanningRepository` wraps it for
/// proposals — converts between raw Supabase rows and [FaultReport], and
/// orchestrates the two-step photo upload (insert the row, upload each
/// photo under the generated `report_id`, then attach the resulting URLs).
class FeedbackRepository {
  FeedbackRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();

  final SupabaseService _supabase;

  /// The signed-in driver's id. Every feedback screen sits behind
  /// `AuthGate`, so a real session should always exist here; `mockUserId`
  /// is only a defensive fallback, same as
  /// `SupabaseService.uploadFaultReportPhoto`.
  String get currentUserId =>
      _supabase.client.auth.currentUser?.id ?? SupabaseService.mockUserId;

  Future<List<FaultReport>> getReports() async {
    final rows = await _supabase.getFaultReports();
    return rows.map(FaultReport.fromSupabase).toList();
  }

  Future<void> createReport(FaultReport draft, List<XFile> photos) async {
    final reportId = await _supabase.insertFaultReport({
      'user_id': currentUserId,
      ..._toValues(draft),
    });
    if (photos.isNotEmpty) {
      final photoUrls = await _uploadPhotos(reportId, photos);
      await _supabase.updateFaultReport(reportId, {'photo_urls': photoUrls});
    }
  }

  /// [newPhotos] is `null` to leave the existing photos untouched entirely
  /// (no re-upload, `photo_urls` isn't sent), or a (possibly empty) list of
  /// newly-picked local files to upload. When [newPhotos] is non-null, the
  /// final `photo_urls` is [keepPhotoUrls] (already-uploaded URLs the
  /// caller wants to retain) plus the freshly uploaded ones — the caller
  /// (`NewReportScreen` in edit mode) is responsible for tracking which
  /// existing photos the driver removed vs kept.
  Future<void> updateReport(
    FaultReport report,
    List<XFile>? newPhotos, {
    List<String> keepPhotoUrls = const [],
  }) async {
    final values = _toValues(report);
    if (newPhotos != null) {
      final uploaded = await _uploadPhotos(report.id, newPhotos);
      values['photo_urls'] = [...keepPhotoUrls, ...uploaded];
    }
    await _supabase.updateFaultReport(report.id, values);
  }

  Future<void> deleteReport(String id) => _supabase.deleteFaultReport(id);

  Future<List<String>> _uploadPhotos(String reportId, List<XFile> photos) =>
      Future.wait([
        for (var index = 0; index < photos.length; index++)
          _supabase.uploadFaultReportPhoto(
            reportId,
            photos[index],
            index: index,
          ),
      ]);

  /// Fields the driver controls. Deliberately excludes `status` — only the
  /// admin side writes that (see MODULE3_ADMIN_IMPLEMENTATION_PLAN.md); RLS
  /// also only allows edits while a report is still `submitted`.
  Map<String, dynamic> _toValues(FaultReport report) => {
        'category': report.category,
        'description': report.description,
        'station_id': report.stationId,
        'contact_info': report.contactInfo,
        'latitude': report.latitude,
        'longitude': report.longitude,
        'address': report.locationLabel,
      };
}