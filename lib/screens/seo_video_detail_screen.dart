import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/thumb_metrics.dart';
import '../widgets/competitor_widgets.dart' show fmtCount, timeAgo;
import 'diamond_store_screen.dart';
import 'seo_complete_screen.dart';

/// Video SEO Optimizer - step 2: score + Overview / Title / Description / Tags.
///
/// Real-data rules:
///  * Overall + Title/Description/Tags scores = POST /ai/seo-score (AI analysis
///    of the video's real title/description/tags, 1 diamond, NOT an official
///    YouTube score). Cached per video for this session so re-opening is free.
///  * Thumbnail score = measured on-device from the real thumbnail pixels (free).
///  * Title / description suggestions = POST /ai/title-options and
///    /ai/description-options (3 diamonds each, only when the user taps).
///  * Every "check" row is computed from the video's real text.
class SeoVideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  const SeoVideoDetailScreen({super.key, required this.video});

  /// videoId -> last /ai/seo-score result (session cache).
  static final Map<String, Map<String, dynamic>> cache = {};

  @override
  State<SeoVideoDetailScreen> createState() => _SeoVideoDetailScreenState();
}

class _SeoVideoDetailScreenState extends State<SeoVideoDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _unlocked = false;
  bool _analyzing = false;
  bool _showDetail = false;
  bool _genTitles = false;
  bool _genDescs = false;
  Map<String, dynamic>? _result;
  ThumbMetrics? _thumb;
  List<String> _titles = [];
  List<String> _descs = [];
  String? _pickedTitle;
  String? _pickedDesc;
  bool _pickedTags = false;

  String get _vid => (widget.video['videoId'] ?? '').toString();
  String get _title => (widget.video['title'] ?? '').toString();
  String get _desc => (widget.video['description'] ?? '').toString();
  List<String> get _tags => ((widget.video['tags'] as List?) ?? []).map((e) => e.toString()).toList();

  @override
  void initState() {
    super.initState();
    _result = SeoVideoDetailScreen.cache[_vid];
    _tabs.addListener(() => setState(() {}));
    _loadPlan();
    _measureThumb();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPlan() async {
    try {
      final dash = await ApiService.instance.dashboard();
      final level = dash['data']?['seoScoreLevel'] as String?;
      if (mounted) setState(() => _unlocked = level != null && level != 'none');
    } catch (_) {}
  }

  Future<void> _measureThumb() async {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final bytes = await fetchImageBytes(url);
    if (bytes == null) return;
    final m = await measureThumbnail(bytes);
    if (mounted) setState(() => _thumb = m);
  }

  void _goUpgrade() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));

  Future<void> _analyze() async {
    if (!_unlocked) return _goUpgrade();
    if (_title.trim().isEmpty) {
      showToast(context, context.tr('seo_enter_title_error'), isError: true);
      return;
    }
    setState(() => _analyzing = true);
    try {
      final res = await ApiService.instance.aiSeoScore(title: _title, description: _desc, tags: _tags);
      SeoVideoDetailScreen.cache[_vid] = res;
      if (mounted) setState(() => _result = res);
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  String _topic() {
    final d = _desc.trim();
    return d.isEmpty ? _title : '$_title - ${d.length > 200 ? d.substring(0, 200) : d}';
  }

  List<String> _asStrings(dynamic list, List<String> keys) {
    return ((list as List?) ?? []).map((e) {
      if (e is Map) {
        for (final k in keys) {
          if (e[k] != null) return e[k].toString();
        }
        return '';
      }
      return e.toString();
    }).where((s) => s.trim().isNotEmpty).toList();
  }

  Future<void> _generateTitles() async {
    setState(() => _genTitles = true);
    try {
      final res = await ApiService.instance.aiTitleOptions(_topic(), count: 5);
      final list = _asStrings(res['titles'], ['title', 'text']);
      if (mounted) setState(() => _titles = list);
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _genTitles = false);
    }
  }

  Future<void> _generateDescs() async {
    setState(() => _genDescs = true);
    try {
      final res = await ApiService.instance.aiDescriptionOptions(_topic(), count: 3);
      final list = _asStrings(res['descriptions'], ['description', 'text']);
      if (mounted) setState(() => _descs = list);
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _genDescs = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.tr('rd_copied'), isSuccess: true);
  }

  Color _band(int s) => s > 70 ? AppColors.green : (s >= 50 ? const Color(0xFFF5A623) : AppColors.red);

  List<String> get _recTags => _unlocked ? ((_result?['recommendedTags'] as List?) ?? []).map((e) => e.toString()).toList() : <String>[];

  bool get _hasPick => _pickedTitle != null || _pickedDesc != null || _pickedTags;

  void _apply() {
    final tags = _pickedTags ? {..._tags, ..._recTags}.toList() : null;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeoCompleteScreen(
        video: widget.video,
        newTitle: _pickedTitle,
        newDescription: _pickedDesc,
        newTags: tags,
      ),
    ));
  }

  // ───────────── UI pieces ─────────────

  Widget _card({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        width: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _label(String key) => Text(context.tr(key), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700));

  Widget _scoreTile(String key, int? v) {
    final c = v == null ? context.surfaces.textDim : _band(v);
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.withValues(alpha: 0.4))),
        child: Column(children: [
          Text(v == null ? '—' : '$v', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 2),
          Text(context.tr(key), textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: context.surfaces.textDim, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _gauge(int score) {
    final c = _band(score);
    return Center(
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox(width: 140, height: 140, child: CircularProgressIndicator(value: score / 100, strokeWidth: 11, backgroundColor: context.surfaces.border, valueColor: AlwaysStoppedAnimation(c))),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: c)),
            Text(context.tr(score > 70 ? 'seo_band_strong' : (score >= 50 ? 'seo_band_needs_work' : 'seo_band_weak')), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
          ]),
        ]),
      ),
    );
  }

  Widget _check(bool ok, String key, {String? arg}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 17, color: ok ? AppColors.green : const Color(0xFFF5A623)),
          const SizedBox(width: 8),
          Expanded(child: Text(arg == null ? context.tr(key) : context.tr(key).replaceAll('%1', arg), style: const TextStyle(fontSize: 13, height: 1.35))),
        ]),
      );

  Widget _copyUseRow({required String text, required bool picked, required VoidCallback onUse}) => Row(children: [
        TextButton.icon(onPressed: () => _copy(text), icon: const Icon(Icons.copy_rounded, size: 15), label: Text(context.tr('rd_copy'))),
        const Spacer(),
        picked
            ? Row(children: [const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 17), const SizedBox(width: 4), Text(context.tr('so_selected'), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 12.5))])
            : OutlinedButton(onPressed: onUse, child: Text(context.tr('so_use_this'))),
      ]);

  // ───────────── tabs ─────────────

  Widget _overviewTab() {
    final issues = ((_result?['issues'] as List?) ?? []).map((e) => e.toString()).toList();
    final notes = (_result?['notes'] ?? '').toString();
    final sugKeys = _thumb?.suggestionKeys() ?? [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_result == null)
        _card(child: Text(context.tr('so_run_first'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)))
      else ...[
        if (issues.isNotEmpty)
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('vso_issues_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 10),
              for (final i in issues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFF5A623)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i, style: const TextStyle(fontSize: 13, height: 1.4))),
                  ]),
                ),
            ]),
          ),
        if (notes.isNotEmpty) _card(child: Text(notes, style: TextStyle(fontSize: 13, color: context.surfaces.textDim, height: 1.4))),
      ],
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('so_thumb_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          if (_thumb == null)
            Text(context.tr('so_thumb_measuring'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))
          else if (sugKeys.isEmpty)
            _check(true, 'tm_sug_none')
          else
            for (final k in sugKeys) _check(false, k),
          const SizedBox(height: 4),
          Text(context.tr('so_thumb_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
        ]),
      ),
    ]);
  }

  Widget _titleTab() {
    final len = _title.runes.length;
    final hasNum = RegExp(r'\d').hasMatch(_title);
    final words = _tags.expand((t) => t.toLowerCase().split(RegExp(r'\s+'))).where((w) => w.length > 2).toSet();
    final lower = _title.toLowerCase();
    final hasKw = words.any(lower.contains);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('so_current_title'),
          const SizedBox(height: 6),
          Text(_title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
          const SizedBox(height: 12),
          _check(len <= 70, 'so_chk_title_len', arg: '$len'),
          _check(hasNum, 'so_chk_title_num'),
          _check(hasKw, 'so_chk_title_kw'),
        ]),
      ),
      const SizedBox(height: 14),
      GradientButton(
        label: context.tr(_titles.isEmpty ? 'so_gen_titles_btn' : 'so_improve_ai_btn'),
        icon: Icons.auto_awesome_rounded,
        loading: _genTitles,
        onPressed: _generateTitles,
      ),
      if (_titles.isNotEmpty) ...[
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.purple, size: 18),
              const SizedBox(width: 6),
              Text(context.tr('so_suggested_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
            const SizedBox(height: 8),
            Text(_titles.first, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
            const SizedBox(height: 10),
            Text(context.tr('so_why_works'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _check(_titles.first.runes.length <= 70, 'so_chk_title_len', arg: '${_titles.first.runes.length}'),
            _check(RegExp(r'\d').hasMatch(_titles.first), 'so_chk_title_num'),
            _check(words.any(_titles.first.toLowerCase().contains), 'so_chk_title_kw'),
            _copyUseRow(text: _titles.first, picked: _pickedTitle == _titles.first, onUse: () => setState(() => _pickedTitle = _titles.first)),
          ]),
        ),
        if (_titles.length > 1) ...[
          const SizedBox(height: 16),
          _label('so_more_titles'),
          for (final t in _titles.skip(1))
            _card(
              margin: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.3)),
                _copyUseRow(text: t, picked: _pickedTitle == t, onUse: () => setState(() => _pickedTitle = t)),
              ]),
            ),
        ],
      ],
    ]);
  }

  Widget _descTab() {
    final len = _desc.runes.length;
    final hasLink = RegExp(r'https?://').hasMatch(_desc);
    final hashtags = RegExp(r'#\w+').allMatches(_desc).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('so_current_desc'),
          const SizedBox(height: 6),
          Text(_desc.isEmpty ? context.tr('so_desc_empty') : _desc, maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          _check(len >= 200, 'so_chk_desc_len', arg: '$len'),
          _check(hasLink, 'so_chk_desc_link'),
          _check(hashtags >= 1 && hashtags <= 3, 'so_chk_desc_tags', arg: '$hashtags'),
        ]),
      ),
      const SizedBox(height: 14),
      GradientButton(
        label: context.tr(_descs.isEmpty ? 'so_gen_desc_btn' : 'so_improve_ai_btn'),
        icon: Icons.auto_awesome_rounded,
        loading: _genDescs,
        onPressed: _generateDescs,
      ),
      for (final d in _descs)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d, style: const TextStyle(fontSize: 13, height: 1.4)),
            _copyUseRow(text: d, picked: _pickedDesc == d, onUse: () => setState(() => _pickedDesc = d)),
          ]),
        ),
    ]);
  }

  Widget _tagsTab() {
    final used = _tags.join(',').length;
    final rec = _recTags;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('so_current_tags'),
          const SizedBox(height: 8),
          if (_tags.isEmpty)
            Text(context.tr('so_tags_empty'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13))
          else
            Wrap(spacing: 8, runSpacing: 8, children: _tags.map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact)).toList()),
          const SizedBox(height: 12),
          _check(_tags.length >= 5, 'so_chk_tags_count', arg: '${_tags.length}'),
          _check(used <= 500, 'so_chk_tags_chars', arg: '$used'),
        ]),
      ),
      if (_result == null)
        _card(child: Text(context.tr('so_run_first'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)))
      else if (rec.isNotEmpty)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _label('seo_recommended_tags'),
              const Spacer(),
              TextButton.icon(onPressed: () => _copy(rec.join(', ')), icon: const Icon(Icons.copy_rounded, size: 15), label: Text(context.tr('seo_copy_all_btn'))),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: rec.map((t) => Chip(label: Text(t), backgroundColor: AppColors.purple.withValues(alpha: 0.12), visualDensity: VisualDensity.compact)).toList()),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: _pickedTags
                  ? Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 17), const SizedBox(width: 4), Text(context.tr('so_selected'), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 12.5))])
                  : OutlinedButton(onPressed: () => setState(() => _pickedTags = true), child: Text(context.tr('so_add_tags_btn'))),
            ),
          ]),
        )
      else if (!_unlocked)
        _card(child: Row(children: [
          const Icon(Icons.diamond_rounded, color: AppColors.diamond, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(context.tr('vso_upgrade_notice'), style: const TextStyle(fontSize: 12.5, height: 1.4))),
          TextButton(onPressed: _goUpgrade, child: Text(context.tr('vso_upgrade_btn'))),
        ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final overall = (_result?['seoScore'] as num?)?.toInt();
    final bd = _result?['breakdown'] as Map?;
    int? sc(String k) => (bd?[k] as num?)?.toInt();
    final views = widget.video['viewCount'] as num?;
    final ago = timeAgo(context, widget.video['publishedAt']?.toString());
    final thumbUrl = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: GradientButton(label: context.tr('apply_to_video_btn_label'), icon: Icons.send_rounded, onPressed: _hasPick ? _apply : () => showToast(context, context.tr('so_pick_first'), isError: true)),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: thumbUrl.isNotEmpty ? Image.network(thumbUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2)) : Container(color: context.surfaces.card2),
          ),
        ),
        const SizedBox(height: 10),
        Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 2),
        Text([if (views != null) context.tr('sv_views').replaceAll('%1', fmtCount(views)), if (ago.isNotEmpty) ago].join('  ·  '), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
        _card(
          child: Column(children: [
            Align(alignment: Alignment.centerLeft, child: Text(context.tr('so_overall'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            const SizedBox(height: 12),
            if (overall != null) ...[
              _gauge(overall),
              const SizedBox(height: 14),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(context.tr(_unlocked ? 'so_analyze_hint' : 'vso_upgrade_notice'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, height: 1.4)),
              ),
            Row(children: [
              _scoreTile('so_sub_thumb', _thumb?.overall),
              _scoreTile('so_sub_title', sc('titleScore')),
              _scoreTile('so_sub_desc', sc('descScore')),
              _scoreTile('so_sub_tags', sc('tagScore')),
            ]),
            const SizedBox(height: 8),
            Text(context.tr('so_score_note'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
            const SizedBox(height: 12),
            if (overall == null || !_unlocked)
              GradientButton(label: context.tr(_unlocked ? 'so_analyze_btn' : 'vso_upgrade_btn'), icon: Icons.query_stats_rounded, loading: _analyzing, onPressed: _analyze)
            else
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: _analyzing ? null : _analyze, icon: const Icon(Icons.refresh_rounded, size: 16), label: Text(context.tr('so_reanalyze_btn')))),
              ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => setState(() => _showDetail = !_showDetail),
                child: Text(context.tr(_showDetail ? 'so_hide_detail_btn' : 'so_view_detail_btn')),
              ),
            ),
          ]),
        ),
        if (_showDetail) ...[
          const SizedBox(height: 16),
          TabBar(
            controller: _tabs,
            labelColor: AppColors.purple,
            indicatorColor: AppColors.purple,
            tabs: [
              Tab(text: context.tr('so_tab_overview')),
              Tab(text: context.tr('so_tab_title')),
              Tab(text: context.tr('so_tab_desc')),
              Tab(text: context.tr('so_tab_tags')),
            ],
          ),
          const SizedBox(height: 4),
          [_overviewTab, _titleTab, _descTab, _tagsTab][_tabs.index](),
        ],
      ]),
    );
  }
}