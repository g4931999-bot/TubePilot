import 'package:flutter/material.dart';
import '../providers/language_provider.dart';
import '../widgets/channel_video_list.dart';
import 'thumbnail_analysis_screen.dart';

/// Visual Analyzer - step 1: pick one of your channel videos (UPDATE14 flow).
/// Video list -> Thumbnail Analysis -> Improvement + ChatGPT prompt ->
/// Upload improved thumbnail -> Preview & Apply -> Success.
class VisualAnalyzerScreen extends StatelessWidget {
  const VisualAnalyzerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('visual_analyzer_title'))),
      body: ChannelVideoList(
        cardStyle: true,
        onSelect: (v) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ThumbnailAnalysisScreen(video: v))),
      ),
    );
  }
}