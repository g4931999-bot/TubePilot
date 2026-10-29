import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

/// Smart Scheduler (UPDATE15). REAL data only.
///
/// The YouTube Data API does NOT expose "when is my audience online", so the
/// old hard-coded heatmap is gone. The heatmap and Suggested Best Times are
/// now built from the user's OWN published videos (GET /youtube/my-videos):
/// for every weekday x 3-hour slot, the MEDIAN views-per-day of the videos
/// published in that slot (videos younger than 2 days are skipped, because
/// their views are still growing). Each suggestion shows how many videos it
/// is based on - small samples are labelled, nothing is estimated.
///
/// UPDATE16: the Auto-Slotting switch is REAL. It is saved on the user
/// (PATCH /videos/auto-slotting). ON = scheduled uploads are placed at the
/// user's best time by the server (same real data, IST); OFF = the manual
/// time the user picks is used. The card shows the actual next auto slot.
class SmartSchedulerScreen extends StatefulWidget {
  const SmartSchedulerScreen({super.key});
  @override
  State<SmartSchedulerScreen> createState() => _SmartSchedulerScreenState();
}

class _Cell {
  final List<double> rates = [];
  double get median {
    final s = [...rates]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }
}

class _SmartSchedulerScreenState extends State<SmartSchedulerScreen> {
  static const _hourLabels = ['6a', '9a', '12p', '3p', '6p', '9p', '12a', '3a'];
  static const _slotStartHour = [6, 9, 12, 15, 18, 21, 0, 3];

