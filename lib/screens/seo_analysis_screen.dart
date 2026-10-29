import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/thumb_metrics.dart';
import 'diamond_store_screen.dart';
import 'seo_complete_screen.dart';

/// tr() with an English fallback, so a missing language key never shows a raw key.
String seoTx(BuildContext c, String key, String fallback) {
  final v = c.tr(key);
  return (v.isEmpty || v == key) ? fallback : v;
}

const Color _kAmber = Color(0xFFF5A623);

Color seoBandColor(int? s) => s == null ? Colors.grey : (s > 70 ? AppColors.green : (s >= 50 ? _kAmber : AppColors.red));

String seoBandLabel(BuildContext c, int? s) =>
    s == null ? '—' : c.tr(s > 70 ? 'seo_band_strong' : (s >= 50 ? 'seo_band_needs_work' : 'seo_band_weak'));

// ─────────────────────────────────────────────────────────────────────────────
// QUICK SCORE (free users)
// Rule-based score calculated on the phone from the video's real title,
// description and tags. No AI call, no diamonds, no server cost - so every free
// user can see a REAL score. Paid users get the AI score instead.
// ─────────────────────────────────────────────────────────────────────────────
class SeoQuick {
  final int title;
  final int desc;
  final int tags;
  final int overall;
  const SeoQuick(this.title, this.desc, this.tags, this.overall);
}

SeoQuick seoLocalScores({required String title, required String desc, required List<String> tags}) {
  Set<String> words(String s) => s
      .toLowerCase()
      .split(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true))
      .where((w) => w.runes.length > 2)
      .toSet();

  final t = title.trim();
  final d = desc.trim();
  final tw = words(t);
  final tagWords = tags.expand((x) => words(x)).toSet();
  final dHead = words(String.fromCharCodes(d.runes.take(150)));

  // Title: length 40, number 15, keyword match 25, structure (| : - ? ! ( ) ) 20
  var ts = 0;
  final tl = t.runes.length;
  if (tl >= 40 && tl <= 70) {
    ts += 40;
  } else if ((tl >= 25 && tl < 40) || (tl > 70 && tl <= 90)) {
    ts += 25;
  } else if (tl > 0) {
    ts += 10;
  }
  if (RegExp(r'\d').hasMatch(t)) ts += 15;
  final kwPool = tagWords.isNotEmpty ? tagWords : dHead;
  if (tw.any(kwPool.contains)) ts += 25;
  if (RegExp(r'[|:\-–?!()]').hasMatch(t)) ts += 20;

  // Description: length 40, link 15, 1-3 hashtags 15, keyword in first lines 15, 3+ lines 15
  var ds = 0;
  final dl = d.runes.length;
  if (dl >= 500) {
    ds += 40;
  } else if (dl >= 200) {
    ds += 28;
  } else if (dl >= 50) {
    ds += 15;
  } else if (dl > 0) {
    ds += 5;
  }
  if (RegExp(r'https?://').hasMatch(d)) ds += 15;
  final hc = RegExp(r'#\w+').allMatches(d).length;
  if (hc >= 1 && hc <= 3) {
    ds += 15;
  } else if (hc > 3) {
    ds += 5;
  }
  if (tw.any(dHead.contains)) ds += 15;
  if (d.split('\n').where((l) => l.trim().isNotEmpty).length >= 3) ds += 15;

  // Tags: count 50, within 500 chars 15, relevance to title 35
  var gs = 0;
  final n = tags.length;
  if (n >= 8) {
    gs += 50;
  } else if (n >= 5) {
    gs += 35;
  } else if (n >= 1) {
    gs += 15;
  }
  if (n > 0 && tags.join(',').length <= 500) gs += 15;
  final shared = tw.where(tagWords.contains).length;
  if (shared >= 2) {
    gs += 35;
  } else if (shared == 1) {
    gs += 20;
  }

  ts = ts.clamp(0, 100);
  ds = ds.clamp(0, 100);
  gs = gs.clamp(0, 100);
  final overall = (ts * 0.4 + ds * 0.3 + gs * 0.3).round().clamp(0, 100);
  return SeoQuick(ts, ds, gs, overall);
}

class SeoScoreRing extends StatelessWidget {
  final int? score;
  final double size;
  final double stroke;
  final bool showMax;
  const SeoScoreRing({super.key, required this.score, this.size = 56, this.stroke = 5, this.showMax = false});

