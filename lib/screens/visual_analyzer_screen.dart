import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../services/api_service.dart';
import '../widgets/common.dart';
import 'diamond_store_screen.dart';

/// Screen 5/7 — thumbnail mockup previewer + on-device contrast analysis.
///
/// The "Visual Score" is computed for real, on-device, from the picked
/// image's actual pixels (luminance standard deviation = contrast proxy,
/// mean luminance = brightness) — not a placeholder/random number. There's
/// no ML-based composition/face-detection scoring here (that would need a
/// vision model this app doesn't have access to); this is a genuine but
/// simple contrast+brightness heuristic, labelled as such.
///
/// ⚠️ UPDATED (Boss request — "upload karne ke baad analyse button add
/// karo"): picking an image no longer auto-triggers analysis. It now just
/// loads the image into the mockup preview, and a dedicated "Analyze"
/// button appears below it — the user taps it when ready (e.g. after also
/// typing/adjusting the title, since the mockup preview uses that same
/// title text). The button is also how a user re-runs analysis on the
/// SAME image after changing something, without having to re-pick it.
class VisualAnalyzerScreen extends StatefulWidget {
  const VisualAnalyzerScreen({super.key});
  @override
  State<VisualAnalyzerScreen> createState() => _VisualAnalyzerScreenState();
}

enum _MockupTab { instagram, youtube, facebook }

class _VisualAnalyzerScreenState extends State<VisualAnalyzerScreen> {
  File? _image;
  final _titleCtrl = TextEditingController();
  String? _channelName;
  String? _channelThumb;
  final _MockupTab _tab = _MockupTab.youtube;
  bool _analyzing = false;
  double? _contrastScore; // 0-100
  double? _brightness; // 0-255

  // ⚠️ NEW: tracks whether the CURRENT image has already been analyzed at
  // least once — used to swap the button's label between "Analyze" (first
  // run) and "Re-analyze" (after a result is already showing), and to
  // decide whether the score card is stale relative to a freshly picked
  // image (score/brightness are cleared on every new pick, so this stays
  // in sync automatically).
  bool get _hasResult => _contrastScore != null && _brightness != null;

  int? _diamondBalance;
  static const int _previewWordCount = 13;

  bool get _isUnlocked => (_diamondBalance ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    _loadDiamondBalance();
    _loadChannel();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    try {
      final res = await ApiService.instance.getYoutubeChannel();
      final ch = res['success'] == true ? res['channel'] : null;
      if (ch is Map && mounted) {
        setState(() {
          _channelName = (ch['channelTitle'] ?? '').toString().trim();
          _channelThumb = (ch['thumbnail'] ?? '').toString().trim();
        });
      }
    } catch (_) {}
  }

