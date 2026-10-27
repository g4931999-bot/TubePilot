import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

/// Real, on-device thumbnail measurements (UPDATE14).
///
/// Everything here is computed from the thumbnail's ACTUAL pixels - no AI,
/// no random numbers, nothing uploaded anywhere. It is NOT a YouTube score;
/// the screens label it "measured on your device".
///
///  readability   = luminance contrast (std-dev of brightness)
///  colorBalance  = how close average brightness is to mid-tone
///  appeal        = average of colour vibrancy (saturation) and detail (edges)
///  composition   = how much of the edge detail sits in the central area
///  overall       = average of the four above
class ThumbMetrics {
  final int overall, appeal, readability, colorBalance, composition;
  final double brightness; // 0-255 mean luminance
  final double saturation; // 0-1 mean saturation
  final double contrast; // luminance std-dev
  final double centerShare; // share of edge energy in the centre (0-1)
  const ThumbMetrics({
    required this.overall,
    required this.appeal,
    required this.readability,
    required this.colorBalance,
    required this.composition,
    required this.brightness,
    required this.saturation,
    required this.contrast,
    required this.centerShare,
  });

  /// Suggestion string-keys that are TRUE for this image (each one is
  /// triggered by a measured number, never by a guess).
  List<String> suggestionKeys() {
    final out = <String>[];
    if (readability < 55) out.add('tm_sug_contrast');
    if (brightness < 85) out.add('tm_sug_dark');
    if (brightness > 185) out.add('tm_sug_bright');
    if (saturation < 0.25) out.add('tm_sug_saturation');
    if (composition < 45) out.add('tm_sug_composition');
    if (appeal < 45 && !out.contains('tm_sug_saturation')) out.add('tm_sug_detail');
    return out;
  }

  /// Short English fact lines (used inside the ChatGPT prompt).
  List<String> factLines() => [
        'Average brightness: ${brightness.round()}/255',
        'Contrast (brightness spread): ${contrast.round()}',
        'Colour saturation: ${(saturation * 100).round()}%',
        'Share of detail near the centre: ${(centerShare * 100).round()}%',
      ];
}

Future<Uint8List?> fetchImageBytes(String url) async {
  if (url.isEmpty) return null;
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
    if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) return res.bodyBytes;
  } catch (_) {}
  return null;
}

int _clamp100(double v) => v.isNaN ? 0 : v.clamp(0, 100).round();

Future<ThumbMetrics?> measureThumbnail(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width, h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null || w < 8 || h < 8) return null;
    final px = data.buffer.asUint8List();

    final lum = List<double>.filled(w * h, 0);
    double sumL = 0, sumS = 0;
    for (int i = 0; i < w * h; i++) {
      final r = px[i * 4], g = px[i * 4 + 1], b = px[i * 4 + 2];
      final l = 0.299 * r + 0.587 * g + 0.114 * b;
      lum[i] = l;
      sumL += l;
      final mx = math.max(r, math.max(g, b)).toDouble();
      final mn = math.min(r, math.min(g, b)).toDouble();
      sumS += mx == 0 ? 0 : (mx - mn) / mx;
    }
    final n = w * h;
    final mean = sumL / n;
    final sat = sumS / n;
    double v = 0;
    for (final l in lum) {
      v += (l - mean) * (l - mean);
    }
    final std = math.sqrt(v / n);

    // Edge energy (simple gradient), total + centre (middle 60% x 60%).
    double edgeAll = 0, edgeCenter = 0, gradSum = 0;
    final x0 = (w * 0.2).floor(), x1 = (w * 0.8).ceil();
    final y0 = (h * 0.2).floor(), y1 = (h * 0.8).ceil();
    for (int y = 0; y < h - 1; y++) {
      for (int x = 0; x < w - 1; x++) {
        final i = y * w + x;
        final g = (lum[i] - lum[i + 1]).abs() + (lum[i] - lum[i + w]).abs();
        gradSum += g;
        edgeAll += g;
        if (x >= x0 && x < x1 && y >= y0 && y < y1) edgeCenter += g;
      }
    }
    final avgGrad = gradSum / ((w - 1) * (h - 1));
    final centerShare = edgeAll == 0 ? 0.0 : edgeCenter / edgeAll;

    final readability = _clamp100(std / 70 * 100);
    final colorBalance = _clamp100(100 - (mean - 128).abs() / 128 * 100);
    final vibrancy = _clamp100(100 - (sat - 0.5).abs() / 0.5 * 100);
    final detail = _clamp100(avgGrad / 24 * 100);
    final appeal = ((vibrancy + detail) / 2).round();
    // centre area is 36% of the frame -> share 0.36 = evenly spread, 0.6+ = focused.
    final composition = _clamp100((centerShare - 0.25) / (0.65 - 0.25) * 100);
    final overall = ((appeal + readability + colorBalance + composition) / 4).round();

    return ThumbMetrics(
      overall: overall,
      appeal: appeal,
      readability: readability,
      colorBalance: colorBalance,
      composition: composition,
      brightness: mean,
      saturation: sat,
      contrast: std,
      centerShare: centerShare,
    );
  } catch (_) {
    return null;
  }
}