  @override
  Widget build(BuildContext context) {
    final c = seoBandColor(score);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(value: (score ?? 0) / 100, strokeWidth: stroke, backgroundColor: context.surfaces.border, valueColor: AlwaysStoppedAnimation(c)),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(score == null ? '—' : '$score', style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w900, color: c, height: 1.1)),
          if (showMax) Text('/100', style: TextStyle(fontSize: size * 0.13, color: context.surfaces.textDim, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

class SeoBandChip extends StatelessWidget {
  final int? score;
  const SeoBandChip({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final c = seoBandColor(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(seoBandLabel(context, score), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 11.5)),
    );
  }
}

/// Blurred, non-interactive preview with a lock badge on top.
/// SECURITY RULE: the child must only ever hold PLACEHOLDER content (or data
/// the user already has locally). Real paid data is never sent to the app for
/// users who have not bought the pack, so there is nothing to un-blur.
class SeoLocked extends StatelessWidget {
  final Widget child;
  final String label;
  final VoidCallback? onTap;
  final double radius;
  const SeoLocked({super.key, required this.child, this.label = '', this.onTap, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(alignment: Alignment.center, children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.decal),
            child: IgnorePointer(child: child),
          ),
          Positioned.fill(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.35))),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: EdgeInsets.symmetric(horizontal: label.isEmpty ? 7 : 12, vertical: 7),
            decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_rounded, size: 14, color: Colors.white),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11.5))),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Chk {
  final bool ok;
  final String key;
  final String? arg;
  const _Chk(this.ok, this.key, [this.arg]);
}

/// Video SEO Optimizer - step 3: Detailed Analysis
/// (Overview / Title / Description / Tags) + AI suggestions + Apply.
///
/// Plan levels (diamond.js / ai.js):
///  * none    -> FREE HOOK: real quick scores (thumbnail + title + description +
///               tags, calculated on the phone) and the first 1-2 suggestions of
///               every section are visible. Everything after that is blurred.
///  * basic   -> AI scores, issues, title/description suggestions. Recommended
///               tags + notes + competitor gap stay blurred (need Rs.100+ pack).
///  * advance -> everything.
/// Suggestion cost (routes/ai.js): title 3 diamonds, description 3 diamonds.
/// Suggestions are cached per video, so re-opening never charges again.
class SeoAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic> video;
  final Map<String, dynamic>? result; // null for free users (no AI analysis)
  final String level; // 'none' | 'basic' | 'advance'
  final ThumbMetrics? thumb;
  final int initialTab;
  final VoidCallback? onApplied;
  const SeoAnalysisScreen({super.key, required this.video, this.result, this.level = 'none', this.thumb, this.initialTab = 0, this.onApplied});

  static final Map<String, List<String>> titleCache = {};
  static final Map<String, List<String>> descCache = {};

  @override
  State<SeoAnalysisScreen> createState() => _SeoAnalysisScreenState();
}

class _SeoAnalysisScreenState extends State<SeoAnalysisScreen> {
  int _tab = 0;
  bool _genTitles = false;
  bool _genDescs = false;
  bool _showAllTitles = false;
  List<String> _titles = [];
  List<String> _descs = [];
  String? _pickedTitle;
  String? _pickedDesc;
  bool _pickedTags = false;

  bool get _free => widget.level == 'none';
  bool get _adv => widget.level == 'advance';
  Map<String, dynamic> get _res => widget.result ?? const <String, dynamic>{};

  String get _vid => (widget.video['videoId'] ?? '').toString();
  String get _title => (widget.video['title'] ?? '').toString();
  String get _desc => (widget.video['description'] ?? '').toString();
  List<String> get _tags => ((widget.video['tags'] as List?) ?? []).map((e) => e.toString()).toList();
  List<String> get _recTags => ((_res['recommendedTags'] as List?) ?? []).map((e) => e.toString()).toList();
  bool get _hasPick => _pickedTitle != null || _pickedDesc != null || _pickedTags;

