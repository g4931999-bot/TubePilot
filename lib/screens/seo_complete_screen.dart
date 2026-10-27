import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

/// Video SEO Optimizer - last step. Shows exactly what will change (the
/// video's REAL current text vs the suggestion the user picked), then
/// "Apply to YouTube" writes it with PATCH /youtube/my-videos/:id.
/// Nothing is sent to YouTube until the user taps that button.
class SeoCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final String? newTitle;
  final String? newDescription;
  final List<String>? newTags;
  const SeoCompleteScreen({super.key, required this.video, this.newTitle, this.newDescription, this.newTags});
  @override
  State<SeoCompleteScreen> createState() => _SeoCompleteScreenState();
}

class _SeoCompleteScreenState extends State<SeoCompleteScreen> {
  bool _applying = false;
  bool _applied = false;

  String get _oldTitle => (widget.video['title'] ?? '').toString();
  String get _oldDesc => (widget.video['description'] ?? '').toString();
  List<String> get _oldTags => ((widget.video['tags'] as List?) ?? []).map((e) => e.toString()).toList();

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await ApiService.instance.updateYoutubeVideoMetadata(
        (widget.video['videoId'] ?? '').toString(),
        title: widget.newTitle,
        description: widget.newDescription,
        tags: widget.newTags,
      );
      if (mounted) {
        // keep the shared video map in sync so the list / detail screens show the new text
        if (widget.newTitle != null) widget.video['title'] = widget.newTitle;
        if (widget.newDescription != null) widget.video['description'] = widget.newDescription;
        if (widget.newTags != null) widget.video['tags'] = widget.newTags;
        setState(() => _applied = true);
        showToast(context, context.tr('so_applied_toast'), isSuccess: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _copyAll() {
    final b = StringBuffer();
    if (widget.newTitle != null) b.writeln('${context.tr('so_tab_title')}:\n${widget.newTitle}\n');
    if (widget.newDescription != null) b.writeln('${context.tr('so_tab_desc')}:\n${widget.newDescription}\n');
    if (widget.newTags != null) b.writeln('${context.tr('so_tab_tags')}:\n${widget.newTags!.join(', ')}');
    Clipboard.setData(ClipboardData(text: b.toString().trim()));
    showToast(context, context.tr('rd_copied'), isSuccess: true);
  }

  Widget _change(String labelKey, String before, String after) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr(labelKey), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 10),
        Text(context.tr('so_before'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(before.isEmpty ? '—' : before, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, height: 1.35, color: context.surfaces.textDim)),
        const SizedBox(height: 10),
        Text(context.tr('so_after'), style: const TextStyle(color: AppColors.green, fontSize: 11.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(after, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: (_applied ? AppColors.green : AppColors.purple).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_applied ? Icons.check_circle_rounded : Icons.auto_awesome_rounded, size: 40, color: _applied ? AppColors.green : AppColors.purple),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(context.tr('so_complete_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        const SizedBox(height: 6),
        Center(child: Text(context.tr(_applied ? 'so_complete_done' : 'so_complete_sub'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.4))),
        if (widget.newTitle != null) _change('so_tab_title', _oldTitle, widget.newTitle!),
        if (widget.newDescription != null) _change('so_tab_desc', _oldDesc, widget.newDescription!),
        if (widget.newTags != null) _change('so_tab_tags', _oldTags.join(', '), widget.newTags!.join(', ')),
        const SizedBox(height: 22),
        GradientButton(
          label: context.tr(_applied ? 'so_applied_btn' : 'so_apply_yt_btn'),
          icon: _applied ? Icons.check_rounded : Icons.cloud_upload_rounded,
          loading: _applying,
          onPressed: _applied ? () {} : _apply,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _copyAll, icon: const Icon(Icons.copy_rounded, size: 16), label: Text(context.tr('so_copy_all_btn'))),
        TextButton(
          // complete -> detail -> video list
          onPressed: () => Navigator.of(context)
            ..pop()
            ..pop(),
          child: Text(context.tr('so_back_videos_btn')),
        ),
      ]),
    );
  }
}