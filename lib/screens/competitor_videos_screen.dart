import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/competitor_widgets.dart';

/// Video performance list: Most Viewed / Recent / Fastest Growing / Beating Average.
/// For ONE competitor (competitorId given) or all tracked competitors together.
///  • "views" = total views.
///  • "Fastest Growing" = measured growth between two real daily snapshots
///    (Advanced plan). With no measurement yet it stays empty — nothing is estimated.
class CompetitorVideosScreen extends StatefulWidget {
  final String? competitorId;
  final String? title;
  final String initialSort;
  const CompetitorVideosScreen({super.key, this.competitorId, this.title, this.initialSort = 'most_viewed'});

  @override
  State<CompetitorVideosScreen> createState() => _CompetitorVideosScreenState();
}

class _CompetitorVideosScreenState extends State<CompetitorVideosScreen> {
  static const _sorts = ['most_viewed', 'recent', 'fastest', 'outperforming'];
  static const _sortKeys = {
    'most_viewed': 'rd_tab_most_viewed',
    'recent': 'rd_tab_recent',
    'fastest': 'rd_tab_fastest',
    'outperforming': 'rd_tab_outperforming',
  };

  late String _sort;
  bool _loading = true;
  bool _locked = false;
  List<Map<String, dynamic>> _videos = [];
  bool _growthReady = false;
  int _windowDays = 90;

  @override
  void initState() {
    super.initState();
    _sort = _sorts.contains(widget.initialSort) ? widget.initialSort : 'most_viewed';
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _locked = false;
    });
    try {
      final res = await ApiService.instance.getCompetitorVideos(competitorId: widget.competitorId, sort: _sort);
      if (!mounted) return;
      final growth = res['growth'] is Map ? Map<String, dynamic>.from(res['growth']) : <String, dynamic>{};
      setState(() {
        _videos = (res['videos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _growthReady = growth['ready'] == true;
        _windowDays = (res['windowDays'] as num?)?.toInt() ?? 90;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'FEATURE_LOCKED') {
        setState(() {
          _locked = true;
          _videos = [];
        });
      } else {
        showApiError(context, e);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? context.tr('rd_videos_title'))),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              itemCount: _sorts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = _sorts[i];
                final selected = s == _sort;
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _select(s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.purple : context.surfaces.card2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: selected ? AppColors.purple : context.surfaces.border),
                    ),
                    child: Text(
                      context.tr(_sortKeys[s]!),
                      style: TextStyle(color: selected ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const LoadingView();
    if (_locked) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [CompetitorLockedCard(message: context.tr('rd_locked_features'))],
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.purple,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          if (_videos.isEmpty)
            EmptyView(
              message: context.tr(_sort == 'fastest' ? 'rd_growth_waiting' : 'rd_videos_empty'),
              icon: Icons.video_library_outlined,
            )
          else
            ..._videos.map((v) => CompetitorVideoTile(video: v, showChannel: widget.competitorId == null)),
          if (_sort == 'fastest' && _videos.isNotEmpty) competitorNote(context, context.tr('rd_growth_note')),
          if (_sort == 'fastest' && _videos.isEmpty && _growthReady) competitorNote(context, context.tr('rd_growth_note')),
          if (_sort == 'outperforming') competitorNote(context, context.tr('rd_outperform_note')),
          competitorNote(context, context.tr('rd_window_note').replaceAll('%1', '$_windowDays')),
        ],
      ),
    );
  }
}