  late final SeoQuick _q = seoLocalScores(title: _title, desc: _desc, tags: _tags);

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 3);
    _titles = List<String>.of(SeoAnalysisScreen.titleCache[_vid] ?? const []);
    _descs = List<String>.of(SeoAnalysisScreen.descCache[_vid] ?? const []);
  }

  // After the store: if the user really bought a pack, go back to the score
  // screen (it reloads the plan) so they can run the AI analysis.
  Future<void> _goUpgrade() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
    try {
      final dash = await ApiService.instance.dashboard();
      final level = (dash['data']?['seoScoreLevel'] ?? 'none').toString();
      if (mounted && level != widget.level && level != 'none') Navigator.of(context).pop();
    } catch (_) {}
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
    if (_free) { _goUpgrade(); return; }
    if (_genTitles) return;
    setState(() => _genTitles = true);
    try {
      final res = await ApiService.instance.aiTitleOptions(_topic(), count: 5);
      final list = _asStrings(res['titles'], ['title', 'text']);
      SeoAnalysisScreen.titleCache[_vid] = list;
      if (mounted) {
        setState(() {
          _titles = list;
          _pickedTitle = null;
          _showAllTitles = false;
        });
      }
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _genTitles = false);
    }
  }

  Future<void> _generateDescs() async {
    if (_free) { _goUpgrade(); return; }
    if (_genDescs) return;
    setState(() => _genDescs = true);
    try {
      final res = await ApiService.instance.aiDescriptionOptions(_topic(), count: 3);
      final list = _asStrings(res['descriptions'], ['description', 'text']);
      SeoAnalysisScreen.descCache[_vid] = list;
      if (mounted) {
        setState(() {
          _descs = list;
          _pickedDesc = null;
        });
      }
    } catch (e) {
      if (mounted) showAiError(context, e);
    } finally {
      if (mounted) setState(() => _genDescs = false);
    }
  }

  void _improveWithAi() {
    if (_free) { _goUpgrade(); return; }
    setState(() => _tab = 1);
    if (_titles.isEmpty) _generateTitles();
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, context.tr('rd_copied'), isSuccess: true);
  }

  void _apply() {
    final tags = _pickedTags ? {..._tags, ..._recTags}.toList() : null;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeoCompleteScreen(
        video: widget.video,
        newTitle: _pickedTitle,
        newDescription: _pickedDesc,
        newTags: tags,
        thumbScore: widget.thumb?.overall,
        onApplied: () {
          SeoAnalysisScreen.titleCache.remove(_vid);
          SeoAnalysisScreen.descCache.remove(_vid);
          widget.onApplied?.call();
        },
      ),
    ));
  }

  // ───────────── placeholders (sample content only - never real paid data) ─────────────

  static const _phTitle = 'Top 10 Best Hidden Gems You Must Know in 2026 | Complete Guide';
  static const _phDesc =
      'In this video we cover everything you need to know, step by step. Watch till the end for the best tip.\n\n🔔 Subscribe for more\n#viral #trending #shorts';
  static const _phTags = ['trending video', 'best tips 2026', 'how to guide', 'must watch', 'viral shorts', 'explained'];

  // ───────────── UI pieces ─────────────

  Widget _card({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        width: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _lockedBlock({required Widget child, required String label, EdgeInsets? margin}) => Container(
        margin: margin ?? const EdgeInsets.only(top: 14),
        child: SeoLocked(
          label: label,
          onTap: _goUpgrade,
          child: Container(
            padding: const EdgeInsets.all(14),
            width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: child,
          ),
        ),
      );

  String get _lockFree => seoTx(context, 'so_lock_free', 'Unlock with any pack');
  String get _lockAdv => seoTx(context, 'so_lock_adv', 'Unlock with ₹100+ pack');

  Widget _label(String key) => Text(context.tr(key), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700));

  Widget _checkRow(_Chk c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(c.ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 17, color: c.ok ? AppColors.green : _kAmber),
          const SizedBox(width: 8),
          Expanded(child: Text(c.arg == null ? context.tr(c.key) : context.tr(c.key).replaceAll('%1', c.arg!), style: const TextStyle(fontSize: 13, height: 1.35))),
        ]),
      );

  Widget _check(bool ok, String key, {String? arg}) => _checkRow(_Chk(ok, key, arg));

  /// Paid: all checks. Free: only [freeVisible] real checks (problems first), the rest blurred.
  List<Widget> _checkList(List<_Chk> all, int freeVisible) {
    if (!_free) return all.map(_checkRow).toList();
    final sorted = [...all.where((c) => !c.ok), ...all.where((c) => c.ok)];
    final shown = sorted.take(freeVisible).toList();
    final hidden = sorted.skip(freeVisible).toList();
    return [
      ...shown.map(_checkRow),
      if (hidden.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SeoLocked(
            radius: 10,
            label: _lockFree,
            onTap: _goUpgrade,
            child: Column(children: hidden.map(_checkRow).toList()),
          ),
        ),
    ];
  }

  /// Thumbnail suggestions: free users see the first 2, the rest is blurred.
  List<Widget> _thumbSugRows(List<String> keys) {
    if (keys.isEmpty) return [_check(true, 'tm_sug_none')];
    if (!_free) return keys.map((k) => _check(false, k)).toList();
    final shown = keys.take(2).toList();
    final hidden = keys.skip(2).toList();
    return [
      ...shown.map((k) => _check(false, k)),
      if (hidden.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: SeoLocked(
            radius: 10,
            label: _lockFree,
            onTap: _goUpgrade,
            child: Column(children: hidden.map((k) => _check(false, k)).toList()),
          ),
        ),
    ];
  }

  Widget _selectedMark() => Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 17),
        const SizedBox(width: 4),
        Text(context.tr('so_selected'), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]);

  Widget _copyUseRow({required String text, required bool picked, required VoidCallback onUse}) => Row(children: [
        TextButton.icon(onPressed: () => _copy(text), icon: const Icon(Icons.copy_rounded, size: 15), label: Text(context.tr('rd_copy'))),
        const Spacer(),
        picked ? _selectedMark() : OutlinedButton(onPressed: onUse, child: Text(context.tr('so_use_this'))),
      ]);

  Widget _issuesCard(List<String> issues) {
    if (issues.isEmpty) return const SizedBox.shrink();
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.tr('vso_issues_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 10),
        for (final i in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: _kAmber),
              const SizedBox(width: 8),
              Expanded(child: Text(i, style: const TextStyle(fontSize: 13, height: 1.4))),
            ]),
          ),
      ]),
    );
  }

  List<String> _areaIssues(String area) => ((((_res['issuesByArea'] as Map?)?[area]) as List?) ?? []).map((e) => e.toString()).toList();

  Widget _upgradeBanner() {
    if (_adv) return const SizedBox.shrink();
    final isFree = _free;
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
                isFree ? seoTx(context, 'so_up_free_t', 'Unlock your full SEO report') : seoTx(context, 'so_up_basic_t', 'Go deeper with the ₹100+ pack'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 3),
              Text(
                isFree
                    ? seoTx(context, 'so_up_free_d', 'Buy any diamond pack for the AI score, every issue and AI title & description suggestions.')
                    : seoTx(context, 'so_up_basic_d', 'Get recommended tags, expert notes and competitor gap insights.'),
                style: TextStyle(fontSize: 12, height: 1.4, color: context.surfaces.textDim),
              ),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
        ]),
      ),
    );
  }

  Widget _pills() {
    final keys = ['so_tab_overview', 'so_tab_title', 'so_tab_desc', 'so_tab_tags'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        for (var i = 0; i < keys.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _tab == i ? AppColors.purple : Colors.transparent, borderRadius: BorderRadius.circular(11)),
                child: Text(
                  context.tr(keys[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : context.surfaces.textDim),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _miniHeader(int? overall) {
    final url = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();
    final label = _free ? seoTx(context, 'so_quick_score', 'Quick score') : seoTx(context, 'so_current_score', 'Current Score');
    return _card(
      margin: const EdgeInsets.only(top: 12),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 88,
            height: 50,
            child: url.isNotEmpty ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2)) : Container(color: context.surfaces.card2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, height: 1.25)),
            const SizedBox(height: 4),
            Text('$label  ${overall ?? '—'}/100', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: seoBandColor(overall))),
          ]),
        ),
      ]),
    );
  }

  Widget _analysisCard({required String heading, required int? score, String? imageUrl, VoidCallback? onTap}) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(heading, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
      const SizedBox(height: 10),
      Row(children: [
        if (imageUrl != null && imageUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(width: 96, height: 54, child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))),
          ),
          const SizedBox(width: 12),
        ],
        SeoScoreRing(score: score, size: 54, stroke: 5),
        const SizedBox(width: 10),
        SeoBandChip(score: score),
        const Spacer(),
        if (onTap != null) Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
      ]),
    ]);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: _card(child: body),
    );
  }

  // ───────────── tabs ─────────────

  Widget _overviewTab() {
    final bd = _res['breakdown'] as Map?;
    int? sc(String k) {
      if (_free) return k == 'titleScore' ? _q.title : (k == 'descScore' ? _q.desc : _q.tags);
      return (bd?[k] as num?)?.toInt();
    }

    final issues = ((_res['issues'] as List?) ?? []).map((e) => e.toString()).toList();
    final notes = (_res['notes'] ?? '').toString();
    final gap = (_res['competitorGapNotes'] ?? '').toString();
    final sugKeys = widget.thumb?.suggestionKeys() ?? [];
    final thumbUrl = (widget.video['thumbnailHigh'] ?? widget.video['thumbnail'] ?? '').toString();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Thumbnail: score + suggestions measured on the phone. Free users see the first 2 suggestions.
      _analysisCard(heading: context.tr('so_thumb_title'), score: widget.thumb?.overall, imageUrl: thumbUrl),
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(seoTx(context, 'so_thumb_sugs', 'Thumbnail suggestions'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          if (widget.thumb == null)
            Text(context.tr('so_thumb_measuring'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))
          else
            ..._thumbSugRows(sugKeys),
          const SizedBox(height: 4),
          Text(context.tr('so_thumb_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
        ]),
      ),
      _analysisCard(heading: seoTx(context, 'so_title_analysis', 'Title Analysis'), score: sc('titleScore'), onTap: () => setState(() => _tab = 1)),
      _analysisCard(heading: seoTx(context, 'so_desc_analysis', 'Description Analysis'), score: sc('descScore'), onTap: () => setState(() => _tab = 2)),
      _analysisCard(heading: seoTx(context, 'so_tags_analysis', 'Tags Analysis'), score: sc('tagScore'), onTap: () => setState(() => _tab = 3)),
      if (_free)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            seoTx(context, 'so_quick_note', 'Quick scores are calculated on your phone from your title, description and tags. Packs unlock the AI score and exact fixes.'),
            style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.4),
          ),
        ),
      if (!_free) _issuesCard(issues),
      if (_adv && notes.isNotEmpty) _card(child: Text(notes, style: TextStyle(fontSize: 13, color: context.surfaces.textDim, height: 1.4))),
      if (_adv && gap.isNotEmpty)
        _card(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(seoTx(context, 'so_gap_title', 'What top videos do better'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            Text(gap, style: TextStyle(fontSize: 13, color: context.surfaces.textDim, height: 1.4)),
          ]),
        ),
      if (widget.level == 'basic')
        _lockedBlock(
          label: _lockAdv,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(seoTx(context, 'so_gap_title', 'What top videos do better'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            const Text('Top videos in this niche open with a stronger hook in the first 3 seconds and use a tighter, keyword-first title.', style: TextStyle(fontSize: 13, height: 1.4)),
          ]),
        ),
      _upgradeBanner(),
      if (!_free)
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _improveWithAi,
          child: _card(
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.auto_awesome_rounded, color: AppColors.purple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(seoTx(context, 'so_ai_suggestions', 'AI Suggestions'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(
                    seoTx(context, 'so_ai_cost_note', 'Better title and description ideas by AI (3 diamonds each).'),
                    style: TextStyle(fontSize: 12, height: 1.4, color: context.surfaces.textDim),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
            ]),
          ),
        ),
    ]);
  }

  Widget _titleTab() {
    final len = _title.runes.length;
    final hasNum = RegExp(r'\d').hasMatch(_title);
    final words = _tags.expand((t) => t.toLowerCase().split(RegExp(r'\s+'))).where((w) => w.length > 2).toSet();
    final lower = _title.toLowerCase();
    final hasKw = words.any(lower.contains);
    final others = _titles.length > 1 ? _titles.skip(1).toList() : <String>[];
    final visible = _showAllTitles ? others : others.take(2).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _label('so_current_title'),
          const SizedBox(height: 6),
          Text(_title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
          const SizedBox(height: 12),
          ..._checkList([
            _Chk(len <= 70, 'so_chk_title_len', '$len'),
            _Chk(hasNum, 'so_chk_title_num'),
            _Chk(hasKw, 'so_chk_title_kw'),
          ], 2),
        ]),
      ),
      if (!_free) _issuesCard(_areaIssues('title')),
      const SizedBox(height: 14),
      if (_free) ...[
        _lockedBlock(
          label: _lockFree,
          margin: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.purple, size: 18),
              const SizedBox(width: 6),
              Text(context.tr('so_suggested_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
            const SizedBox(height: 8),
            const Text(_phTitle, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
            const SizedBox(height: 10),
            _check(true, 'so_chk_title_len', arg: '58'),
            _check(true, 'so_chk_title_num'),
          ]),
        ),
        _upgradeBanner(),
      ] else ...[
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
                Expanded(child: Text(context.tr('so_suggested_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(seoTx(context, 'so_recommended', 'Recommended'), style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700, fontSize: 11)),
                ),
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
          if (others.isNotEmpty) ...[
            const SizedBox(height: 16),
            _label('so_more_titles'),
            for (final t in visible)
              _card(
                margin: const EdgeInsets.only(top: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.3)),
                  _copyUseRow(text: t, picked: _pickedTitle == t, onUse: () => setState(() => _pickedTitle = t)),
                ]),
              ),
            if (others.length > 2)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _showAllTitles = !_showAllTitles),
                  child: Text(_showAllTitles ? seoTx(context, 'so_show_less', 'Show Less') : seoTx(context, 'so_show_more', 'Show More')),
                ),
              ),
          ],
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
          ..._checkList([
            _Chk(len >= 200, 'so_chk_desc_len', '$len'),
            _Chk(hasLink, 'so_chk_desc_link'),
            _Chk(hashtags >= 1 && hashtags <= 3, 'so_chk_desc_tags', '$hashtags'),
          ], 2),
        ]),
      ),
      if (!_free) _issuesCard(_areaIssues('description')),
      const SizedBox(height: 14),
      if (_free) ...[
        _lockedBlock(
          label: _lockFree,
          margin: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.star_rounded, color: AppColors.purple, size: 18),
              const SizedBox(width: 6),
              Text(seoTx(context, 'so_suggested_desc', 'Suggested Description'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
            const SizedBox(height: 8),
            const Text(_phDesc, style: TextStyle(fontSize: 13, height: 1.4)),
          ]),
        ),
        _upgradeBanner(),
      ] else ...[
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
      ],
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
          ..._checkList([
            _Chk(_tags.length >= 5, 'so_chk_tags_count', '${_tags.length}'),
            _Chk(used <= 500, 'so_chk_tags_chars', '$used'),
          ], 1),
        ]),
      ),
      if (!_free) _issuesCard(_areaIssues('tags')),
      if (_adv && rec.isNotEmpty)
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
              child: _pickedTags ? _selectedMark() : OutlinedButton(onPressed: () => setState(() => _pickedTags = true), child: Text(context.tr('so_add_tags_btn'))),
            ),
          ]),
        )
      else if (!_adv)
        // free + basic: recommended tags are an Rs.100+ feature (server returns none for basic)
        _lockedBlock(
          label: _free ? _lockFree : _lockAdv,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('seo_recommended_tags'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _phTags.map((t) => Chip(label: Text(t), visualDensity: VisualDensity.compact)).toList()),
          ]),
        ),
      if (!_adv) _upgradeBanner(),
    ]);
  }

  Widget _bottomButton() {
    if (_free) {
      return GradientButton(label: seoTx(context, 'so_unlock_btn', 'Unlock Full Analysis'), icon: Icons.lock_open_rounded, onPressed: _goUpgrade);
    }
    if (!_hasPick && _tab == 0) {
      return GradientButton(label: context.tr('so_improve_ai_btn'), icon: Icons.auto_awesome_rounded, loading: _genTitles, onPressed: _improveWithAi);
    }
    return GradientButton(
      label: context.tr('apply_to_video_btn_label'),
      icon: Icons.send_rounded,
      onPressed: _hasPick ? _apply : () => showToast(context, context.tr('so_pick_first'), isError: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final overall = _free ? _q.overall : (_res['seoScore'] as num?)?.toInt();
    final Widget body;
    switch (_tab) {
      case 1:
        body = _titleTab();
        break;
      case 2:
        body = _descTab();
        break;
      case 3:
        body = _tagsTab();
        break;
      default:
        body = _overviewTab();
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(height: 54, width: double.infinity, child: _bottomButton()),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        _pills(),
        _miniHeader(overall),
        body,
      ]),
    );
  }
}