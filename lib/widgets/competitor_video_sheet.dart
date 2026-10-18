import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import 'common.dart';
import 'competitor_widgets.dart';

/// Bottom sheet opened when a competitor video is tapped: thumbnail, title,
/// description and tags can be copied, the thumbnail can be downloaded.
/// Description/tags come from GET /analytics/competitors/video/:videoId.
Future<void> showCompetitorVideoSheet(BuildContext context, Map<String, dynamic> video) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _VideoSheet(video: video),
  );
}

class _VideoSheet extends StatefulWidget {
  final Map<String, dynamic> video;
  const _VideoSheet({required this.video});
  @override
  State<_VideoSheet> createState() => _VideoSheetState();
}

class _VideoSheetState extends State<_VideoSheet> {
  bool _loadingDetails = true;
  bool _downloading = false;
  String? _description; // null = unavailable
  List<String> _tags = [];
  String _title = '';

  String get _videoId => (widget.video['videoId'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    _title = (widget.video['title'] ?? '').toString();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      final res = await ApiService.instance.getCompetitorVideoDetails(_videoId);
      final v = res['video'] is Map ? Map<String, dynamic>.from(res['video']) : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _description = v['description']?.toString();
        _tags = (v['tags'] as List? ?? []).map((e) => e.toString()).toList();
        final t = (v['title'] ?? '').toString();
        if (t.isNotEmpty) _title = t;
      });
    } catch (_) {
      // description stays null -> "not available" note
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _copy(String text, {String? labelKey}) async {
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, context.tr('rd_copied'), isSuccess: true);
  }

  /// Saves the best available thumbnail into Pictures/TubePilot (or Download/TubePilot).
  /// Returns the saved path, or null if it could not be saved.
  Future<String?> _saveThumbnail() async {
    final client = HttpClient();
    try {
      List<int>? bytes;
      for (final u in [
        'https://i.ytimg.com/vi/$_videoId/maxresdefault.jpg',
        'https://i.ytimg.com/vi/$_videoId/hqdefault.jpg',
      ]) {
        final req = await client.getUrl(Uri.parse(u));
        final resp = await req.close();
        if (resp.statusCode == 200) {
          bytes = await consolidateHttpClientResponseBytes(resp);
          break;
        }
        await resp.drain();
      }
      if (bytes == null) return null;
      for (final dir in ['/storage/emulated/0/Pictures/TubePilot', '/storage/emulated/0/Download/TubePilot']) {
        try {
          final d = Directory(dir);
          await d.create(recursive: true);
          final f = File('${d.path}/thumbnail_$_videoId.jpg');
          await f.writeAsBytes(bytes, flush: true);
          return f.path;
        } catch (_) {/* try next folder */}
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final path = await _saveThumbnail();
    if (!mounted) return;
    setState(() => _downloading = false);
    if (path != null) {
      showToast(context, context.tr('rd_download_ok').replaceAll('%1', path), isSuccess: true);
    } else {
      // Could not write to storage - open the image so it can be saved from the browser.
      showToast(context, context.tr('rd_download_fail'), isSuccess: false);
      await openYoutubeVideo('https://i.ytimg.com/vi/$_videoId/maxresdefault.jpg');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final thumb = (v['thumbnail'] ?? '').toString();
    final ago = timeAgo(context, v['publishedAt']?.toString());
    final channel = (v['channelLabel'] ?? '').toString();
    final channelThumb = (v['channelThumbnail'] ?? '').toString();
    final key = (v['channelId'] ?? v['competitorId'] ?? channel).toString();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: context.surfaces.border, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                'https://i.ytimg.com/vi/$_videoId/maxresdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => thumb.isNotEmpty
                    ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))
                    : Container(color: context.surfaces.card2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (channel.isNotEmpty) competitorChannelChip(context, key: key, label: channel, thumbnail: channelThumb),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SelectableText(_title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.3))),
              IconButton(
                tooltip: context.tr('rd_copy_title'),
                onPressed: () => _copy(_title),
                icon: const Icon(Icons.copy_rounded, size: 20),
              ),
            ],
          ),
          Text(
            '${fmtCount(v['views'] as num?)} ${context.tr('rd_views_suffix')}${ago.isEmpty ? '' : ' · $ago'}',
            style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: _downloading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(context.tr('rd_download_thumb'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openYoutubeVideo(v['url']?.toString() ?? 'https://www.youtube.com/watch?v=$_videoId'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(context.tr('rd_open_youtube'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _sectionRow(context.tr('rd_description'), (_description ?? '').isEmpty ? null : () => _copy(_description!)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(12)),
            child: _loadingDetails
                ? const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                : (_description == null || _description!.trim().isEmpty)
                    ? Text(context.tr('rd_desc_unavailable'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))
                    : SelectableText(_description!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionRow(context.tr('rd_tags'), () => _copy(_tags.join(', '))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _tags
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
                        child: Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionRow(String title, VoidCallback? onCopy) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800))),
        if (onCopy != null)
          TextButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(context.tr('rd_copy'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
      ],
    );
  }
}