import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/thumb_metrics.dart';
import '../widgets/competitor_widgets.dart' show fmtCount, timeAgo;
import 'diamond_store_screen.dart';
import 'seo_analysis_screen.dart';

/// Video SEO Optimizer - step 2: score screen.
///
/// FREE HOOK: users without a pack see REAL scores here (thumbnail + title +
/// description + tags + overall). Free scores are "quick scores" calculated on
/// the phone (no AI, no diamonds). The first 1-2 suggestions are visible in the
/// detailed analysis, everything after that is blurred -> that is what makes
/// them buy a pack.
///  * level 'none'    -> quick scores (free)
///  * level 'basic'   -> AI score (Rs.10/50 packs): POST /ai/seo-score, 1 diamond
///  * level 'advance' -> AI score + extra insights (Rs.100+ packs)
class SeoVideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  const SeoVideoDetailScreen({super.key, required this.video});

  /// videoId -> last /ai/seo-score result (session cache).
  static final Map<String, Map<String, dynamic>> cache = {};

  @override
  State<SeoVideoDetailScreen> createState() => _SeoVideoDetailScreenState();
}

class _SeoVideoDetailScreenState extends State<SeoVideoDetailScreen> {
  String _level = 'none'; // 'none' | 'basic' | 'advance'
  bool _planLoaded = false;
  bool _analyzing = false;
  Map<String, dynamic>? _result;
  ThumbMetrics? _thumb;

  bool get _unlocked => _level != 'none';

  String get _vid => (widget.video['videoId'] ?? '').toString();
  String get _title => (widget.video['title'] ?? '').toString();
  String get _desc => (widget.video['description'] ?? '').toString();
  List<String> get _tags => ((widget.video['tags'] as List?) ?? []).map((e) => e.toString()).toList();

  // Recomputed every build, so after "Apply to YouTube" the new text gives a new quick score.
  SeoQuick get _quick => seoLocalScores(title: _title, desc: _desc, tags: _tags);

  @override
  void initState() {
    super.initState();
    _result = SeoVideoDetailScreen.cache[_vid];
    _loadPlan();
    _measureThumb();
  }