  bool _autoSlotting = false;
  bool _savingAuto = false;
  DateTime? _nextAutoSlot;
  String _autoReason = '';
  bool _loading = true;
  bool _needsReconnect = false;
  List<Map<String, dynamic>> _queued = [];
  List<Map<String, dynamic>> _videos = [];
  int _rangeDays = 0; // 0 = all loaded videos
  late Duration _offset = DateTime.now().timeZoneOffset;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<String> _days(BuildContext context) => [
        context.tr('day_mon'), context.tr('day_tue'), context.tr('day_wed'), context.tr('day_thu'),
        context.tr('day_fri'), context.tr('day_sat'), context.tr('day_sun'),
      ];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _needsReconnect = false;
    });
    try {
      final res = await Future.wait([
        ApiService.instance.listVideos(status: 'queued'),
        ApiService.instance.getAutoSlotting().catchError((_) => <String, dynamic>{}),
        ApiService.instance.getMyYoutubeVideos(max: 100).catchError((e) {
          if (e is ApiException && (e.code == 'YOUTUBE_RECONNECT_REQUIRED' || e.status == 404)) {
            if (mounted) setState(() => _needsReconnect = true);
            return <String, dynamic>{};
          }
          throw e;
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _queued = (res[0]['videos'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _autoSlotting = res[1]['enabled'] == true;
        _nextAutoSlot = DateTime.tryParse((res[1]['nextSlot'] ?? '').toString())?.toLocal();
        _autoReason = (res[1]['reason'] ?? '').toString();
        _videos = (res[2]['videos'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAuto(bool v) async {
    setState(() {
      _autoSlotting = v;
      _savingAuto = true;
    });
    try {
      await ApiService.instance.setAutoSlotting(v);
      if (mounted) showToast(context, context.tr(v ? 'ss_auto_on_toast' : 'ss_auto_off_toast'), isSuccess: true);
    } catch (e) {
      if (mounted) {
        setState(() => _autoSlotting = !v);
        showApiError(context, e);
      }
    } finally {
      if (mounted) setState(() => _savingAuto = false);
    }
  }

  String _fmtSlot(DateTime d) {
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${_days(context)[d.weekday - 1]} ${d.day}/${d.month}  $h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  // ───── real computation ─────
  List<List<_Cell>> _grid() {
    final grid = List.generate(7, (_) => List.generate(8, (_) => _Cell()));
    final now = DateTime.now().toUtc();
    for (final v in _videos) {
      final views = v['viewCount'] as num?;
      final pub = DateTime.tryParse((v['publishedAt'] ?? '').toString())?.toUtc();
      if (views == null || pub == null) continue;
      final ageDays = now.difference(pub).inHours / 24;
      if (ageDays < 2) continue;
      if (_rangeDays > 0 && ageDays > _rangeDays) continue;
      final local = pub.add(_offset);
      final slot = ((local.hour - 6 + 24) % 24) ~/ 3;
      grid[local.weekday - 1][slot].rates.add(views / ageDays);
    }
    return grid;
  }

  int _level(double v, double max) {
    final r = max == 0 ? 0 : v / max;
    if (r >= 0.75) return 3;
    if (r >= 0.5) return 2;
    if (r >= 0.25) return 1;
    return 0;
  }

  Color _heatColor(int level) {
    switch (level) {
      case 3:
        return AppColors.purple;
      case 2:
        return AppColors.purpleLight;
      case 1:
        return AppColors.purpleLight.withValues(alpha: 0.5);
      default:
        return AppColors.purpleLight.withValues(alpha: 0.22);
    }
  }

  String _fmtRate(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}K' : v.toStringAsFixed(v >= 10 ? 0 : 1);

  String _slotText(int day, int slot) {
    final h = _slotStartHour[slot];
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '${_days(context)[day]} $h12:00 ${h < 12 ? 'AM' : 'PM'}';
  }

  String _offsetLabel(Duration o) {
    final m = o.inMinutes.abs();
    final sign = o.isNegative ? '-' : '+';
    return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  void _pickTimezone() {
    final opts = <Duration>{
      DateTime.now().timeZoneOffset,
      const Duration(hours: 0),
      const Duration(hours: 5, minutes: 30),
      const Duration(hours: 4),
      const Duration(hours: 8),
      const Duration(hours: 9),
      const Duration(hours: 1),
      const Duration(hours: -5),
      const Duration(hours: -8),
    }.toList()
      ..sort((a, b) => a.compareTo(b));
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const SizedBox(height: 12),
          for (final o in opts)
            ListTile(
              title: Text(_offsetLabel(o) + (o == DateTime.now().timeZoneOffset ? '  (${context.tr('ss_device')})' : ''), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: _offset == o ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
              onTap: () {
                setState(() => _offset = o);
                Navigator.pop(c);
              },
            ),
        ]),
      ),
    );
  }

  void _pickRange() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          for (final d in const [30, 90, 0])
            ListTile(
              title: Text(d == 0 ? context.tr('ss_range_all') : context.tr('wr_last_days').replaceAll('%1', '$d'), style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: _rangeDays == d ? const Icon(Icons.check_rounded, color: AppColors.purple) : null,
              onTap: () {
                setState(() {
                  _rangeDays = d;
                  _selected = 0;
                });
                Navigator.pop(c);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String? _earliestScheduledAt(Map<String, dynamic> video) {
    final platforms = video['platforms'] as List? ?? [];
    final dates = platforms.map((p) => p is Map ? p['scheduledAt'] : null).whereType<String>().map((s) => DateTime.tryParse(s)).whereType<DateTime>().toList();
    if (dates.isEmpty) return null;
    dates.sort();
    final d = dates.first.toLocal();
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ───── UI ─────
  // UPDATE21: compact pill button so the text never touches the border / overflows.
  Widget _pill({required VoidCallback onTap, required IconData icon, required String text, double maxWidth = 170}) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: context.surfaces.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _box({required Widget child, EdgeInsets? margin}) => Container(
        margin: margin,
        padding: const EdgeInsets.all(14),
        width: double.infinity,
        decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
        child: child,
      );

  Widget _legend(int level, String key) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(width: 16, height: 16, decoration: BoxDecoration(color: _heatColor(level), borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Text(context.tr(key), style: const TextStyle(fontSize: 11.5)),
        ]),
      );

  Widget _heatmap(List<List<_Cell>> grid, double max) {
    final days = _days(context);
    return _box(
      child: Column(children: [
        Row(children: [
          const SizedBox(width: 32),
          ..._hourLabels.map((h) => Expanded(child: Text(h, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: context.surfaces.textDim)))),
        ]),
        const SizedBox(height: 6),
        ...List.generate(7, (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 32, child: Text(days[row], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                ...List.generate(8, (col) {
                  final c = grid[row][col];
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(1.5),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.rates.isEmpty ? Colors.transparent : _heatColor(_level(c.median, max)),
                            border: c.rates.isEmpty ? Border.all(color: context.surfaces.border) : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ]),
            )),
        const SizedBox(height: 10),
        Wrap(spacing: 14, children: [
          _legend(3, 'ss_very_high'),
          _legend(2, 'ss_high'),
          _legend(1, 'ss_medium'),
          _legend(0, 'ss_low'),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 16, height: 16, decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 8),
              Text(context.tr('ss_no_data'), style: const TextStyle(fontSize: 11.5)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _bestCard(int idx, ({int day, int slot, double rate, int n, int level}) b) {
    final sel = _selected == idx;
    final label = idx == 0 ? 'ss_highest' : (b.level >= 2 ? 'ss_high_reach' : 'ss_medium_reach');
    return GestureDetector(
      onTap: () => setState(() => _selected = idx),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: sel ? AppColors.purple : context.surfaces.border, width: sel ? 2 : 1), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_slotText(b.day, b.slot), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: idx == 0 ? AppColors.purple : AppColors.purple.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
            child: Text(context.tr(label), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: idx == 0 ? Colors.white : AppColors.purple)),
          ),
          const SizedBox(height: 8),
          Text(context.tr('ss_rate').replaceAll('%1', _fmtRate(b.rate)), style: TextStyle(fontSize: 11.5, color: context.surfaces.textDim)),
          Text(context.tr('ss_based_on').replaceAll('%1', '${b.n}'), style: TextStyle(fontSize: 11, color: context.surfaces.textDim)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grid = _grid();
    double max = 0;
    final ranked = <({int day, int slot, double rate, int n, int level})>[];
    for (var d = 0; d < 7; d++) {
      for (var s = 0; s < 8; s++) {
        final c = grid[d][s];
        if (c.rates.isEmpty) continue;
        if (c.median > max) max = c.median;
      }
    }
    for (var d = 0; d < 7; d++) {
      for (var s = 0; s < 8; s++) {
        final c = grid[d][s];
        if (c.rates.isEmpty) continue;
        ranked.add((day: d, slot: s, rate: c.median, n: c.rates.length, level: _level(c.median, max)));
      }
    }
    ranked.sort((a, b) => b.rate.compareTo(a.rate));
    final best = ranked.take(5).toList();
    final used = ranked.fold<int>(0, (s, r) => s + r.n);
    final hasData = ranked.isNotEmpty;
    if (_selected >= best.length) _selected = 0;

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('smart_scheduler_title'))),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.purple,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            Expanded(child: Text(context.tr('ss_subtitle'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))),
            const SizedBox(width: 12),
            _pill(onTap: _pickTimezone, icon: Icons.public_rounded, text: _offsetLabel(_offset), maxWidth: 130),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(context.tr('audience_peak_activity'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            const SizedBox(width: 12),
            _pill(
              onTap: _pickRange,
              icon: Icons.expand_more_rounded,
              text: _rangeDays == 0 ? context.tr('ss_range_all') : context.tr('wr_last_days').replaceAll('%1', '$_rangeDays'),
              maxWidth: 160,
            ),
          ]),
          const SizedBox(height: 4),
          Text(context.tr('ss_peak_sub'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.35)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: LoadingView())
          else if (_needsReconnect)
            _box(child: Text(context.tr('sv_reconnect_msg'), style: const TextStyle(fontSize: 13, height: 1.4)))
          else ...[
            _heatmap(grid, max),
            const SizedBox(height: 6),
            Text(context.tr('ss_used').replaceAll('%1', '$used'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              SwitchListTile(
                value: _autoSlotting,
                onChanged: _savingAuto ? null : _toggleAuto,
                activeTrackColor: AppColors.purple,
                title: Text(context.tr('auto_slotting_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(context.tr('ss_auto_sub'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.35)),
              ),
              if (_autoSlotting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(_nextAutoSlot != null ? Icons.event_available_rounded : Icons.info_outline_rounded, size: 17, color: _nextAutoSlot != null ? AppColors.green : const Color(0xFFF5A623)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nextAutoSlot != null
                            ? context.tr('ss_auto_next').replaceAll('%1', _fmtSlot(_nextAutoSlot!))
                            : context.tr(_autoReason == 'youtube_not_connected' ? 'sv_reconnect_msg' : 'ss_auto_nodata'),
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
          if (!_loading && !_needsReconnect) ...[
            const SizedBox(height: 22),
            Row(children: [
              const Icon(Icons.auto_awesome_rounded, color: AppColors.purple, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(context.tr('ss_best_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
              if (best.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _slotText(best[_selected].day, best[_selected].slot)));
                    showToast(context, context.tr('ss_time_copied'), isSuccess: true);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: Text(context.tr('ss_copy_time')),
                ),
            ]),
            const SizedBox(height: 10),
            if (!hasData)
              _box(child: Text(context.tr('ss_not_enough'), style: TextStyle(color: context.surfaces.textDim, fontSize: 13, height: 1.4)))
            else ...[
              SizedBox(height: 150, child: ListView(scrollDirection: Axis.horizontal, children: [for (var i = 0; i < best.length; i++) _bestCard(i, best[i])])),
              if (ranked.any((r) => r.n < 2))
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(context.tr('ss_small_note'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11))),
              if (ranked.length >= 2)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: AppColors.purple, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.tr('ss_tip_title'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('ss_tip_text')
                              .replaceAll('%1', _slotText(ranked.first.day, ranked.first.slot))
                              .replaceAll('%2', ranked.last.rate <= 0 ? '—' : (ranked.first.rate / ranked.last.rate).toStringAsFixed(1))
                              .replaceAll('%3', _slotText(ranked.last.day, ranked.last.slot)),
                          style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim),
                        ),
                      ]),
                    ),
                  ]),
                ),
            ],
          ],
          const SizedBox(height: 24),
          Text(context.tr('preview_queue'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (!_loading && _queued.isEmpty)
            EmptyView(message: context.tr('queue_empty'), icon: Icons.event_note_rounded)
          else
            ..._queued.map((v) {
              final when = _earliestScheduledAt(v);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.schedule_rounded, size: 18, color: AppColors.purple),
                  const SizedBox(width: 10),
                  Expanded(child: Text(v['title'] ?? context.tr('untitled_video'), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                  if (when != null) Text(when, style: TextStyle(color: context.surfaces.textDim, fontSize: 12)),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
