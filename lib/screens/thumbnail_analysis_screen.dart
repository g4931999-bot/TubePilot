import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/thumb_metrics.dart';
import 'thumbnail_upload_screen.dart';

/// Visual Analyzer - step 2. Real on-device measurements of the video's
/// current thumbnail (see thumb_metrics.dart), improvement suggestions that
/// are each triggered by a measured number, and a JSON prompt the user can
/// paste into ChatGPT to generate a better thumbnail.
class ThumbnailAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  const ThumbnailAnalysisScreen({super.key, required this.video});
  @override
  State<ThumbnailAnalysisScreen> createState() => _ThumbnailAnalysisScreenState();
}

class _ThumbnailAnalysisScreenState extends State<ThumbnailAnalysisScreen> {
  ThumbMetrics? _m;
  bool _loading = true;
  bool _failed = false;

  static const _en = {
    'tm_sug_contrast': 'Increase contrast: make text and subject stand out from the background (outline, shadow, darker or lighter backdrop).',
    'tm_sug_dark': 'Brighten the image so the subject is clear on a small phone screen.',
    'tm_sug_bright': 'Lower the brightness and add richer shadows so details do not wash out.',
    'tm_sug_saturation': 'Use bolder, more saturated colours to catch the eye.',
    'tm_sug_composition': 'Move the main subject and text closer to the centre of the frame.',
    'tm_sug_detail': 'Add a clear focal subject with sharper detail.',
  };

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final bytes = await fetchImageBytes(url);
    final m = bytes == null ? null : await measureThumbnail(bytes);
    if (!mounted) return;
    setState(() {
      _m = m;
      _failed = m == null;
      _loading = false;
    });
  }

  Color _band(int s) => s >= 70 ? AppColors.green : (s >= 50 ? const Color(0xFFF5A623) : AppColors.red);

  /// The prompt only contains the video's real title and the numbers that
  /// were actually measured on its thumbnail.
  String _jsonPrompt() {
    final m = _m!;
    final issues = m.suggestionKeys().where(_en.containsKey).map((k) => _en[k]).toList();
    final map = {
      'task': 'Design an improved YouTube thumbnail for the video described below. I will attach my current thumbnail for reference.',
      'video_title': (widget.video['title'] ?? '').toString(),
      'output': {'aspect_ratio': '16:9', 'size': '1280x720', 'format': 'JPG or PNG', 'max_file_size': 'under 2 MB'},
      'current_thumbnail_measurements': m.factLines(),
      'problems_to_fix': issues.isEmpty ? ['No major technical problems measured - keep the style and make the subject and text even clearer.'] : issues,
      'requirements': [
        'One clear main subject, readable at 120x67 px (mobile size)',
        'Text overlay of 2 to 4 bold words that matches the video title',
        'High contrast between text and background',
        'Do not add logos or watermarks of other brands',
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  void _viewPrompt() {
    final p = _jsonPrompt();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('va_json_prompt'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 10),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(12)),
                child: SingleChildScrollView(child: SelectableText(p, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.4))),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: p));
                showToast(context, context.tr('va_prompt_copied'), isSuccess: true);
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(context.tr('rd_copy')),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openChatGpt() async {
    await Clipboard.setData(ClipboardData(text: _jsonPrompt()));
    if (mounted) showToast(context, context.tr('va_prompt_copied_open'), isSuccess: true);
    final uri = Uri.parse('https://chatgpt.com/');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {}
  }

  Widget _row(String key, int v) {
    final c = _band(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(context.tr(key), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          Text('$v/100', style: TextStyle(fontWeight: FontWeight.w800, color: c)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(value: v / 100, minHeight: 6, backgroundColor: context.surfaces.border, valueColor: AlwaysStoppedAnimation(c)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final m = _m;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('va_analysis_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(aspectRatio: 16 / 9, child: url.isNotEmpty ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2)) : Container(color: context.surfaces.card2)),
        ),
        const SizedBox(height: 10),
        Text((widget.video['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: LoadingView())
        else if (_failed || m == null)
          Text(context.tr('va_measure_failed'), style: TextStyle(color: context.surfaces.textDim))
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(context.tr('va_overall'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const Spacer(),
                Text('${m.overall}/100', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _band(m.overall))),
              ]),
              const SizedBox(height: 14),
              _row('va_visual_appeal', m.appeal),
              _row('va_readability', m.readability),
              _row('va_color_balance', m.colorBalance),
              _row('va_composition', m.composition),
              Text(context.tr('so_thumb_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('va_suggestions'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 10),
              if (m.suggestionKeys().isEmpty)
                Text(context.tr('tm_sug_none'), style: const TextStyle(fontSize: 13, height: 1.4))
              else
                for (final k in m.suggestionKeys())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.lightbulb_outline_rounded, size: 17, color: Color(0xFFF5A623)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(context.tr(k), style: const TextStyle(fontSize: 13, height: 1.4))),
                    ]),
                  ),
            ]),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.08), border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.data_object_rounded, color: AppColors.purple),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('va_json_prompt'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
              OutlinedButton(onPressed: _viewPrompt, child: Text(context.tr('va_view'))),
            ]),
          ),
          const SizedBox(height: 14),
          GradientButton(label: context.tr('va_open_gpt_btn'), icon: Icons.open_in_new_rounded, onPressed: _openChatGpt),
          const SizedBox(height: 8),
          Text(context.tr('va_gpt_hint'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThumbnailUploadScreen(video: widget.video, currentMetrics: m))),
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
            label: Text(context.tr('va_upload_btn')),
          ),
        ],
      ]),
    );
  }
}