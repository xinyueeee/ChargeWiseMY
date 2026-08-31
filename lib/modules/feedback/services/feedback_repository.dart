import 'package:image_picker/image_picker.dart';

import '../../../services/supabase_service.dart';
import '../models/fault_report.dart';

class FeedbackRepository {
  FeedbackRepository({SupabaseService? supabaseService})
      : _supabase = supabaseService ?? SupabaseService();

  final SupabaseService _supabase;

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
