import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/competitor_limit_sheet.dart';
import '../widgets/competitor_widgets.dart';
import 'competitor_detail_screen.dart';
import 'competitor_videos_screen.dart';

/// Competitor Radar — dashboard.
/// Data comes from GET /analytics/competitors/dashboard. Plan limits
/// (Free 2 / Basic 5 / Advanced 15) are enforced by the backend; this screen
/// only shows the upgrade prompt when the backend says the limit is reached.
class CompetitorRadarScreen extends StatefulWidget {
  const CompetitorRadarScreen({super.key});
  @override
  State<CompetitorRadarScreen> createState() => _CompetitorRadarScreenState();
}

class _CompetitorRadarScreenState extends State<CompetitorRadarScreen> {
  final _inputCtrl = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _adding = false;
  Map<String, dynamic>? _data;

  // Per-competitor filter (so videos of different competitors are not mixed)
  String? _filterId;
  bool _filterLoading = false;
  Map<String, List<Map<String, dynamic>>> _filtered = {};

  // Background data collection (new / old competitors) — re-check a few times.
  Timer? _pollTimer;
  int _polls = 0;

  // ---------------- Typeahead state ----------------
  Timer? _debounce;
  bool _searching = false;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _load();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // small delay so a tap on a suggestion registers before we hide the list
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showSuggestions = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------- data helpers ----------------
  Map<String, dynamic> get _meta => _data?['meta'] is Map ? Map<String, dynamic>.from(_data!['meta']) : <String, dynamic>{};
  int get _limit => (_meta['limit'] as num?)?.toInt() ?? 2;
  int get _count => (_meta['count'] as num?)?.toInt() ?? 0;
  bool get _canAdd => _meta['canAdd'] != false;
  bool get _advanced => _meta['advanced'] == true;

