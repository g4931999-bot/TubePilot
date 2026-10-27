import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import 'common.dart';
import 'competitor_widgets.dart' show fmtCount, timeAgo;

/// Shared by Video SEO Optimizer and Visual Analyzer (UPDATE14).
/// Channel card + All Videos / Shorts tabs + search + sort + the user's
/// REAL videos (GET /youtube/my-videos?max=100: title, thumbnail, views,
/// duration, publish date). The channel is already connected at signup, so
/// there is no "Connect YouTube" screen - only a Reconnect button that shows
/// up if Google has expired the saved connection.
class ChannelVideoList extends StatefulWidget {
  final void Function(Map<String, dynamic> video) onSelect;
  /// Optional line under each tile (e.g. a cached score).
  final String? Function(Map<String, dynamic> video)? trailingText;
  const ChannelVideoList({super.key, required this.onSelect, this.trailingText});
  @override
  State<ChannelVideoList> createState() => _ChannelVideoListState();
}

enum _Sort { newest, oldest, views }

class _ChannelVideoListState extends State<ChannelVideoList> {
  bool _loading = true;
  bool _needsReconnect = false;
  Map<String, dynamic>? _channel;
  List<Map<String, dynamic>> _videos = [];
  bool _shortsTab = false;
  _Sort _sort = _Sort.newest;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _needsReconnect = false;
    });
    try {
      final results = await Future.wait([
        ApiService.instance.getMyYoutubeVideos(max: 100),
        ApiService.instance.getYoutubeChannel().catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      final vids = ((results[0]['videos'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final ch = results[1]['channel'];
      setState(() {
        _videos = vids;
        _channel = ch is Map ? Map<String, dynamic>.from(ch) : null;
      });
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.code : null;
      final status = e is ApiException ? e.status : null;
      if (code == 'YOUTUBE_RECONNECT_REQUIRED' || status == 404) {
        setState(() => _needsReconnect = true);
      } else {
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reconnect() async {
    try {
      final res = await ApiService.instance.getYoutubeOAuthUrl();
      final url = (res['url'] ?? '').toString();
      if (url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  List<Map<String, dynamic>> get _shown {
    final q = _query.trim().toLowerCase();
    final list = _videos.where((v) {
      if ((v['isShort'] == true) != _shortsTab) return false;
      if (q.isEmpty) return true;
      return (v['title'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
    int d(Map v) => DateTime.tryParse((v['publishedAt'] ?? '').toString())?.millisecondsSinceEpoch ?? 0;
    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => d(b).compareTo(d(a)));
        break;
      case _Sort.oldest:
        list.sort((a, b) => d(a).compareTo(d(b)));
        break;
      case _Sort.views:
        list.sort((a, b) => ((b['viewCount'] as num?) ?? -1).compareTo((a['viewCount'] as num?) ?? -1));
        break;
    }
    return list;
  }

  String _dur(int s) {
    if (s <= 0) return '';
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  void _openSort() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          for (final e in {
            _Sort.newest: 'sv_sort_new',
            _Sort.oldest: 'sv_sort_old',
            _Sort.views: 'sv_sort_views',
          }.entries)
            ListTile(
              title: Text(context.tr(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: _sort == e.key ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
              onTap: () {
                setState(() => _sort = e.key);
                Navigator.pop(c);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _channelCard() {
    final ch = _channel;
    final name = (ch?['channelTitle'] ?? '').toString();
    final thumb = (ch?['thumbnail'] ?? '').toString();
    final subs = num.tryParse((ch?['subscriberCount'] ?? '').toString());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        ClipOval(
          child: SizedBox(
            width: 44,
            height: 44,
            child: thumb.isNotEmpty
                ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.purple))
                : Container(color: AppColors.purple, alignment: Alignment.center, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(
              [
                if (subs != null) context.tr('sv_subs').replaceAll('%1', fmtCount(subs)),
                context.tr('sv_videos_count').replaceAll('%1', '${_videos.length}'),
              ].join('  ·  '),
              style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
            ),
          ]),
        ),
        const Icon(Icons.verified_rounded, color: AppColors.green, size: 20),
      ]),
    );
  }

  Widget _tab(String key, bool shorts) {
    final active = _shortsTab == shorts;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _shortsTab = shorts),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.purple : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(context.tr(key), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? Colors.white : context.surfaces.textDim)),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> v) {
    final title = (v['title'] ?? '').toString();
    final views = v['viewCount'] as num?;
    final ago = timeAgo(context, v['publishedAt']?.toString());
    final dur = _dur((v['durationSeconds'] as num?)?.toInt() ?? 0);
    final extra = widget.trailingText?.call(v);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => widget.onSelect(v),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 112,
              height: 63,
              child: Stack(fit: StackFit.expand, children: [
                (v['thumbnail'] ?? '').toString().isNotEmpty
                    ? Image.network(v['thumbnail'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))
                    : Container(color: context.surfaces.card2),
                if (dur.isNotEmpty)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(4)),
                      child: Text(dur, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title.isEmpty ? context.tr('apply_to_video_untitled') : title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.25)),
              const SizedBox(height: 4),
              Text(
                [if (views != null) context.tr('sv_views').replaceAll('%1', fmtCount(views)), if (ago.isNotEmpty) ago].join('  ·  '),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
              ),
              if (extra != null && extra.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(extra, style: const TextStyle(color: AppColors.purple, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ],
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.surfaces.textDim),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingView();
    if (_needsReconnect) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.link_off_rounded, size: 44, color: AppColors.purple),
          const SizedBox(height: 14),
          Text(context.tr('sv_reconnect_msg'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4)),
          const SizedBox(height: 18),
          GradientButton(label: context.tr('sv_reconnect_btn'), icon: Icons.refresh_rounded, onPressed: _reconnect),
          TextButton(onPressed: _load, child: Text(context.tr('sv_retry'))),
        ]),
      );
    }
    final list = _shown;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(children: [
          _channelCard(),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [_tab('sv_tab_all', false), _tab('sv_tab_shorts', true)]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (t) => setState(() => _query = t),
                decoration: InputDecoration(
                  hintText: context.tr('sv_search_hint'),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(onPressed: _openSort, tooltip: context.tr('sv_filter'), icon: const Icon(Icons.tune_rounded, color: AppColors.purple)),
          ]),
          if (_shortsTab)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(alignment: Alignment.centerLeft, child: Text(context.tr('sv_shorts_hint'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11))),
            ),
        ]),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 60),
                  EmptyView(message: context.tr(_videos.isEmpty ? 'sv_no_videos' : 'sv_no_match'), icon: Icons.video_library_outlined),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: context.surfaces.border),
                  itemBuilder: (_, i) => _tile(list[i]),
                ),
        ),
      ),
    ]);
  }
}