import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../providers/language_provider.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  final bool embedded;
  const AnalyticsScreen({super.key, this.embedded = false});
  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? analytics;
  int unreadCount = 0;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoader = true}) async {
    if (showLoader) setState(() => loading = true);
    try {
      final results = await Future.wait([
        ApiService.instance.getAnalytics(),
        ApiService.instance.getNotifications().catchError((_) => <String, dynamic>{}),
      ]);
      setState(() {
        analytics = results[0]['analytics'];
        unreadCount = (results[1]['unreadCount'] as num?)?.toInt() ?? 0;
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (showLoader && mounted) setState(() => loading = false);
    }
  }

  void _goToProfile() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen())).then((_) => _load(showLoader: false));
  }

  // ⚠️ FIX (Boss request — "analyze screen mein question mark hai profile
  // screen mein but wahan real email honi chahiye"): this avatar used to
  // be a plain "?" icon that opened a generic help dialog. It now reads
  // straight from AuthProvider's cached user object — the SAME source of
  // truth dashboard_screen.dart's avatar uses — so it can never disagree
  // with what Dashboard/Settings show, and tapping it opens Profile
  // instead of a help popup.
  String? _userEmail(BuildContext context) {
    final user = context.watch<AuthProvider>().user ?? {};
    final email = user['email'];
    return (email is String && email.isNotEmpty) ? email : null;
  }

  String _userInitial(BuildContext context) {
    final email = _userEmail(context);
    return (email != null) ? email.trim()[0].toUpperCase() : '?';
  }

  int get _diamondCostPerUpload {
    final cost = analytics?['diamondCostPerUpload'] ?? analytics?['uploadCostDiamonds'];
    if (cost is num && cost > 0) return cost.toInt();
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    final trend = (analytics?['uploadTrend'] as List?) ?? [];
    final activity = (analytics?['recentActivity'] as List?) ?? [];
    final diamondBalance = (analytics?['remainingUploadCredits'] ?? 0) as num;
    final worthUploads = diamondBalance ~/ _diamondCostPerUpload;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: 20,
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('analytics_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
            Text(context.tr('analytics_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))
                    .then((_) => _load(showLoader: false)),
              ),
              if (unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$unreadCount', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _goToProfile,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
                ),
                child: Text(
                  _userInitial(context),
                  style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: () => _load(showLoader: false),
              child: ListView(
                // ⚠️ TIGHTENED FURTHER (Boss request — "aur upar karo"):
                // top padding trimmed from 8 → 4.
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
                children: [
                  // ⚠️ FIX (Boss request — "BOTTOM OVERFLOWED" red pixel
                  // errors on every metric card): 1.6 was too short for
                  // the icon + label + value (+ subtitle) column to fit,
                  // so every card clipped its bottom row. Lowered to 1.3
                  // (taller cards) — combined with the tightened
                  // _MetricCard padding/spacing below — so the content
                  // fits with room to spare instead of overflowing.
                  GridView.count(
                    padding: EdgeInsets.zero,
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.3,
                    children: [
                      _MetricCard(
                        icon: Icons.cloud_upload_rounded,
                        label: context.tr('free_uploads_left'),
                        value: '${analytics?['freeUploadsLeft'] ?? 0}',
                        subtitle: context.tr('resets_30_days'),
                      ),
                      _MetricCard(
                        icon: Icons.diamond_rounded,
                        label: context.tr('diamond_balance'),
                        value: '$diamondBalance',
                        subtitle: worthUploads > 0 ? context.tr('diamonds_worth_uploads').replaceAll('%d', '$worthUploads') : null,
                      ),
                      _MetricCard(
                        icon: Icons.play_circle_fill_rounded,
                        label: context.tr('videos_published'),
                        value: '${analytics?['uploadCount'] ?? 0}',
                        subtitle: context.tr('total_videos'),
                      ),
                      _MetricCard(
                        icon: Icons.event_available_rounded,
                        label: context.tr('scheduled_videos'),
                        value: '${analytics?['scheduledQueue'] ?? 0}',
                        subtitle: context.tr('this_month'),
                      ),
                    ],
                  ),
                  // ⚠️ FIX (Boss request — "gap hai use hatao aur
                  // componets ko aur upar karo"): 12 → 6, so the chart
                  // card sits right under the stats grid.
                  const SizedBox(height: 12),

                  // ---------------- 14-day upload trend chart ----------------
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(context.tr('uploads_last_14_days'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                            _periodDropdown(context),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(context.tr('uploads_consistency_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 160,
                          child: trend.isEmpty ? _emptyChartPlaceholder(context) : _buildTrendChart(context, trend),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.06), border: Border.all(color: AppColors.red.withValues(alpha: 0.25)), borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.red.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.warning_amber_rounded, color: AppColors.red, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(context.tr('failed_uploads'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 4),
                              Text(context.tr('analytics_placeholder_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
                          child: Text('${analytics?['failedUploads'] ?? 0}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ---------------- Recent activity ----------------
                  Text(context.tr('recent_activity'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (activity.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Text(context.tr('no_activity_yet'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: List.generate(activity.length, (i) {
                          final a = activity[i] as Map<String, dynamic>;
                          final isLast = i == activity.length - 1;
                          return Column(children: [_activityRow(context, a), if (!isLast) Divider(height: 1, color: context.surfaces.border)]);
                        }),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _periodDropdown(BuildContext context) {
    return PopupMenuButton<String>(
      itemBuilder: (_) => [PopupMenuItem(value: '14d', child: Text(context.tr('uploads_last_14_days')))],
      onSelected: (_) {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.tr('uploads_last_14_days'), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: context.surfaces.textDim),
          ],
        ),
      ),
    );
  }

  Widget _emptyChartPlaceholder(BuildContext context) {
    return Center(
      child: Text(context.tr('no_uploads_14_days'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
    );
  }

  Widget _buildTrendChart(BuildContext context, List trend) {
    final counts = trend.map((t) => (t['count'] as num?)?.toDouble() ?? 0).toList();
    final maxY = (counts.isEmpty ? 1.0 : counts.reduce((a, b) => a > b ? a : b));
    final chartMaxY = maxY < 4 ? 4.0 : maxY + 2;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: chartMaxY,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: chartMaxY / 4, getDrawingHorizontalLine: (_) => FlLine(color: context.surfaces.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: chartMaxY / 4 == 0 ? 1 : chartMaxY / 4,
              getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= trend.length) return const SizedBox.shrink();
                if (i % 2 != 0) return const SizedBox.shrink();
                final dateStr = trend[i]['date'] as String;
                final d = DateTime.tryParse(dateStr);
                final label = d == null ? '' : '${d.day}/${d.month}';
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5)));
              },
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: true),
        lineBarsData: [
          LineChartBarData(
            isCurved: true,
            barWidth: 2.5,
            color: AppColors.purple,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(radius: 3.5, color: AppColors.purple, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.purple.withValues(alpha: 0.28), AppColors.purple.withValues(alpha: 0.02)],
              ),
            ),
            spots: List.generate(counts.length, (i) => FlSpot(i.toDouble(), counts[i])),
          ),
        ],
      ),
    );
  }

  Widget _activityRow(BuildContext context, Map<String, dynamic> a) {
    final usedFreeUpload = a['usedFreeUpload'] == true;
    final diamondsCharged = (a['diamondsCharged'] ?? 0) as num;
    final status = (a['status'] ?? '').toString();
    final title = a['title'] ?? '';
    final date = a['createdAt'] as String?;

    late final String emoji;
    late final String headline;
    late final Color color;
    if (status == 'failed') {
      emoji = '⚠️';
      headline = context.tr('activity_upload_failed');
      color = AppColors.red;
    } else if (status == 'uploaded') {
      emoji = '✅';
      headline = context.tr('activity_video_uploaded');
      color = AppColors.green;
    } else {
      emoji = '📤';
      headline = context.tr('activity_upload_queued');
      color = AppColors.purple;
    }

    final subtitle = usedFreeUpload
        ? context.tr('used_free_upload')
        : (diamondsCharged > 0 ? context.tr('spent_diamonds').replaceAll('%d', '$diamondsCharged') : (title.toString().isNotEmpty ? title.toString() : context.tr('no_charge')));

    return ListTile(
      dense: true,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Text(emoji, style: const TextStyle(fontSize: 15)),
      ),
      title: Text(headline, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: Text(_timeAgo(date), style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5)),
    );
  }

  // Local "x ago" formatter — kept here rather than assuming a shared
  // helper exists in widgets/common.dart (that file wasn't provided).
  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return context.tr('time_just_now');
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ${context.tr('time_ago_suffix')}';
    if (diff.inHours < 24) return '${diff.inHours}h ${context.tr('time_ago_suffix')}';
    if (diff.inDays < 7) return '${diff.inDays}d ${context.tr('time_ago_suffix')}';
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  const _MetricCard({required this.icon, required this.label, required this.value, this.subtitle}) : onTap = null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // ⚠️ TIGHTENED (Boss's overflow fix, alongside the 1.3 aspect
        // ratio above): vertical padding 10 → 8, plus the internal gaps
        // below, so there's extra breathing room even on smaller screens.
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaces.card2,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: AppColors.purple, size: 14),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 1),
            Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              Text(subtitle!, style: TextStyle(color: context.surfaces.textDim, fontSize: 9.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
      ),
    );
  }
}