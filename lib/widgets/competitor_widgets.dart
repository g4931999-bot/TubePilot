import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import 'common.dart';
import 'competitor_limit_sheet.dart';
import 'competitor_video_sheet.dart';

// Shared building blocks for the Competitor Radar screens.

/// 1234 -> 1.2K, 2500000 -> 2.5M, null -> —
String fmtCount(num? n) {
  if (n == null) return '—';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return n.round().toString();
}

/// "5h ago" / "3d ago" (strings come from rd_ago_hours / rd_ago_days).
String timeAgo(BuildContext context, String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inHours < 24) {
    final h = diff.inHours < 1 ? 1 : diff.inHours;
    return context.tr('rd_ago_hours').replaceAll('%1', '$h');
  }
  return context.tr('rd_ago_days').replaceAll('%1', '${diff.inDays}');
}

/// Every competitor gets its own stable colour so videos are easy to tell apart.
const _channelPalette = <Color>[
  Color(0xFF8E24AA), Color(0xFF1E88E5), Color(0xFF00897B), Color(0xFFEF6C00),
  Color(0xFFD81B60), Color(0xFF5E35B1), Color(0xFF43A047), Color(0xFF6D4C41),
];

Color channelColor(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _channelPalette[h % _channelPalette.length];
}

/// Small "avatar + channel name" pill in the channel's colour.
Widget competitorChannelChip(BuildContext context, {required String key, required String label, String thumbnail = ''}) {
  final color = channelColor(key);
  return Container(
    padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: color.withValues(alpha: 0.25),
          backgroundImage: thumbnail.isNotEmpty ? NetworkImage(thumbnail) : null,
          child: thumbnail.isEmpty ? Icon(Icons.person_rounded, size: 12, color: color) : null,
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5))),
      ],
    ),
  );
}

Future<void> openYoutubeVideo(String? url) async {
  if (url == null || url.isEmpty) return;
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Widget competitorSectionHeader(BuildContext context, String title, {VoidCallback? onViewAll}) {
  return Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800))),
        if (onViewAll != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onViewAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(context.tr('rd_view_all'), style: const TextStyle(color: AppColors.purpleLight, fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ),
      ],
    ),
  );
}

/// Small grey explanatory note (data limitations etc.).
Widget competitorNote(BuildContext context, String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: context.surfaces.textDim),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, height: 1.35))),
      ],
    ),
  );
}

/// Shown instead of Advanced-plan sections.
class CompetitorLockedCard extends StatelessWidget {
  final String message;
  const CompetitorLockedCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaces.card2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.surfaces.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(gradient: AppColors.gradient, shape: BoxShape.circle),
            child: const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => openUpgradeScreen(context),
            child: Text(context.tr('rd_upgrade'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// One competitor video. Shows TOTAL views and, separately, MEASURED growth
/// (only when the backend has two real snapshots for it).
class CompetitorVideoTile extends StatelessWidget {
  final Map<String, dynamic> video;
  final bool showChannel;
  const CompetitorVideoTile({super.key, required this.video, this.showChannel = true});

  @override
  Widget build(BuildContext context) {
    final thumb = (video['thumbnail'] ?? '').toString();
    final growth = video['growth'] is Map ? Map<String, dynamic>.from(video['growth']) : null;
    final out = video['outperform'] is Map ? Map<String, dynamic>.from(video['outperform']) : null;
    final channel = (video['channelLabel'] ?? '').toString();
    final ago = timeAgo(context, video['publishedAt']?.toString());
    final channelKey = (video['channelId'] ?? video['competitorId'] ?? channel).toString();
    final channelThumb = (video['channelThumbnail'] ?? '').toString();

    final chips = <Widget>[];
    if (growth != null) {
      final pct = growth['pct'] as num?;
      chips.add(AppBadge(
        label: context
                .tr('rd_growth_chip')
                .replaceAll('%1', fmtCount(growth['deltaViews'] as num?))
                .replaceAll('%2', '${((growth['hours'] as num?) ?? 0).round()}') +
            (pct != null ? ' · ${pct.toStringAsFixed(pct.abs() >= 100 ? 0 : 1)}%' : ''),
        color: AppColors.green,
      ));
    }
    if (out != null) {
      chips.add(AppBadge(label: context.tr('rd_outperform_chip').replaceAll('%1', '${out['ratio']}'), color: AppColors.purpleLight));
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => showCompetitorVideoSheet(context, video),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: showChannel && channel.isNotEmpty ? channelColor(channelKey).withValues(alpha: 0.55) : context.surfaces.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 118,
                height: 66,
                child: thumb.isNotEmpty
                    ? Image.network(
                        thumb,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined)),
                      )
                    : Container(color: context.surfaces.card2, child: const Icon(Icons.movie_outlined)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (video['title'] ?? '').toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
                  ),
                  const SizedBox(height: 5),
                  if (showChannel && channel.isNotEmpty) ...[
                    competitorChannelChip(context, key: channelKey, label: channel, thumbnail: channelThumb),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    '${fmtCount(video['views'] as num?)} ${context.tr('rd_views_suffix')}${ago.isEmpty ? '' : ' · $ago'}',
                    style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: chips),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A topic / content-opportunity row (keyword counting - not a viral promise).
/// Tap to expand: shows the videos behind the topic and WHICH competitor made them.
class CompetitorTopicTile extends StatefulWidget {
  final Map<String, dynamic> topic;
  final int rank;
  const CompetitorTopicTile({super.key, required this.topic, required this.rank});

  @override
  State<CompetitorTopicTile> createState() => _CompetitorTopicTileState();
}

class _CompetitorTopicTileState extends State<CompetitorTopicTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final topic = widget.topic;
    final strength = topic['strength'] as num?;
    final name = (topic['topic'] ?? '').toString();
    final display = name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
    var videos = (topic['topVideos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (videos.isEmpty && topic['exampleVideo'] is Map) {
      videos = [Map<String, dynamic>.from(topic['exampleVideo'])];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: context.surfaces.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: videos.isEmpty ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.purple, shape: BoxShape.circle),
                    child: Text('${widget.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(display, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                        const SizedBox(height: 3),
                        Text(
                          context
                              .tr('rd_topic_stats')
                              .replaceAll('%1', '${topic['videos']}')
                              .replaceAll('%2', '${topic['channels']}')
                              .replaceAll('%3', fmtCount(topic['avgViews'] as num?)),
                          style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if (strength != null) ...[
                    const SizedBox(width: 8),
                    AppBadge(
                      label: context.tr('rd_topic_strength').replaceAll('%1', strength.toStringAsFixed(1)),
                      color: strength >= 1 ? AppColors.green : AppColors.purpleLight,
                    ),
                  ],
                  if (videos.isNotEmpty) Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: context.surfaces.textDim),
                ],
              ),
            ),
          ),
          if (_open && videos.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 8),
                    child: Text(context.tr('rd_topic_top_videos'), style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                  ...videos.map((v) => CompetitorVideoTile(video: v)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}