  List<Map<String, dynamic>> _list(String key) =>
      (_data?[key] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> get _competitors => _list('competitors');

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await ApiService.instance.getCompetitorDashboard();
      if (!mounted) return;
      setState(() => _data = res);
      _schedulePoll();
    } catch (e) {
      if (mounted && !silent) showApiError(context, e);
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    if (_data?['refreshing'] == true && _polls < 4) {
      _polls++;
      _pollTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) _load(silent: true);
      });
    }
  }

  // ---------------- Per-competitor filter ----------------
  Future<void> _selectFilter(String? id) async {
    if (id == _filterId) return;
    setState(() {
      _filterId = id;
      _filtered = {};
      _filterLoading = id != null;
    });
    if (id == null) return;
    try {
      final results = await Future.wait([
        ApiService.instance.getCompetitorVideos(competitorId: id, sort: 'most_viewed', limit: 10),
        ApiService.instance.getCompetitorVideos(competitorId: id, sort: 'recent', limit: 10),
        ApiService.instance.getCompetitorVideos(competitorId: id, sort: 'outperforming', limit: 10),
      ]);
      if (!mounted || _filterId != id) return;
      List<Map<String, dynamic>> vids(Map<String, dynamic> r) =>
          (r['videos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() => _filtered = {'top': vids(results[0]), 'recent': vids(results[1]), 'out': vids(results[2])});
    } catch (e) {
      if (mounted) {
        setState(() => _filterId = null);
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _filterLoading = false);
    }
  }

  Widget _filterChips(List<Map<String, dynamic>> competitors) {
    Widget chip({required String label, required bool selected, required VoidCallback onTap, Color? color, String thumb = ''}) {
      final c = color ?? AppColors.purple;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.fromLTRB(thumb.isNotEmpty || color != null ? 4 : 12, 5, 12, 5),
            decoration: BoxDecoration(
              color: selected ? c : c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withValues(alpha: selected ? 1 : 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (color != null) ...[
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.white,
                    backgroundImage: thumb.isNotEmpty ? NetworkImage(thumb) : null,
                    child: thumb.isEmpty ? Icon(Icons.person_rounded, size: 13, color: c) : null,
                  ),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : c, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(label: context.tr('rd_filter_all'), selected: _filterId == null, onTap: () => _selectFilter(null)),
          ...competitors.map((c) {
            final stats = c['lastStats'] is Map ? Map<String, dynamic>.from(c['lastStats']) : <String, dynamic>{};
            final key = (stats['resolvedChannelId'] ?? c['channelId'] ?? c['_id']).toString();
            final label = (c['label'] ?? c['handle'] ?? c['channelId'] ?? '').toString();
            return chip(
              label: label,
              selected: _filterId == c['_id'].toString(),
              color: channelColor(key),
              thumb: (stats['thumbnail'] ?? '').toString(),
              onTap: () => _selectFilter(c['_id'].toString()),
            );
          }),
        ],
      ),
    );
  }

  // ---------------- Typeahead search (debounced) ----------------
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    try {
      final res = await ApiService.instance.searchCompetitors(query);
      final results = (res['results'] as List? ?? []).cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _showSuggestions = true;
      });
    } catch (e) {
      if (mounted) setState(() => _showSuggestions = false);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _addFromSuggestion(Map<String, dynamic> suggestion) async {
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
      _inputCtrl.clear();
    });
    _focusNode.unfocus();
    await _addCompetitor(
      channelId: suggestion['channelId'] as String?,
      label: suggestion['title'] as String?,
    );
  }

  Future<void> _addCompetitor({String? channelId, String? handle, String? label}) async {
    final input = _inputCtrl.text.trim();
    if (channelId == null && handle == null && input.isEmpty) return;

    // The app already knows the plan is full → show the upgrade prompt right away.
    // (The backend still enforces the limit on its own.)
    if (_data != null && !_canAdd) {
      showCompetitorLimitSheet(context, limit: _limit, current: _count);
      return;
    }

    setState(() => _adding = true);
    try {
      final isHandle = handle != null || input.startsWith('@');
      await ApiService.instance.addCompetitor(
        channelId: channelId ?? (isHandle ? null : (input.isNotEmpty ? input : null)),
        handle: handle ?? (isHandle ? (input.isNotEmpty ? input : null) : null),
        label: label,
      );
      _inputCtrl.clear();
      _polls = 0;
      await _load(silent: true);
      if (mounted) showToast(context, context.tr('radar_competitor_added_toast'), isSuccess: true);
    } on ApiException catch (e) {
      if (e.code == 'COMPETITOR_LIMIT_REACHED') {
        await _load(silent: true);
        if (mounted) showCompetitorLimitSheet(context, limit: _limit, current: _count);
      } else if (mounted) {
        showApiError(context, e);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _confirmRemove(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('rd_remove_title')),
        content: Text(ctx.tr('rd_remove_body')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(ctx.tr('rd_cancel'))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('rd_remove'), style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.instance.deleteCompetitor(c['_id'].toString());
      await _load(silent: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  void _openVideos(String sort) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CompetitorVideosScreen(initialSort: sort)));
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('radar_title'))),
      body: RefreshIndicator(
        onRefresh: () {
          _polls = 0;
          return _load(silent: true);
        },
        color: AppColors.purple,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _searchRow(),
            _suggestionsList(),
            const SizedBox(height: 16),
            if (_loading && _data == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: LoadingView())
            else if (_data != null) ..._dashboard(),
          ],
        ),
      ),
    );
  }

  Widget _searchRow() {
    return Row(children: [
      Expanded(
        child: TextFormField(
          controller: _inputCtrl,
          focusNode: _focusNode,
          decoration: InputDecoration(
            hintText: context.tr('radar_search_hint'),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
          onChanged: _onSearchChanged,
          onFieldSubmitted: (_) => _addCompetitor(),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        height: 52,
        child: ElevatedButton(
          onPressed: _adding ? null : () => _addCompetitor(),
          child: _adding
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Icon(_data != null && !_canAdd ? Icons.lock_rounded : Icons.add_rounded),
        ),
      ),
    ]);
  }

  Widget _suggestionsList() {
    if (_showSuggestions && _suggestions.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          border: Border.all(color: context.surfaces.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: context.surfaces.border),
          itemBuilder: (_, i) {
            final s = _suggestions[i];
            final thumb = (s['thumbnail'] ?? '').toString();
            return ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.purple.withValues(alpha: 0.14),
                backgroundImage: thumb.isNotEmpty ? NetworkImage(thumb) : null,
                child: thumb.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.purple, size: 18) : null,
              ),
              title: Text(s['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
              subtitle: Text(s['description'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
              onTap: () => _addFromSuggestion(s),
            );
          },
        ),
      );
    }
    if (_showSuggestions && !_searching && _suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(context.tr('radar_no_channels_found'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _dashboard() {
    final competitors = _competitors;
    final summary = _data?['summary'] is Map ? Map<String, dynamic>.from(_data!['summary']) : <String, dynamic>{};
    final growth = _data?['growth'] is Map ? Map<String, dynamic>.from(_data!['growth']) : <String, dynamic>{};
    final windowDays = (_data?['windowDays'] as num?)?.toInt() ?? 90;
    final refreshing = _data?['refreshing'] == true;

    final apiKeyError = competitors.isNotEmpty &&
        competitors.every((c) => (c['lastStats']?['error'] ?? '').toString().contains('YOUTUBE_DATA_API_KEY'));

    final filtering = _filterId != null;
    final topVideos = filtering ? (_filtered['top'] ?? <Map<String, dynamic>>[]) : _list('topVideos');
    final recentVideos = filtering ? (_filtered['recent'] ?? <Map<String, dynamic>>[]) : _list('recentVideos');
    final outperforming = filtering ? (_filtered['out'] ?? <Map<String, dynamic>>[]) : _list('outperforming');

    final vphValues = competitors.map((c) => (c['lastStats']?['vph'] as num?)?.toDouble()).whereType<double>().toList();
    final avgVph = vphValues.isEmpty ? 0.0 : vphValues.reduce((a, b) => a + b) / vphValues.length;

    final widgets = <Widget>[
      _summaryBanner(summary, growth),
      if (apiKeyError)
        Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.08), border: Border.all(color: AppColors.red.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('radar_api_key_error'), style: const TextStyle(color: AppColors.red, fontSize: 12.5))),
          ]),
        ),
      if (refreshing && competitors.isNotEmpty) ...[
        const SizedBox(height: 12),
        competitorNote(context, context.tr('rd_collecting')),
      ],
      competitorSectionHeader(context, context.tr('rd_sec_competitors')),
    ];

    if (competitors.isEmpty) {
      widgets.add(EmptyView(message: context.tr('radar_empty_state'), icon: Icons.radar_rounded));
      return widgets;
    }

    widgets.addAll(competitors.map((c) => _competitorCard(c, avgVph)));

    // ---------- videos ----------
    if (competitors.length >= 2) {
      widgets.add(competitorSectionHeader(context, context.tr('rd_filter_title')));
      widgets.add(_filterChips(competitors));
    }
    if (filtering && _filterLoading) {
      widgets.add(const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator())));
      return widgets;
    }
    if (topVideos.isEmpty && recentVideos.isEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(competitorNote(context, context.tr(refreshing ? 'rd_collecting' : 'rd_no_videos')));
      return widgets;
    }

    widgets.add(competitorSectionHeader(context, context.tr('rd_sec_top_videos'), onViewAll: filtering ? null : () => _openVideos('most_viewed')));
    widgets.addAll(topVideos.map((v) => CompetitorVideoTile(video: v)));
    widgets.add(competitorNote(context, context.tr('rd_window_note').replaceAll('%1', '$windowDays')));

    if (recentVideos.isNotEmpty) {
      widgets.add(competitorSectionHeader(context, context.tr('rd_sec_recent'), onViewAll: filtering ? null : () => _openVideos('recent')));
      widgets.addAll(recentVideos.take(5).map((v) => CompetitorVideoTile(video: v)));
    }

    if (outperforming.isNotEmpty) {
      widgets.add(competitorSectionHeader(context, context.tr('rd_sec_outperforming'), onViewAll: filtering ? null : () => _openVideos('outperforming')));
      widgets.addAll(outperforming.take(3).map((v) => CompetitorVideoTile(video: v)));
    }

    // ---------- Advanced-plan sections ----------
    if (!_advanced) {
      widgets.add(const SizedBox(height: 18));
      widgets.add(CompetitorLockedCard(message: context.tr('rd_locked_features')));
    } else {
      final fastest = _list('fastestGrowing');
      widgets.add(competitorSectionHeader(context, context.tr('rd_sec_fastest'), onViewAll: () => _openVideos('fastest')));
      if (fastest.isEmpty) {
        widgets.add(competitorNote(context, context.tr('rd_growth_waiting')));
      } else {
        widgets.addAll(fastest.take(4).map((v) => CompetitorVideoTile(video: v)));
        widgets.add(competitorNote(context, context.tr('rd_growth_note')));
      }

      final topics = _list('topics');
      widgets.add(competitorSectionHeader(context, context.tr('rd_sec_topics')));
      if (topics.isEmpty) {
        widgets.add(competitorNote(context, context.tr('rd_topics_empty')));
      } else {
        for (var i = 0; i < topics.length && i < 6; i++) {
          widgets.add(CompetitorTopicTile(topic: topics[i], rank: i + 1));
        }
        widgets.add(competitorNote(context, context.tr('rd_topics_note')));
      }

      final opps = _list('opportunities');
      widgets.add(competitorSectionHeader(context, context.tr('rd_sec_opps')));
      if (opps.isEmpty) {
        widgets.add(competitorNote(context, context.tr('rd_opps_empty')));
      } else {
        for (var i = 0; i < opps.length && i < 5; i++) {
          widgets.add(CompetitorTopicTile(topic: opps[i], rank: i + 1));
        }
        widgets.add(competitorNote(context, context.tr('rd_opps_note')));
      }
    }

    widgets.add(const SizedBox(height: 24));
    return widgets;
  }

  Widget _summaryBanner(Map<String, dynamic> summary, Map<String, dynamic> growth) {
    final since = growth['firstSnapshotAt']?.toString();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _bannerStat(context.tr('rd_summary_tracked'), '$_count / $_limit')),
              Container(width: 1, height: 38, color: context.surfaces.border),
              Expanded(child: _bannerStat(context.tr('rd_summary_videos'), fmtCount(summary['videosAnalysed'] as num?))),
            ],
          ),
          if (_advanced && since != null && since.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              context.tr('rd_growth_since').replaceAll('%1', formatDate(since)),
              style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: AppColors.purple, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
      ],
    );
  }

  Widget _competitorCard(Map<String, dynamic> c, double avgVph) {
    final stats = c['lastStats'] is Map ? Map<String, dynamic>.from(c['lastStats']) : <String, dynamic>{};
    final vph = (stats['vph'] as num?)?.toDouble();
    final isTrending = vph != null && avgVph > 0 && vph > avgVph * 2;
    final thumbnail = (stats['thumbnail'] ?? '').toString();
    final label = (c['label'] ?? c['handle'] ?? c['channelId'] ?? '').toString();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CompetitorDetailScreen(id: c['_id'].toString(), label: label, thumbnail: thumbnail),
        ));
        if (mounted) _load(silent: true);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: isTrending ? AppColors.green.withValues(alpha: 0.5) : context.surfaces.border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.purple.withValues(alpha: 0.14),
                backgroundImage: thumbnail.isNotEmpty ? NetworkImage(thumbnail) : null,
                child: thumbnail.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.purple) : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text('${fmtCount(stats['subscriberCount'] as num?)} ${context.tr('radar_subscribers_suffix')}', style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(onPressed: () => _confirmRemove(c), icon: const Icon(Icons.close_rounded, size: 18)),
              Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
            ]),
            if (stats['error'] != null && !stats['error'].toString().contains('YOUTUBE_DATA_API_KEY')) ...[
              const SizedBox(height: 8),
              Text(stats['error'].toString(), style: const TextStyle(color: AppColors.red, fontSize: 11.5)),
            ] else if (vph != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.speed_rounded, size: 15, color: isTrending ? AppColors.green : context.surfaces.textDim),
                const SizedBox(width: 5),
                Text(
                  context.tr('rd_vph_avg').replaceAll('%1', vph.toStringAsFixed(1)),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: isTrending ? AppColors.green : null),
                ),
                if (isTrending) ...[
                  const SizedBox(width: 8),
                  AppBadge(label: context.tr('radar_trending_badge'), color: AppColors.green),
                ],
              ]),
            ],
          ],
        ),
      ),
    );
  }
}