  Widget _channelAvatar(double radius) {
    final name = (_channelName ?? '').trim();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.purple,
      child: name.isEmpty
          ? null
          : Text(String.fromCharCode(name.runes.first).toUpperCase(),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.9)),
    );
    final url = _channelThumb ?? '';
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(url, width: radius * 2, height: radius * 2, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback),
    );
  }

  String get _youtubeSubtitle =>
      (_channelName ?? '').isNotEmpty ? _channelName! : context.tr('visual_your_channel_views');

  Future<void> _loadDiamondBalance() async {
    try {
      final res = await ApiService.instance.getWallet();
      if (!mounted) return;
      setState(() {
        _diamondBalance = (res['wallet']?['diamondBalance'] as int?) ?? 0;
      });
    } catch (_) {
      if (mounted) setState(() => _diamondBalance = 0);
    }
  }

  // ⚠️ UPDATED: no longer calls _analyze() automatically. Just loads the
  // picked file into the mockup preview and clears any previous score, so
  // the "Analyze" button starts fresh for the new image.
  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _contrastScore = null;
      _brightness = null;
    });
  }

  Future<void> _analyze() async {
    if (_image == null) return;
    setState(() => _analyzing = true);
    try {
      final bytes = await _image!.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120); // downscale for a fast, cheap sample
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return;

      final pixels = byteData.buffer.asUint8List();
      final luminances = <double>[];
      for (int i = 0; i < pixels.length; i += 4) {
        final r = pixels[i], g = pixels[i + 1], b = pixels[i + 2];
        luminances.add(0.299 * r + 0.587 * g + 0.114 * b);
      }
      final mean = luminances.reduce((a, b) => a + b) / luminances.length;
      final variance = luminances.map((l) => (l - mean) * (l - mean)).reduce((a, b) => a + b) / luminances.length;
      final stdDev = math.sqrt(variance.abs());
      final normalizedContrast = (stdDev / 128 * 100).clamp(0, 100).toDouble();

      setState(() {
        _brightness = mean;
        _contrastScore = normalizedContrast;
      });

      // Small confirmation so a re-analyze after tweaking the title feels
      // responsive even though the underlying pixels (and therefore the
      // score) haven't actually changed.
      if (mounted) showToast(context, context.tr('visual_analysis_done_toast'), isSuccess: true);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Color _scoreColor(double score) {
    if (score >= 60) return AppColors.green;
    if (score >= 35) return const Color(0xFFF5A623);
    return AppColors.red;
  }

  String _readabilityNote() {
    if (_contrastScore == null || _brightness == null) return '';
    if (_contrastScore! < 35) return context.tr('visual_note_low_contrast');
    if (_brightness! < 60) return context.tr('visual_note_dark_overall');
    if (_brightness! > 200) return context.tr('visual_note_bright_overall');
    return context.tr('visual_note_good_balance');
  }

  String _generateGeminiPrompt() {
    if (_contrastScore == null || _brightness == null) return '';
    if (_contrastScore! < 35) {
      return 'Redesign this YouTube thumbnail to significantly increase the contrast between the background and the foreground subject/text. Make any title text pop with a bold outline or shadow, and rebalance the color palette so the key details are still easy to read even as a tiny mobile thumbnail (about 120x67px). Keep the same overall theme and composition — just fix the low contrast.';
    }
    if (_brightness! < 60) {
      return 'This YouTube thumbnail looks too dark overall. Brighten it while keeping the same mood, and make sure the main subject and any text are clearly visible against the background — this matters most on a small mobile thumbnail. Keep the same theme and layout, just fix the exposure.';
    }
    if (_brightness! > 200) {
      return 'This YouTube thumbnail looks overexposed and washed out. Reduce the brightness slightly, add richer shadows and contrast so the subject stands out, and keep any text clearly legible. Keep the same theme and layout, just fix the exposure.';
    }
    return '';
  }

  Future<void> _openGeminiApp() async {
    final uri = Uri.parse('https://gemini.google.com/app');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (_) {}
  }

  Future<void> _handleCopyPrompt(String fullPrompt, String partialPrompt) async {
    if (_isUnlocked) {
      await Clipboard.setData(ClipboardData(text: fullPrompt));
      if (mounted) showToast(context, 'Prompt copied to clipboard', isSuccess: true);
    } else {
      await Clipboard.setData(ClipboardData(text: partialPrompt));
      if (mounted) showToast(context, 'Sample copied — upgrade to copy the full prompt', isError: false);
    }
  }

  Future<void> _handleGeminiTap(String fullPrompt) async {
    if (!_isUnlocked) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const DiamondStoreScreen()));
      return;
    }
    await Clipboard.setData(ClipboardData(text: fullPrompt));
    if (mounted) showToast(context, 'Prompt copied — opening Gemini…', isSuccess: true);
    await _openGeminiApp();
  }

  Widget _geminiFixCard() {
    final fullPrompt = _generateGeminiPrompt();
    if (fullPrompt.isEmpty) return const SizedBox.shrink();

    final words = fullPrompt.split(' ');
    final previewText = words.take(_previewWordCount).join(' ');
    final remainingText = words.length > _previewWordCount ? ' ${words.skip(_previewWordCount).join(' ')}' : '';
    final partialCopyText = previewText;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_fix_high_rounded, color: AppColors.purple, size: 18),
            const SizedBox(width: 6),
            const Text('Fix it with AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim),
              children: [
                TextSpan(text: previewText),
                if (remainingText.isNotEmpty)
                  WidgetSpan(
                    child: _isUnlocked
                        ? Text(remainingText, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim))
                        : ImageFiltered(
                            imageFilter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                            child: Text(remainingText, style: TextStyle(fontSize: 12.5, height: 1.4, color: context.surfaces.textDim)),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!_isUnlocked) ...[
            Text(
              context.tr('audit_prompt_locked_label'),
              style: const TextStyle(color: AppColors.purple, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _handleCopyPrompt(fullPrompt, partialCopyText),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text(context.tr('audit_copy_prompt_btn')),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _handleGeminiTap(fullPrompt),
                  child: Tooltip(
                    message: context.tr('audit_open_gemini_btn'),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Image.asset('assets/gemini_icon.png', width: 28, height: 28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mockupFrame() {
    final typedTitle = _titleCtrl.text.trim();
    final hasTitle = typedTitle.isNotEmpty;
    final title = hasTitle ? typedTitle : 'Your Video Title Here';
    switch (_tab) {
      case _MockupTab.instagram:
        return _phoneFrame(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: AppColors.purple),
                const SizedBox(width: 8),
                Text(context.tr('visual_your_channel_handle'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            AspectRatio(aspectRatio: 1, child: _imageBox()),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
            ),
          ]),
        );
      case _MockupTab.youtube:
        return _phoneFrame(
          child: Column(children: [
            AspectRatio(aspectRatio: 16 / 9, child: _imageBox()),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _channelAvatar(16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: hasTitle ? null : context.surfaces.textDim)),
                    const SizedBox(height: 3),
                    Text(_youtubeSubtitle, style: TextStyle(color: context.surfaces.textDim, fontSize: 11)),
                  ]),
                ),
              ]),
            ),
          ]),
        );
      case _MockupTab.facebook:
        return _phoneFrame(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const CircleAvatar(radius: 14, backgroundColor: AppColors.purple),
                const SizedBox(width: 8),
                Text(context.tr('visual_your_page'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Align(alignment: Alignment.centerLeft, child: Text(title, style: const TextStyle(fontSize: 12.5)))),
            const SizedBox(height: 8),
            AspectRatio(aspectRatio: 1.3, child: _imageBox()),
          ]),
        );
    }
  }

  Widget _phoneFrame({required Widget child}) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _imageBox() {
    if (_image == null) {
      return Container(color: context.surfaces.card2, child: const Center(child: Icon(Icons.image_outlined, size: 40)));
    }
    return Image.file(_image!, fit: BoxFit.cover, width: double.infinity);
  }

  // ⚠️ NEW: the "Analyze" / "Re-analyze" button. Only rendered once an
  // image is picked. Disabled while _analyzing is true (GradientButton's
  // own loading state already shows a spinner + blocks double-taps).
  Widget _analyzeButton() {
    if (_image == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: GradientButton(
        label: _hasResult ? context.tr('visual_reanalyze_btn') : context.tr('visual_analyze_btn'),
        icon: Icons.insights_rounded,
        loading: _analyzing,
        onPressed: _analyze,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('visual_analyzer_title'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              height: 140,
              decoration: BoxDecoration(border: Border.all(color: AppColors.purple, style: BorderStyle.solid), borderRadius: BorderRadius.circular(16)),
              child: _image == null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.add_photo_alternate_rounded, color: AppColors.purple, size: 30),
                        const SizedBox(height: 8),
                        Text(context.tr('visual_tap_to_pick'), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(_image!, fit: BoxFit.cover, width: double.infinity)),
                        // Small "change image" affordance so re-tapping the
                        // preview to pick a different file is still obvious
                        // now that tapping it no longer auto-analyzes.
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(999)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.sync_rounded, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(context.tr('visual_change_image'), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _titleCtrl, onChanged: (_) => setState(() {}), decoration: InputDecoration(hintText: context.tr('visual_preview_title_hint'))),
          const SizedBox(height: 20),
          _mockupFrame(),
          _analyzeButton(),
          if (_image != null) ...[
            const SizedBox(height: 24),
            Text(context.tr('visual_score_label'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (_analyzing)
              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: LoadingView())
            else if (_contrastScore != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.contrast_rounded, color: _scoreColor(_contrastScore!), size: 20),
                      const SizedBox(width: 8),
                      Text('${context.tr('visual_contrast_label')}: ${_contrastScore!.toStringAsFixed(0)}/100', style: TextStyle(fontWeight: FontWeight.w800, color: _scoreColor(_contrastScore!))),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(value: _contrastScore! / 100, minHeight: 6, backgroundColor: context.surfaces.border, valueColor: AlwaysStoppedAnimation(_scoreColor(_contrastScore!))),
                    ),
                    const SizedBox(height: 12),
                    Text(_readabilityNote(), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                  ],
                ),
              ),
              _geminiFixCard(),
            ] else
              // ⚠️ NEW: empty-state hint shown between picking the image
              // and tapping Analyze, so the screen doesn't look "stuck" or
              // broken while waiting for the user to tap the button above.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border.all(color: context.surfaces.border), borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  Icon(Icons.touch_app_rounded, color: context.surfaces.textDim, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(context.tr('visual_tap_analyze_hint'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5))),
                ]),
              ),
          ],
        ],
      ),
    );
  }
}