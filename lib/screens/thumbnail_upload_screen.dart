import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/thumb_metrics.dart';

/// Visual Analyzer - steps 3-5: pick the improved thumbnail from the gallery
/// (made in ChatGPT or anywhere), preview it next to the current one with its
/// REAL measured scores, then Apply to YouTube (PATCH .../thumbnail ->
/// YouTube thumbnails.set). YouTube needs a verified channel and < 2 MB.
class ThumbnailUploadScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final ThumbMetrics currentMetrics;
  const ThumbnailUploadScreen({super.key, required this.video, required this.currentMetrics});
  @override
  State<ThumbnailUploadScreen> createState() => _ThumbnailUploadScreenState();
}

class _ThumbnailUploadScreenState extends State<ThumbnailUploadScreen> {
  static const _maxBytes = 2 * 1024 * 1024;
  File? _file;
  ThumbMetrics? _newM;
  bool _applying = false;
  bool _done = false;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    final f = File(x.path);
    final bytes = await f.readAsBytes();
    if (bytes.length > _maxBytes) {
      if (mounted) showToast(context, context.tr('va_too_big'), isError: true);
      return;
    }
    final m = await measureThumbnail(bytes);
    if (!mounted) return;
    setState(() {
      _file = f;
      _newM = m;
    });
  }

  Future<void> _apply() async {
    if (_file == null) return;
    setState(() => _applying = true);
    try {
      await ApiService.instance.updateYoutubeThumbnail((widget.video['videoId'] ?? '').toString(), _file!.path);
      if (!mounted) return;
      setState(() => _done = true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Widget _frame(String labelKey, Widget img, ThumbMetrics? m) => Expanded(
        child: Column(children: [
          Text(context.tr(labelKey), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: AspectRatio(aspectRatio: 16 / 9, child: img)),
          const SizedBox(height: 6),
          Text(m == null ? '—' : '${m.overall}/100', style: const TextStyle(fontWeight: FontWeight.w800)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (_done) return _success();
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final cur = Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2));
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('va_upload_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        GestureDetector(
          onTap: _pick,
          child: Container(
            height: 150,
            decoration: BoxDecoration(border: Border.all(color: AppColors.purple), borderRadius: BorderRadius.circular(16)),
            child: _file == null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.add_photo_alternate_rounded, color: AppColors.purple, size: 32),
                      const SizedBox(height: 8),
                      Text(context.tr('va_pick_gallery'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(context.tr('va_pick_rules'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                    ]),
                  )
                : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_file!, fit: BoxFit.cover, width: double.infinity)),
          ),
        ),
        if (_file != null) ...[
          const SizedBox(height: 18),
          Text(context.tr('va_preview_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _frame('va_current', cur, widget.currentMetrics),
            const SizedBox(width: 12),
            _frame('va_new', Image.file(_file!, fit: BoxFit.cover), _newM),
          ]),
          const SizedBox(height: 6),
          Text(context.tr('so_thumb_note'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
          const SizedBox(height: 18),
          GradientButton(label: context.tr('so_apply_yt_btn'), icon: Icons.cloud_upload_rounded, loading: _applying, onPressed: _apply),
          TextButton(onPressed: _pick, child: Text(context.tr('va_change_image'))),
        ],
      ]),
    );
  }

  Widget _success() {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('va_upload_title')), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 84, height: 84, decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), shape: BoxShape.circle), child: const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 48)),
          const SizedBox(height: 16),
          Text(context.tr('va_success_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(context.tr('va_success_sub'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.4)),
          const SizedBox(height: 18),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 240, child: AspectRatio(aspectRatio: 16 / 9, child: Image.file(_file!, fit: BoxFit.cover)))),
          const SizedBox(height: 24),
          GradientButton(
            label: context.tr('so_back_videos_btn'),
            icon: Icons.video_library_rounded,
            // upload -> analysis -> video list
            onPressed: () => Navigator.of(context)
              ..pop()
              ..pop(),
          ),
        ]),
      ),
    );
  }
}