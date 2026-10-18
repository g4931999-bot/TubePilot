import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/competitor_widgets.dart';
import 'competitor_videos_screen.dart';

/// One tracked competitor: channel info, subscribers, recent / top videos,
/// measured trends (Advanced plan) and topics. Data: GET /analytics/competitors/:id
class CompetitorDetailScreen extends StatefulWidget {
  final String id;
  final String? label;
  final String? thumbnail;
  const CompetitorDetailScreen({super.key, required this.id, this.label, this.thumbnail});

  @override
  State<CompetitorDetailScreen> createState() => _CompetitorDetailScreenState();
}

class _CompetitorDetailScreenState extends State<CompetitorDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _d;
  String _trendMetric = 'subscribers'; // or 'views'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.getCompetitorDetail(widget.id);
      if (mounted) setState(() => _d = res);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      (_d?[key] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('rd_detail_title'))),
      body: _loading && _d == null
          ? const LoadingView()
          : _d == null
              ? EmptyView(message: context.tr('rd_videos_empty'), icon: Icons.radar_rounded)
              : RefreshIndicator(onRefresh: _load, color: AppColors.purple, child: _content()),
    );
  }

  Widget _content() {
    final d = _d!;
    final ch = d['channel'] is Map ? Map<String, dynamic>.from(d['channel']) : <String, dynamic>{};
    final meta = d['meta'] is Map ? Map<String, dynamic>.from(d['meta']) : <String, dynamic>{};
    final advanced = meta['advanced'] == true;
    final growth = d['growth'] is Map ? Map<String, dynamic>.from(d['growth']) : <String, dynamic>{};
    final windowDays = (d['windowDays'] as num?)?.toInt() ?? 90;
    final refreshing = d['refreshing'] == true;

    final label = (ch['label'] ?? widget.label ?? '').toString();
    final thumb = (ch['thumbnail'] ?? widget.thumbnail ?? '').toString();
    final handle = (ch['handle'] ?? '').toString();
    final vph = (ch['vph'] as num?)?.toDouble();

    final mostViewed = _list('mostViewed');
    final recent = _list('recent');
    final outperforming = _list('outperforming');
    final fastest = _list('fastestGrowing');
    final topics = _list('topics');
    final series = _list('series');

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ---------- header ----------
        Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: AppColors.purple.withValues(alpha: 0.14),
              backgroundImage: thumb.isNotEmpty ? NetworkImage(thumb) : null,
              child: thumb.isEmpty ? const Icon(Icons.person_rounded, color: AppColors.purple, size: 28) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  if (handle.isNotEmpty) Text(handle, style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (ch['url'] != null)
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(ch['url'].toString()), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(context.tr('rd_open_youtube')),
          ),
        if (ch['error'] != null && !ch['error'].toString().contains('YOUTUBE_DATA_API_KEY')) ...[
          const SizedBox(height: 8),
          Text(ch['error'].toString(), style: const TextStyle(color: AppColors.red, fontSize: 11.5)),
        ],
        const SizedBox(height: 16),

        // ---------- stats ----------
        Row(
          children: [
            Expanded(child: StatCard(label: context.tr('rd_stat_subs'), value: fmtCount(ch['subscriberCount'] as num?))),
            const SizedBox(width: 10),
            Expanded(child: StatCard(label: context.tr('rd_stat_views'), value: fmtCount(ch['viewCount'] as num?))),
            const SizedBox(width: 10),
            Expanded(child: StatCard(label: context.tr('rd_stat_videos'), value: fmtCount(ch['videoCount'] as num?))),
          ],
        ),
        if (advanced && vph != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.speed_rounded, size: 15, color: context.surfaces.textDim),
            const SizedBox(width: 6),
            Text(context.tr('rd_vph_avg').replaceAll('%1', vph.toStringAsFixed(1)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ],
        if (refreshing) ...[
          const SizedBox(height: 10),
          competitorNote(context, context.tr('rd_collecting')),
        ],

        // ---------- trend (Advanced) ----------
        competitorSectionHeader(context, context.tr('rd_sec_trend')),
        if (!advanced)
          CompetitorLockedCard(message: context.tr('rd_locked_features'))
        else
          _trendCard(series),

        // ---------- videos ----------
        if (mostViewed.isEmpty && recent.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 18), child: competitorNote(context, context.tr(refreshing ? 'rd_collecting' : 'rd_no_videos')))
        else ...[
          competitorSectionHeader(context, context.tr('rd_sec_most_viewed'), onViewAll: () => _openVideos('most_viewed', label)),
          ...mostViewed.map((v) => CompetitorVideoTile(video: v, showChannel: false)),
          competitorSectionHeader(context, context.tr('rd_sec_recent'), onViewAll: () => _openVideos('recent', label)),
          ...recent.take(5).map((v) => CompetitorVideoTile(video: v, showChannel: false)),
          if (outperforming.isNotEmpty) ...[
            competitorSectionHeader(context, context.tr('rd_sec_outperforming'), onViewAll: () => _openVideos('outperforming', label)),
            ...outperforming.take(3).map((v) => CompetitorVideoTile(video: v, showChannel: false)),
            competitorNote(context, context.tr('rd_outperform_note')),
          ],
          competitorNote(context, context.tr('rd_window_note').replaceAll('%1', '$windowDays')),
        ],

        // ---------- Advanced sections ----------
        if (advanced) ...[
          competitorSectionHeader(context, context.tr('rd_sec_fastest'), onViewAll: () => _openVideos('fastest', label)),
          if (fastest.isEmpty)
            competitorNote(context, context.tr('rd_growth_waiting'))
          else ...[
            ...fastest.map((v) => CompetitorVideoTile(video: v, showChannel: false)),
            competitorNote(context, context.tr('rd_growth_note')),
          ],
          competitorSectionHeader(context, context.tr('rd_sec_topics')),
          if (topics.isEmpty)
            competitorNote(context, context.tr('rd_topics_empty'))
          else ...[
            for (var i = 0; i < topics.length && i < 6; i++) CompetitorTopicTile(topic: topics[i], rank: i + 1),
            competitorNote(context, context.tr('rd_topics_note')),
          ],
        ] else ...[
          const SizedBox(height: 18),
          CompetitorLockedCard(message: context.tr('rd_locked_features')),
        ],
        const SizedBox(height: 24),
        // `growth` is only used to decide whether the empty-state wording applies.
        if (growth['ready'] == false && advanced && fastest.isEmpty) const SizedBox.shrink(),
      ],
    );
  }

  void _openVideos(String sort, String label) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CompetitorVideosScreen(competitorId: widget.id, title: label, initialSort: sort),
    ));
  }

  // ---------- channel trend chart (real daily snapshots only) ----------
  Widget _trendCard(List<Map<String, dynamic>> series) {
    final key = _trendMetric;
    final points = <FlSpot>[];
    final labels = <int, String>{};
    for (var i = 0; i < series.length; i++) {
      final v = series[i][key] as num?;
      if (v == null) continue;
      points.add(FlSpot(points.length.toDouble(), v.toDouble()));
      final d = DateTime.tryParse((series[i]['day'] ?? '').toString());
      labels[points.length - 1] = d == null ? '' : '${d.day}/${d.month}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _metricChip('subscribers', context.tr('rd_stat_subs')),
            const SizedBox(width: 8),
            _metricChip('views', context.tr('rd_stat_views')),
          ]),
          const SizedBox(height: 14),
          if (points.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(child: Text(context.tr('rd_trend_empty'), textAlign: TextAlign.center, style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))),
            )
          else
            SizedBox(height: 170, child: _lineChart(points, labels)),
        ],
      ),
    );
  }

  Widget _metricChip(String metric, String label) {
    final selected = _trendMetric == metric;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _trendMetric = metric),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : context.surfaces.card2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : null, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _lineChart(List<FlSpot> points, Map<int, String> labels) {
    final ys = points.map((p) => p.y).toList();
    var minY = ys.reduce((a, b) => a < b ? a : b);
    var maxY = ys.reduce((a, b) => a > b ? a : b);
    if (maxY == minY) {
      maxY = maxY + 1;
      minY = minY - 1;
    }
    final pad = (maxY - minY) * 0.15;
    final step = (points.length / 4).ceil().clamp(1, 1000);

    return LineChart(
      LineChartData(
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: context.surfaces.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                return Text(fmtCount(value), style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5));
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (value != i.toDouble() || i % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i] ?? '', style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5)),
                );
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            isCurved: false,
            barWidth: 2.5,
            color: AppColors.purple,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.purple.withValues(alpha: 0.25), AppColors.purple.withValues(alpha: 0.02)],
              ),
            ),
            spots: points,
          ),
        ],
      ),
    );
  }
}