  Future<void> _loadPlan() async {
    try {
      final dash = await ApiService.instance.dashboard();
      final level = (dash['data']?['seoScoreLevel'] ?? 'none').toString();
      if (mounted) setState(() => _level = level.isEmpty ? 'none' : level);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _planLoaded = true);
    }
  }

  Future<void> _measureThumb() async {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final bytes = await fetchImageBytes(url);
    if (bytes == null) return;
    final m = await measureThumbnail(bytes);
    if (mounted) setState(() => _thumb = m);
  }

  Future<void> _goUpgrade() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
    if (mounted) _loadPlan(); // pack bought -> paid features open on this screen
  }

  Future<void> _analyze() async {
    if (!_planLoaded) return;
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

  Future<void> _openDetail(int tab) async {
    if (_unlocked && _result == null) {
      showToast(context, context.tr('so_run_first'), isError: true);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeoAnalysisScreen(
        video: widget.video,
        result: _unlocked ? _result : null,
        level: _level,
        thumb: _thumb,
        initialTab: tab,
        // after "Apply to YouTube" the old analysis is outdated -> drop it
        onApplied: () => SeoVideoDetailScreen.cache.remove(_vid),
      ),
    ));
    if (mounted) {
      setState(() => _result = SeoVideoDetailScreen.cache[_vid]);
      _loadPlan();
    }
  }

  String _dur(int s) {
    if (s <= 0) return '';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  // ───────────── UI pieces ─────────────

  Widget _header() {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final dur = _dur((widget.video['durationSeconds'] as num?)?.toInt() ?? 0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          url.isNotEmpty ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2)) : Container(color: context.surfaces.card2),
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 34),
            ),
          ),
          if (dur.isNotEmpty)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(5)),
                child: Text(dur, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _overallCard(int? overall) {
    String desc;
    if (!_unlocked) {
      desc = seoTx(context, 'so_ov_free', 'Quick score from your title, description and tags. Unlock the AI score for exact fixes.');
    } else if (overall == null) {
      desc = context.tr('so_analyze_hint');
    } else if (overall > 70) {
      desc = seoTx(context, 'so_ov_good', 'Your video has good potential. Follow the suggestions to improve the score further.');
    } else if (overall >= 50) {
      desc = seoTx(context, 'so_ov_mid', 'Your video needs some work. Follow the suggestions to improve the score.');
    } else {
      desc = seoTx(context, 'so_ov_weak', 'Your video SEO is weak. Open the detailed analysis to fix title, description and tags.');
    }
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        SeoScoreRing(score: overall, size: 96, stroke: 8, showMax: true),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              _unlocked ? context.tr('so_overall') : '${context.tr('so_overall')} · ${seoTx(context, 'so_quick_score', 'Quick score')}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            if (overall != null) SeoBandChip(score: overall),
            const SizedBox(height: 6),
            Text(desc, style: TextStyle(fontSize: 12, height: 1.4, color: context.surfaces.textDim)),
          ]),
        ),
      ]),
    );
  }

  Widget _metric(String key, IconData icon, int? v, int tab) {
    final c = seoBandColor(v);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetail(tab),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 19, color: AppColors.purple),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(key), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.surfaces.textDim)),
                  const SizedBox(height: 2),
                  Text(v == null ? '—' : '$v/100', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: c)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: context.surfaces.textDim),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _upgradeCard() {
    final basic = _level == 'basic';
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: _goUpgrade,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.purple.withValues(alpha: 0.08),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          const Icon(Icons.diamond_rounded, color: AppColors.diamond, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                basic ? seoTx(context, 'so_up_basic_t', 'Go deeper with the ₹100+ pack') : seoTx(context, 'so_up_free_t', 'Unlock your full SEO report'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                basic
                    ? seoTx(context, 'so_up_basic_d', 'Get recommended tags, expert notes and competitor gap insights.')
                    : seoTx(context, 'so_up_free_d', 'Buy any diamond pack for the AI score, every issue and AI title & description suggestions.'),
                style: TextStyle(fontSize: 12, height: 1.4, color: context.surfaces.textDim),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _quick;
    final bd = _result?['breakdown'] as Map?;
    // free -> quick scores (real, on-device); paid -> AI scores (null until analysed)
    final int? overall = _unlocked ? (_result?['seoScore'] as num?)?.toInt() : q.overall;
    int? sc(String k) {
      if (!_unlocked) return k == 'titleScore' ? q.title : (k == 'descScore' ? q.desc : q.tags);
      return (bd?[k] as num?)?.toInt();
    }

    final views = widget.video['viewCount'] as num?;
    final ago = timeAgo(context, widget.video['publishedAt']?.toString());
    final canAnalyze = _unlocked && _result == null;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            height: 54,
            width: double.infinity,
            child: GradientButton(
              label: context.tr(canAnalyze ? 'so_analyze_btn' : 'so_view_detail_btn'),
              icon: canAnalyze ? Icons.query_stats_rounded : Icons.insights_rounded,
              loading: _analyzing || !_planLoaded,
              onPressed: canAnalyze ? _analyze : () => _openDetail(0),
            ),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
        _header(),
        const SizedBox(height: 12),
        Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, height: 1.25)),
        const SizedBox(height: 4),
        Text(
          [if (views != null) context.tr('sv_views').replaceAll('%1', fmtCount(views)), if (ago.isNotEmpty) ago].join('  ·  '),
          style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
        ),
        _overallCard(overall),
        const SizedBox(height: 12),
        Row(children: [
          _metric('so_sub_thumb', Icons.image_rounded, _thumb?.overall, 0),
          _metric('so_sub_title', Icons.title_rounded, sc('titleScore'), 1),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _metric('so_sub_desc', Icons.description_rounded, sc('descScore'), 2),
          _metric('so_sub_tags', Icons.sell_rounded, sc('tagScore'), 3),
        ]),
        const SizedBox(height: 10),
        Text(context.tr('so_score_note'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
        if (_unlocked && _result != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _analyzing ? null : _analyze,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(context.tr('so_reanalyze_btn')),
          ),
        ],
        if (_planLoaded && _level != 'advance') _upgradeCard(),
      ]),
    );
  }
}