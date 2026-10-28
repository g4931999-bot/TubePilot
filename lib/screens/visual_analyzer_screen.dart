import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/app_brand_background.dart';
import '../widgets/competitor_widgets.dart' show fmtCount, timeAgo;
import 'thumbnail_analysis_screen.dart';

/// Visual Analyzer - step 1: pick one of your channel videos (UPDATE20).
/// Self-contained list: All Videos / Shorts tabs + the user's REAL videos
/// (GET /youtube/my-videos). No search bar and no filter button.
/// Video list -> Thumbnail Analysis -> Improvement + ChatGPT prompt ->
/// Upload improved thumbnail -> Preview & Apply -> Success.
class VisualAnalyzerScreen extends StatefulWidget {
  const VisualAnalyzerScreen({super.key});

  @override
  State<VisualAnalyzerScreen> createState() => _VisualAnalyzerScreenState();
}

class _VisualAnalyzerScreenState extends State<VisualAnalyzerScreen> {
  bool _loading = true;
  bool _needsReconnect = false;
  List<Map<String, dynamic>> _videos = [];
  bool _shortsTab = false;

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
      final res = await ApiService.instance.getMyYoutubeVideos(max: 100);
      if (!mounted) return;
      setState(() {
        _videos = ((res['videos'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
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

  // Newest first, filtered by the All / Shorts tab.
  List<Map<String, dynamic>> get _shown {
    DateTime d(Map<String, dynamic> v) => DateTime.tryParse((v['publishedAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final list = _videos.where((v) => (v['isShort'] == true) == _shortsTab).toList();
    list.sort((a, b) => d(b).compareTo(d(a)));
    return list;
  }

  Widget _tab(String key, bool shorts, IconData icon) {
    final active = _shortsTab == shorts;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _shortsTab = shorts),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: active ? AppColors.purple : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: active ? Colors.white : context.surfaces.textDim),
            const SizedBox(width: 6),
            Text(context.tr(key), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? Colors.white : context.surfaces.textDim)),
          ]),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> v) {
    final title = (v['title'] ?? '').toString();
    final views = v['viewCount'] as num?;
    final ago = timeAgo(context, v['publishedAt']?.toString());
    final thumb = (v['thumbnail'] ?? '').toString();
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThumbnailAnalysisScreen(video: v))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 112,
              height: 63,
              child: thumb.isNotEmpty
                  ? Image.network(thumb, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2))
                  : Container(color: context.surfaces.card2),
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
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.purple),
        ]),
      ),
    );
  }

  Widget _body() {
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            _tab('sv_tab_all', false, Icons.image_rounded),
            _tab('sv_tab_shorts', true, Icons.play_circle_outline_rounded),
          ]),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: list.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 60),
                  EmptyView(message: context.tr('sv_no_videos'), icon: Icons.video_library_outlined),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _tile(list[i]),
                ),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    // Festival background wrapper — shows the shared festival image when
    // festival mode is on, and draws nothing extra when it is off.
    return AppBrandBackground(
      watermarkWhenNormal: false,
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('visual_analyzer_title'))),
      body: _body(),
    );
  }
}