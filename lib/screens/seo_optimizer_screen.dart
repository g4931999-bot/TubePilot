import 'package:flutter/material.dart';
import '../providers/language_provider.dart';
import '../widgets/channel_video_list.dart';
import 'seo_video_detail_screen.dart';

/// Video SEO Optimizer - step 1: pick a video from the connected channel.
/// (UPDATE14: new flow. No "Connect YouTube" screen - the channel is linked
/// at signup; a Reconnect button only appears if Google expired the link.)
class SeoOptimizerScreen extends StatefulWidget {
  const SeoOptimizerScreen({super.key});
  @override
  State<SeoOptimizerScreen> createState() => _SeoOptimizerScreenState();
}

class _SeoOptimizerScreenState extends State<SeoOptimizerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('video_seo_optimizer_title'))),
      body: ChannelVideoList(
        // Shows the score only for videos analysed in this session (real result).
        trailingText: (v) {
          final r = SeoVideoDetailScreen.cache[(v['videoId'] ?? '').toString()];
          final s = (r?['seoScore'] as num?)?.toInt();
          return s == null ? null : context.tr('so_score_chip').replaceAll('%1', '$s');
        },
        onSelect: (v) async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeoVideoDetailScreen(video: v)));
          if (mounted) setState(() {});
        },
      ),
    );
  }
}