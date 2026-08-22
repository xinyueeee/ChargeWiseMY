import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/proposal_photo_service.dart';
import 'planning_widgets.dart';

class ProposalSitePhoto extends StatefulWidget {
  const ProposalSitePhoto({
    super.key,
    required this.storagePath,
    this.height = 190,
  });

  final String storagePath;
  final double height;

  @override
  State<ProposalSitePhoto> createState() => _ProposalSitePhotoState();
}

class _ProposalSitePhotoState extends State<ProposalSitePhoto> {
  final ProposalPhotoService _photos = ProposalPhotoService();
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = _photos.createSignedUrl(widget.storagePath);
  }

  @override
  void didUpdateWidget(covariant ProposalSitePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _signedUrl = _photos.createSignedUrl(widget.storagePath);
    }
  }

  void _retry() => setState(
        () => _signedUrl = _photos.createSignedUrl(widget.storagePath),
      );

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: FutureBuilder<String>(
            future: _signedUrl,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return SizedBox(
                  height: widget.height,
                  child: const Center(
                    child: CircularProgressIndicator.adaptive(),
                  ),
                );
              }
              final url = snapshot.data;
              if (snapshot.hasError || url == null) {
                return _PhotoLoadError(onRetry: _retry);
              }
              return Semantics(
                button: true,
                label: 'Open site photo full screen',
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _FullScreenPhoto(url: url),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: double.infinity,
                      height: widget.height,
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _PhotoLoadError(
                          onRetry: _retry,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
}

class LocalProposalPhotoPreview extends StatelessWidget {
  const LocalProposalPhotoPreview({
    super.key,
    required this.bytes,
    this.height = 160,
  });

  final Uint8List bytes;
  final double height;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          ),
        ),
      );
}

class _PhotoLoadError extends StatelessWidget {
  const _PhotoLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF3D7AA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.orange),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Site photo could not be loaded. Check your connection or access.',
                style: TextStyle(color: planningMutedTextColor),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _FullScreenPhoto extends StatelessWidget {
  const _FullScreenPhoto({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Site Photo'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Unable to display the site photo.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
