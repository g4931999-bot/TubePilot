import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';
import '../widgets/competitor_limit_sheet.dart' show openUpgradeScreen;
import '../widgets/competitor_widgets.dart' show fmtCount, openYoutubeVideo;

/// Channel Audit - health score + Content Performance, Titles, Thumbnails,
/// Consistency and Audience Engagement cards. Data: GET /analytics/audit
/// (`report` = real numbers from the YouTube Data API, nothing estimated).
class ChannelAuditScreen extends StatefulWidget {
  const ChannelAuditScreen({super.key});
  @override
  State<ChannelAuditScreen> createState() => _ChannelAuditScreenState();
}

class _ChannelAuditScreenState extends State<ChannelAuditScreen> {
  bool _loading = true;
  Map<String, dynamic>? _audit;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.instance.getChannelAudit();
      if (!mounted) return;
      setState(() {
        _audit = res['audit'] is Map ? Map<String, dynamic>.from(res['audit']) : null;
        _report = res['report'] is Map ? Map<String, dynamic>.from(res['report']) : null;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------- helpers ----------------
  Map<String, dynamic> _m(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  List<Map<String, dynamic>> _l(dynamic v) => (v as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Color _levelColor(String level) {
    switch (level) {
      case 'healthy':
        return AppColors.green;
      case 'attention':
        return const Color(0xFFF9A825);
      default:
        return AppColors.red;
    }
  }

  Widget _card({required IconData icon, required Color color, required String title, String? badge, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaces.card2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
              if (badge != null) AppBadge(label: badge, color: color),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 14, color: context.surfaces.textDim),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.35))),
          ],
        ),
      );

  Widget _empty(String key) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(context.tr(key), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
      );

  Widget _bigStat(String value, String label, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
        ],
      );

  /// Simple line chart. `values[i] == null` points are skipped. Labels = first / last day.
  Widget _line(List<Map<String, dynamic>> daily, String field, Color color, {bool percent = false}) {
    final spots = <FlSpot>[];
    for (var i = 0; i < daily.length; i++) {
      final v = daily[i][field];
      if (v is num) spots.add(FlSpot(i.toDouble(), v.toDouble()));
    }
    if (spots.length < 2) return const SizedBox.shrink();
    final maxY = spots.map((s) => s.y).reduce(math.max);
    final top = maxY <= 0 ? 1.0 : maxY * 1.15;
    String dayLabel(int i) {
      final d = (daily[i]['day'] ?? '').toString();
      return d.length >= 10 ? d.substring(5) : d;
    }

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: top,
          minX: 0,
          maxX: (daily.length - 1).toDouble(),
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
                reservedSize: 38,
                getTitlesWidget: (value, meta) {
                  if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                  return Text(percent ? '${value.toStringAsFixed(1)}%' : fmtCount(value), style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5));
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
                  if (value != i.toDouble() || (i != 0 && i != daily.length - 1 && i != (daily.length - 1) ~/ 2)) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(dayLabel(i), style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5)));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 2.5,
              color: color,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.02)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- cards ----------------
  Widget _healthCard() {
    final h = _m(_report?['health']);
    final score = (h['score'] as num?)?.toInt() ?? 0;
    final level = (h['level'] ?? 'work').toString();
    final color = _levelColor(level);
    final parts = _l(h['parts']);
    return _card(
      icon: Icons.favorite_rounded,
      color: AppColors.green,
      title: context.tr('au_health_title'),
      children: [
        Center(
          child: SizedBox(
            width: 200,
            height: 120,
            child: CustomPaint(
              painter: _GaugePainter(score / 100, color, context.surfaces.border),
              child: Align(
                alignment: const Alignment(0, 0.55),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$score', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, height: 1)),
                    Text(context.tr('au_score'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(child: AppBadge(label: context.tr('au_level_$level'), color: color)),
        const SizedBox(height: 12),
        Text(context.tr('au_health_$level'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        ...parts.map((p) {
          final v = ((p['score'] as num?) ?? 0).toInt();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 92, child: Text(context.tr('au_part_${p['key']}'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: v / 100, minHeight: 8, color: _levelColor(v >= 80 ? 'healthy' : v >= 60 ? 'attention' : 'work'), backgroundColor: context.surfaces.border),
                  ),
                ),
                SizedBox(width: 34, child: Text('$v', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800))),
              ],
            ),
          );
        }),
        _note(context.tr('au_health_note')),
      ],
    );
  }

  Widget _performanceCard() {
    final p = _m(_report?['performance']);
    final daily = _l(p['daily']);
    final videos = (p['videos'] as num?)?.toInt() ?? 0;
    final avg = p['avgViews'] as num?;
    final prevAvg = p['prevAvgViews'] as num?;
    return _card(
      icon: Icons.bar_chart_rounded,
      color: AppColors.purple,
      title: context.tr('au_perf_title'),
      badge: context.tr('au_last_28'),
      children: [
        if (videos == 0)
          _empty('au_perf_empty')
        else ...[
          Row(
            children: [
              Expanded(child: _bigStat(fmtCount(p['views'] as num?), context.tr('au_perf_views').replaceAll('%1', '$videos'))),
              Expanded(child: _bigStat(fmtCount(avg), context.tr('au_perf_avg'))),
            ],
          ),
          const SizedBox(height: 14),
          _line(daily, 'views', AppColors.green),
          if (prevAvg != null) _note(context.tr('au_perf_prev').replaceAll('%1', fmtCount(prevAvg))),
          _note(context.tr('au_perf_note')),
        ],
      ],
    );
  }

  Widget _titleLine(Map<String, dynamic> v, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: (v['title'] ?? '').toString()));
        if (mounted) showToast(context, context.tr('au_copied'), isSuccess: true);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(child: Text((v['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            AppBadge(label: '${fmtCount(v['viewsPerDay'] as num?)} ${context.tr('au_views_day')}', color: color),
          ],
        ),
      ),
    );
  }

  Widget _patternRow(Map<String, dynamic> p) {
    final code = (p['code'] ?? '').toString();
    final ready = p['ready'] == true;
    final diff = p['diffPct'] as num?;
    final up = diff != null && diff >= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('au_pat_$code'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (!ready)
            Text(
              '${p['withCount']} / ${p['withoutCount']} - ${context.tr('au_pat_low').replaceAll('%1', '${_m(_report?['titles'])['minGroup'] ?? 3}')}',
              style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
            )
          else ...[
            Row(
              children: [
                Expanded(child: _patCell(context.tr('au_pat_with'), p['withCount'], p['withMedian'])),
                Expanded(child: _patCell(context.tr('au_pat_without'), p['withoutCount'], p['withoutMedian'])),
              ],
            ),
            const SizedBox(height: 8),
            if (diff != null)
              Text(
                context.tr(up ? 'au_pat_up' : 'au_pat_down').replaceAll('%1', '${diff.abs()}'),
                style: TextStyle(color: up ? AppColors.green : AppColors.red, fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
          ],
        ],
      ),
    );
  }

  Widget _patCell(String label, dynamic count, dynamic median) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
          Text('${fmtCount(median as num?)} ${context.tr('au_views_day')}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          Text(context.tr('au_pat_videos').replaceAll('%1', '$count'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
        ],
      );

  Widget _titlesCard() {
    final t = _report?['titles'] is Map ? _m(_report!['titles']) : null;
    final lengths = t == null ? <Map<String, dynamic>>[] : _l(t['lengths']);
    final bestLen = t?['bestLength']?.toString();
    return _card(
      icon: Icons.title_rounded,
      color: const Color(0xFF1E88E5),
      title: context.tr('au_titles_title'),
      children: [
        if (t == null)
          _empty('au_titles_empty')
        else ...[
          Text(context.tr('au_titles_best'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.green)),
          const SizedBox(height: 4),
          ..._l(t['best']).map((v) => _titleLine(v, AppColors.green)),
          const SizedBox(height: 10),
          Text(context.tr('au_titles_worst'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.red)),
          const SizedBox(height: 4),
          ..._l(t['worst']).map((v) => _titleLine(v, AppColors.red)),
          const SizedBox(height: 14),
          Text(context.tr('au_titles_patterns'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ..._l(t['patterns']).map(_patternRow),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('au_titles_length'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...lengths.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(context.tr('au_len_${l['bucket']}'), style: const TextStyle(fontSize: 12.5))),
                          Text(
                            l['ready'] == true
                                ? '${fmtCount(l['median'] as num?)} ${context.tr('au_views_day')} · ${context.tr('au_pat_videos').replaceAll('%1', '${l['count']}')}'
                                : '${context.tr('au_pat_videos').replaceAll('%1', '${l['count']}')} · ${context.tr('au_data_low')}',
                            style: TextStyle(
                              color: l['bucket'] == bestLen ? AppColors.green : context.surfaces.textDim,
                              fontSize: 12,
                              fontWeight: l['bucket'] == bestLen ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )),
                if (bestLen != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context.tr('au_titles_best_len').replaceAll('%1', context.tr('au_len_$bestLen')), style: const TextStyle(color: AppColors.green, fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          _note(context.tr('au_titles_note2').replaceAll('%1', '${t['sampled']}')),
        ],
      ],
    );
  }

  Widget _thumbRow(List<Map<String, dynamic>> list, Color color) {
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: list
            .map((v) => GestureDetector(
                  onTap: () => openYoutubeVideo('https://www.youtube.com/watch?v=${v['videoId']}'),
                  child: Container(
                    width: 132,
                    margin: const EdgeInsets.only(right: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network((v['thumbnail'] ?? '').toString(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text('${fmtCount(v['viewsPerDay'] as num?)} ${context.tr('au_views_day')}', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
                        if (v['vsMedian'] != null) Text(context.tr('au_vs_median').replaceAll('%1', '${v['vsMedian']}'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
                      ],
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _thumbnailsCard() {
    final t = _report?['thumbnails'] is Map ? _m(_report!['thumbnails']) : null;
    return _card(
      icon: Icons.image_rounded,
      color: const Color(0xFF8E24AA),
      title: context.tr('au_thumbs_title'),
      children: [
        if (t == null)
          _empty('au_thumbs_empty')
        else ...[
          Text(context.tr('au_thumbs_best'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.green)),
          const SizedBox(height: 8),
          _thumbRow(_l(t['best']), AppColors.green),
          const SizedBox(height: 12),
          Text(context.tr('au_thumbs_worst'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.red)),
          const SizedBox(height: 8),
          _thumbRow(_l(t['worst']), AppColors.red),
          _note(context.tr('au_thumbs_note').replaceAll('%1', '${t['sampled']}')),
        ],
      ],
    );
  }

  Widget _consistencyCard() {
    final c = _m(_report?['consistency']);
    final week = _l(c['week']);
    final hasVideos = ((_report?['videosAnalysed'] as num?) ?? 0) > 0;
    return _card(
      icon: Icons.calendar_month_rounded,
      color: const Color(0xFFF9A825),
      title: context.tr('au_cons_title'),
      badge: context.tr('au_last_7'),
      children: [
        if (!hasVideos)
          _empty('au_no_videos')
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: week.map((d) {
              final done = ((d['uploads'] as num?) ?? 0) > 0;
              return Column(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: done ? AppColors.green : context.surfaces.border,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded, size: 18, color: done ? Colors.white : context.surfaces.textDim),
                  ),
                  const SizedBox(height: 4),
                  Text(context.tr('au_wd_${d['weekday']}'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _bigStat('${c['perWeek']}', context.tr('au_cons_per_week'))),
              Expanded(child: _bigStat(c['avgGapDays'] == null ? '—' : '${c['avgGapDays']}', context.tr('au_cons_gap'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (c['daysSinceLast'] as num?) == null
                ? ''
                : context.tr('au_cons_since').replaceAll('%1', '${c['daysSinceLast']}'),
            style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
          ),
          if (((c['weekendUploads'] as num?) ?? 0) == 0 && ((c['uploadsLast28'] as num?) ?? 0) > 0) _note(context.tr('au_cons_weekend')),
        ],
      ],
    );
  }

  Widget _engagementCard() {
    final e = _m(_report?['engagement']);
    final pct = e['pct'] as num?;
    final delta = e['deltaPoints'] as num?;
    final daily = _l(e['daily']);
    return _card(
      icon: Icons.groups_rounded,
      color: const Color(0xFFD81B60),
      title: context.tr('au_eng_title'),
      badge: context.tr('au_last_28'),
      children: [
        if (pct == null)
          _empty('au_eng_empty')
        else ...[
          Row(
            children: [
              Expanded(child: _bigStat('${pct.toStringAsFixed(2)}%', context.tr('au_eng_rate'))),
              if (delta != null)
                Expanded(
                  child: _bigStat(
                    '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(2)}',
                    context.tr('au_eng_delta'),
                    color: delta >= 0 ? AppColors.green : AppColors.red,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _line(daily, 'pct', const Color(0xFFD81B60), percent: true),
          if (e['basedOnRecent'] == true) _note(context.tr('au_eng_recent')),
          _note(context.tr('au_eng_note')),
        ],
      ],
    );
  }

  Widget _recommendations() {
    final unlocked = _audit?['channelSeoUnlocked'] == true;
    final recs = _l(_audit?['recommendations']);
    return _card(
      icon: Icons.auto_awesome_rounded,
      color: AppColors.purple,
      title: context.tr('au_recs_title'),
      children: [
        if (!unlocked)
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
                child: const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(context.tr('au_recs_locked'), style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => openUpgradeScreen(context), child: Text(context.tr('rd_upgrade'), style: const TextStyle(fontWeight: FontWeight.w800))),
            ],
          )
        else
          ...recs.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tips_and_updates_outlined, size: 18, color: AppColors.purple),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r['message'] ?? '').toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
                          if ((r['prompt'] ?? '').toString().isNotEmpty)
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: r['prompt'].toString()));
                                if (mounted) showToast(context, context.tr('au_copied'), isSuccess: true);
                              },
                              icon: const Icon(Icons.copy_rounded, size: 15),
                              label: Text(context.tr('au_copy_prompt'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _basics() {
    final a = _audit ?? <String, dynamic>{};
    Widget tile(String v, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(color: context.surfaces.card2, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.surfaces.border)),
            child: Column(
              children: [
                Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
              ],
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          tile(fmtCount(a['subscriberCount'] as num?), context.tr('rd_stat_subs')),
          tile(fmtCount(a['totalViews'] as num?), context.tr('rd_stat_views')),
          tile(fmtCount(a['totalVideos'] as num?), context.tr('rd_stat_videos')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('au_title'))),
      body: _loading
          ? const LoadingView()
          : _audit == null
              ? EmptyView(message: context.tr('au_load_failed'), icon: Icons.fact_check_outlined)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      _basics(),
                      if (_report != null) ...[
                        _healthCard(),
                        _performanceCard(),
                        _titlesCard(),
                        _thumbnailsCard(),
                        _consistencyCard(),
                        _engagementCard(),
                      ],
                      _recommendations(),
                    ],
                  ),
                ),
    );
  }
}

/// Semicircle gauge: grey track + coloured arc for the score.
class _GaugePainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  final Color track;
  _GaugePainter(this.value, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(14, 14, size.width - 28, (size.width - 28));
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, math.pi, math.pi, false, base);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, math.pi, math.pi * value.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.value != value || old.color != color || old.track != track;
}