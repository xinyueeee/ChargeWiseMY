import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProposalPhotoUpload {
  const ProposalPhotoUpload({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final String extension;
  final String contentType;
}

class ProposalPhotoService {
  ProposalPhotoService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const bucketName = 'proposal-site-photos';
  static const signedUrlLifetimeSeconds = 3600;
  static const _uploadTimeout = Duration(seconds: 45);
  static const _requestTimeout = Duration(seconds: 20);

  final SupabaseClient _client;

  Future<String> uploadAndAttach({
    required String proposalId,
    required ProposalPhotoUpload upload,
    String? previousPath,
  }) async {
    final userId = _requireAuthenticatedUser();
    final generatedName =
        'site-${DateTime.now().toUtc().microsecondsSinceEpoch}.${upload.extension}';
    final path = '$userId/$proposalId/$generatedName';
    try {
      await _client.storage
          .from(bucketName)
          .uploadBinary(
            path,
            upload.bytes,
            fileOptions: FileOptions(
              contentType: upload.contentType,
              cacheControl: '3600',
              upsert: false,
            ),
          )
          .timeout(_uploadTimeout);
      final updated = await _client
          .from('proposals')
          .update({'site_photo_path': path})
          .eq('proposal_id', proposalId)
          .eq('user_id', userId)
          .select('proposal_id')
          .maybeSingle()
          .timeout(_requestTimeout);
      if (updated == null) {
        throw StateError('Authenticated user does not own this proposal.');
      }
    } catch (error) {
      await _removeBestEffort(path, operation: 'rollback');
      rethrow;
    }
    if (previousPath != null && previousPath != path) {
      await _removeOwnedBestEffort(
        previousPath,
        userId: userId,
        proposalId: proposalId,
        operation: 'replacement cleanup',
      );
    }
    return path;
  }

  Future<void> removeAndDetach({
    required String proposalId,
    required String path,
  }) async {
    final userId = _requireAuthenticatedUser();
    final updated = await _client
        .from('proposals')
        .update({'site_photo_path': null})
        .eq('proposal_id', proposalId)
        .eq('user_id', userId)
        .select('proposal_id')
        .maybeSingle()
        .timeout(_requestTimeout);
    if (updated == null) {
      throw StateError('Authenticated user does not own this proposal.');
    }
    await _removeOwnedBestEffort(
      path,
      userId: userId,
      proposalId: proposalId,
      operation: 'photo removal',
    );
  }

  Future<String> createSignedUrl(String path) => _client.storage
      .from(bucketName)
      .createSignedUrl(path, signedUrlLifetimeSeconds)
      .timeout(_requestTimeout);

  Future<void> cleanupAfterProposalDeletion({
    required String proposalId,
    required String path,
  }) async {
    final userId = _requireAuthenticatedUser();
    await _removeOwnedBestEffort(
      path,
      userId: userId,
      proposalId: proposalId,
      operation: 'proposal deletion cleanup',
    );
  }

  String _requireAuthenticatedUser() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException(
        'Authentication is required for proposal photo operations.',
      );
    }
    return userId;
  }

  Future<void> _removeOwnedBestEffort(
    String path, {
    required String userId,
    required String proposalId,
    required String operation,
  }) async {
    if (!path.startsWith('$userId/$proposalId/')) {
      debugPrint(
        'Proposal photo $operation skipped: object path did not match the '
        'authenticated proposal owner.',
      );
      return;
    }
    await _removeBestEffort(path, operation: operation);
  }

  Future<void> _removeBestEffort(
    String path, {
    required String operation,
  }) async {
    try {
      await _client.storage
          .from(bucketName)
          .remove([path]).timeout(_requestTimeout);
    } catch (error, stackTrace) {
      debugPrint('Proposal photo $operation failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
