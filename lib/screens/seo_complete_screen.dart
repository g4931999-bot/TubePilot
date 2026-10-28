import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

String _tx(BuildContext c, String key, String fallback) {
  final v = c.tr(key);
  return (v.isEmpty || v == key) ? fallback : v;
}

/// Video SEO Optimizer - last step. Summary card (like the mockup) + the real
/// before/after text. Nothing is sent to YouTube until the user taps
/// "Apply to YouTube" (PATCH /youtube/my-videos/:id); rows turn to "Updated"
/// only after that call succeeds.
class SeoCompleteScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final String? newTitle;
  final String? newDescription;
  final List<String>? newTags;
  final int? thumbScore;
  final VoidCallback? onApplied;
  const SeoCompleteScreen({super.key, required this.video, this.newTitle, this.newDescription, this.newTags, this.thumbScore, this.onApplied});
  @override
  State<SeoCompleteScreen> createState() => _SeoCompleteScreenState();
}

class _SeoCompleteScreenState extends State<SeoCompleteScreen> {
  bool _applying = false;
  bool _applied = false;

  String get _oldTitle => (widget.video['title'] ?? '').toString();
  String get _oldDesc => (widget.video['description'] ?? '').toString();
  List<String> get _oldTags => ((widget.video['tags'] as List?) ?? []).map((e) => e.toString()).toList();

  // old text is captured once, because the shared video map is updated after apply
  late final String _beforeTitle = _oldTitle;
  late final String _beforeDesc = _oldDesc;
  late final String _beforeTags = _oldTags.join(', ');

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
        // keep the shared video map in sync so the list / score screens show the new text
        if (widget.newTitle != null) widget.video['title'] = widget.newTitle;
        if (widget.newDescription != null) widget.video['description'] = widget.newDescription;
        if (widget.newTags != null) widget.video['tags'] = widget.newTags;
        widget.onApplied?.call();
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

  Widget _statusRow(IconData icon, String label, {String? valueText, bool pending = false, bool last = false}) {
    final done = _applied && !pending;
    final Widget trailing = valueText != null
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            Text(valueText, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(width: 4),
            const Icon(Icons.check_rounded, color: AppColors.green, size: 17),
          ])
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Text(
              done ? _tx(context, 'so_status_updated', 'Updated') : _tx(context, 'so_status_ready', 'Ready to apply'),
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: done ? AppColors.green : context.surfaces.textDim),
            ),
            if (done) ...[const SizedBox(width: 4), const Icon(Icons.check_rounded, color: AppColors.green, size: 17)],
          ]);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: context.surfaces.border))),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.purple),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
        trailing,
      ]),
    );
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
    final rows = <Widget>[];
    if (widget.newTitle != null) rows.add(_statusRow(Icons.title_rounded, _tx(context, 'so_row_title', 'Optimized Title')));
    if (widget.newDescription != null) rows.add(_statusRow(Icons.description_rounded, _tx(context, 'so_row_desc', 'Improved Description')));
    if (widget.newTags != null) rows.add(_statusRow(Icons.sell_rounded, _tx(context, 'so_row_tags', 'Suggested Tags')));
    if (widget.thumbScore != null) {
      rows.add(_statusRow(Icons.image_rounded, _tx(context, 'so_row_thumb', 'Thumbnail Rating'), valueText: '${widget.thumbScore}/100', pending: true));
    }
    // last row without the bottom divider
    final summary = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      summary.add(rows[i]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(color: (_applied ? AppColors.green : AppColors.purple).withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(_applied ? Icons.check_circle_rounded : Icons.auto_awesome_rounded, size: 44, color: _applied ? AppColors.green : AppColors.purple),
          ),
        ),
        const SizedBox(height: 14),
        Center(child: Text(context.tr('so_complete_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        const SizedBox(height: 6),
        Center(child: Text(context.tr(_applied ? 'so_complete_done' : 'so_complete_sub'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.4))),
        if (summary.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: summary),
          ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(_tx(context, 'so_see_changes', 'See exact changes'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            children: [
              if (widget.newTitle != null) _change('so_tab_title', _beforeTitle, widget.newTitle!),
              if (widget.newDescription != null) _change('so_tab_desc', _beforeDesc, widget.newDescription!),
              if (widget.newTags != null) _change('so_tab_tags', _beforeTags, widget.newTags!.join(', ')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        GradientButton(
          label: context.tr(_applied ? 'so_applied_btn' : 'so_apply_yt_btn'),
          icon: _applied ? Icons.check_rounded : Icons.cloud_upload_rounded,
          loading: _applying,
          onPressed: _applied ? () {} : _apply,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: _copyAll, icon: const Icon(Icons.copy_rounded, size: 16), label: Text(context.tr('so_copy_all_btn'))),
        TextButton(
          // complete -> analysis -> score -> video list
          onPressed: () => Navigator.of(context)
            ..pop()
            ..pop()
            ..pop(),
          child: Text(context.tr('so_back_videos_btn')),
        ),
      ]),
    );
  }
}