import 'dart:async';
import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../providers/language_provider.dart';
import '../widgets/common.dart';

/// ⚠️ NEW: Phone ke camera se seedha YouTube par live.
///
/// Flow: backend (POST /live-stream/start-camera) YouTube par broadcast + stream key banata hai
/// (limits + plan hours check karke) -> app camera/mic ko RTMP se seedha YouTube ko bhejti hai.
/// EC2 beech mein NAHI aata. Wahi rules lagte hain: 1 at a time, 1 ghanta gap,
/// 24 ghante mein max 3, aur plan ke hours kat-te hain.
///
/// Dhyan: live ke dauraan app khuli rehni chahiye (background mein camera Android band kar deta hai).
///
/// ⚠️ FIX (camera app mein dikh raha tha par YouTube par nahi): ab connect karne ke baad backend
/// ke through YouTube se pucha jata hai ki data SACH MEIN aa raha hai ya nahi (streamStatus == active).
/// Nahi aaya to dusre URL format (slash ke saath/bina, rtmp / rtmps) ek-ek karke try hote hain.
/// Kaun sa URL chala wo live screen par dikhta hai. Sab fail hone par live start hi nahi hoti
/// aur slot wapas mil jata hai.
class LiveCameraScreen extends StatefulWidget {
  /// Camera live chal rahi ho to true — LiveStreamScreen is flag se pehchanta hai ki
  /// server par dikhne wali camera session "adhoori" (app band hui thi) hai ya abhi chal rahi hai.
  static bool active = false;

  const LiveCameraScreen({super.key});
  @override
  State<LiveCameraScreen> createState() => _LiveCameraScreenState();
}

enum _CamStage { loading, error, ready, starting, live }

class _LiveCameraScreenState extends State<LiveCameraScreen> with WidgetsBindingObserver {
  ApiVideoLiveStreamController? _controller;
  final TextEditingController _titleCtrl = TextEditingController();

  _CamStage _stage = _CamStage.loading;
  String _errorText = '';
  bool _permanentlyDenied = false;

  LiveLimits _limits = const LiveLimits();
  int _waitSeconds = 0;
  Timer? _ticker;

  String? _streamId;
  String? _watchUrl;
  bool _isFreeTrial = false;
  int _secondsAllowed = 0;
  int _secondsElapsed = 0;
  bool _muted = false;
  bool _stopping = false;

  // YouTube connection ki asli sthiti
  bool _trying = false;        // connect/fallback chal raha hai — callbacks se session band mat karo
  bool _ytActive = false;      // YouTube ko data mil raha hai
  bool _polling = false;
  String? _rtmpError;          // library ka last error (callback se)
  String _connectInfo = '';    // user ko dikhane wala status / chala hua URL
  String? _ytHealth;           // YouTube stream health (good/ok/bad/noData)

  bool get _blocked => !_limits.canStart;

  /// Translation helper — async/callback ke andar bhi safe (widget hat chuka ho to key hi lauta deta hai).
  String _t(String key) => mounted ? context.tr(key) : key;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), _onTick);
    _initCamera();
    _refreshLimits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _titleCtrl.dispose();

    // App kill/screen destroy hone par bhi server session chhodna nahi hai.
    final id = _streamId;
    if (id != null && !_stopping) {
      ApiService.instance.stopLiveStream(id).catchError((_) => <String, dynamic>{});
    }
    LiveCameraScreen.active = false;
    WakelockPlus.disable();
    _controller?.stop();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------- lifecycle ----------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null) return;
    if (state == AppLifecycleState.paused) {
      if (_stage == _CamStage.live || _stage == _CamStage.starting) {
        // Android background mein camera chalne nahi deta — saaf tareeke se live band karo.
        _endSession(message: _t('live_cam_bg_stopped'), isError: true);
      } else {
        c.stopPreview();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_stage == _CamStage.ready) c.startPreview();
    }
  }

  // ---------------- timers / limits ----------------
  void _onTick(Timer _) {
    if (!mounted) return;
    var changed = false;
    var autoEnded = false;
    var waitDone = false;

    if (_stage == _CamStage.live) {
      _secondsElapsed++;
      changed = true;
      if (_secondsElapsed % 10 == 0) _pollYoutube();
      if (_secondsAllowed > 0 && _secondsElapsed >= _secondsAllowed) autoEnded = true;
    }
    if (_waitSeconds > 0) {
      _waitSeconds--;
      changed = true;
      if (_waitSeconds == 0 && _stage != _CamStage.live) waitDone = true;
    }

    if (changed) setState(() {});
    if (autoEnded) _endSession(message: _t('live_cam_time_over'));
    if (waitDone) _refreshLimits();
  }

  Future<void> _refreshLimits() async {
    try {
      final res = await ApiService.instance.startLiveStream(videoUrl: LiveLimits.checkToken, title: null);
      final limits = LiveLimits.fromJson(Map<String, dynamic>.from(res as Map));
      if (!mounted) return;
      setState(() {
        _limits = limits;
        _waitSeconds = limits.retryAfterSeconds;
      });
    } catch (_) {
      // Offline/temporary error: backend har haal mein rok dega.
    }
  }

  // ---------------- camera init ----------------
  Future<void> _initCamera() async {
    setState(() {
      _stage = _CamStage.loading;
      _errorText = '';
      _permanentlyDenied = false;
    });

    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _permanentlyDenied = cam.isPermanentlyDenied || mic.isPermanentlyDenied;
        _errorText = _t('live_cam_perm_needed');
        _stage = _CamStage.error;
      });
      return;
    }

    try {
      final controller = ApiVideoLiveStreamController(
        initialAudioConfig: AudioConfig(),
        initialVideoConfig: VideoConfig.withDefaultBitrate(),
        onConnectionSuccess: () => debugPrint('[CameraLive] RTMP connection success'),
        onConnectionFailed: (String error) {
          debugPrint('[CameraLive] RTMP connection failed: $error');
          _rtmpError = error;
          if (!_trying) _handleConnectionProblem(_t('live_cam_connect_failed').replaceAll('%1', error));
        },
        onDisconnection: () {
          debugPrint('[CameraLive] RTMP disconnected');
          if (_trying) return; // fallback mein hum khud stopStreaming bulate hain
          _handleConnectionProblem(_t('live_cam_conn_lost'));
        },
        onError: (Exception e) {
          debugPrint('[CameraLive] error: $e');
          _rtmpError = e.toString();
          if (!_trying) _handleConnectionProblem(_t('live_cam_error').replaceAll('%1', '$e'));
        },
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _stage = _CamStage.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = _t('live_cam_start_failed').replaceAll('%1', '$e');
        _stage = _CamStage.error;
      });
    }
  }

  // ---------------- go live / stop ----------------
  Future<void> _goLive() async {
    final controller = _controller;
    if (controller == null || _blocked || _stage != _CamStage.ready) return;
    setState(() {
      _stage = _CamStage.starting;
      _ytActive = false;
      _ytHealth = null;
      _rtmpError = null;
      _connectInfo = _t('live_cam_session_creating');
    });

    String? createdStreamId;
    try {
      final title = _titleCtrl.text.trim();
      final res = await ApiService.instance.startCameraLive(title: title.isEmpty ? null : title);

      createdStreamId = res['streamId']?.toString();
      final rtmpUrl = res['rtmpUrl']?.toString();
      final rtmpsUrl = res['rtmpsUrl']?.toString();
      final streamKey = res['streamKey']?.toString();
      if (createdStreamId == null || rtmpUrl == null || streamKey == null) {
        throw ApiException(_t('live_cam_no_details'));
      }
      _streamId = createdStreamId; // ab se koi bhi band-karne wala raasta server session bhi band karega

      final usedUrl = await _connectToYouTube(
        controller,
        streamId: createdStreamId,
        key: streamKey,
        urls: [rtmpUrl, rtmpsUrl],
      );
      if (usedUrl == null) {
        throw ApiException(
          _rtmpError != null
              ? _t('live_cam_no_data_detail').replaceAll('%1', _rtmpError!)
              : _t('live_cam_no_data_nodetail'),
        );
      }

      if (!mounted) return;
      LiveCameraScreen.active = true;
      WakelockPlus.enable(); // live ke dauraan screen band na ho
      setState(() {
        _watchUrl = res['watchUrl']?.toString();
        _isFreeTrial = res['isFreeTrial'] == true;
        _secondsAllowed = (res['secondsAllowed'] as num?)?.toInt() ?? 0;
        _secondsElapsed = 0;
        _ytActive = true;
        _connectInfo = usedUrl;
        _stage = _CamStage.live;
      });
      showToast(context, context.tr(_isFreeTrial ? 'live_cam_trial_started' : 'live_cam_started'), isSuccess: true);
      _refreshLimits();
    } catch (e) {
      // Server par session ban chuka ho to release karo (kabhi live nahi hua to slot wapas milta hai).
      if (createdStreamId != null) {
        try {
          await controller.stopStreaming();
        } catch (_) {}
        try {
          await ApiService.instance.stopLiveStream(createdStreamId);
        } catch (_) {}
        _streamId = null;
      }
      if (!mounted) return;
      setState(() {
        _stage = _CamStage.ready;
        _connectInfo = '';
      });
      showApiError(context, e);
      _refreshLimits();
    }
  }

  /// URL ke alag-alag format ek-ek karke try karta hai (library "url/streamKey" jodti hai ya
  /// "urlstreamKey" — pakka nahi, isliye dono). Har try ke baad backend se YouTube ki sthiti
  /// poochta hai. Jo URL chala wo return hota hai, koi nahi chala to null.
  Future<String?> _connectToYouTube(
    ApiVideoLiveStreamController controller, {
    required String streamId,
    required String key,
    required List<String?> urls,
  }) async {
    final candidates = <String>[];
    for (final u in urls) {
      if (u == null || u.isEmpty) continue;
      final base = u.replaceAll(RegExp(r'/+$'), '');
      candidates.add(base);
      candidates.add('$base/');
    }

    _trying = true;
    try {
      for (var i = 0; i < candidates.length; i++) {
        final url = candidates[i];
        _rtmpError = null;
        if (mounted) setState(() => _connectInfo = _t('live_cam_connecting').replaceAll('%1', '${i + 1}').replaceAll('%2', '${candidates.length}'));
        debugPrint('[CameraLive] try $url');

        try {
          await controller.startStreaming(streamKey: key, url: url);
        } catch (e) {
          _rtmpError = e.toString();
        }

        if (_rtmpError == null && await _waitForYoutubeData(streamId, 16)) {
          debugPrint('[CameraLive] YouTube ko data mil gaya via $url');
          return url;
        }

        debugPrint('[CameraLive] $url se data nahi mila (error: $_rtmpError)');
        try {
          await controller.stopStreaming();
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 700));
      }
      return null;
    } finally {
      _trying = false;
    }
  }

  /// Backend (jo YouTube se poochta hai) se confirm: streamStatus == active matlab data aa raha hai.
  Future<bool> _waitForYoutubeData(String streamId, int seconds) async {
    for (var waited = 0; waited < seconds; waited += 2) {
      await Future.delayed(const Duration(seconds: 2));
      if (_rtmpError != null) return false; // library ne hi error de diya
      try {
        final res = await ApiService.instance.getLiveStreamStatus(streamId);
        if (res['streamStatus'] == 'active') {
          _ytHealth = res['health']?.toString();
          return true;
        }
      } catch (_) {
        // status check fail — agli baar phir try
      }
    }
    return false;
  }

  /// Live ke dauraan har 10 sec par YouTube ki sthiti (data aa raha hai? health kaisi hai?).
  Future<void> _pollYoutube() async {
    final id = _streamId;
    if (id == null || _polling || _stage != _CamStage.live) return;
    _polling = true;
    try {
      final res = await ApiService.instance.getLiveStreamStatus(id);
      if (!mounted) return;
      setState(() {
        _ytActive = res['streamStatus'] == 'active';
        _ytHealth = res['health']?.toString();
      });
    } catch (_) {
      // ignore
    } finally {
      _polling = false;
    }
  }

  void _handleConnectionProblem(String message) {
    if (!mounted || _stopping) return;
    if (_stage == _CamStage.live || _stage == _CamStage.starting) {
      _endSession(message: message, isError: true);
    }
  }

  Future<void> _endSession({String? message, bool isError = false}) async {
    if (_stopping) return;
    _stopping = true;
    final id = _streamId;

    try {
      await _controller?.stopStreaming();
    } catch (_) {}
    if (id != null) {
      try {
        await ApiService.instance.stopLiveStream(id);
      } catch (_) {}
    }
    LiveCameraScreen.active = false;
    WakelockPlus.disable();

    if (!mounted) return;
    setState(() {
      _stage = _CamStage.ready;
      _streamId = null;
      _watchUrl = null;
      _secondsElapsed = 0;
      _secondsAllowed = 0;
      _ytActive = false;
      _ytHealth = null;
      _connectInfo = '';
      _stopping = false;
    });
    if (message != null) showToast(context, message, isError: isError, isSuccess: !isError);
    _refreshLimits();
  }

  Future<bool> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('live_cam_stop_title')),
        content: Text(ctx.tr('live_cam_stop_body')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('live_cam_no'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('live_cam_stop_confirm'), style: const TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _switchCamera() async {
    try {
      await _controller?.switchCamera();
    } catch (e) {
      if (mounted) showToast(context, context.tr('live_cam_switch_failed'), isError: true);
    }
  }

  Future<void> _toggleMute() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.toggleMute();
      final muted = await c.isMuted;
      if (mounted) setState(() => _muted = muted);
    } catch (_) {}
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final busy = _stage == _CamStage.live || _stage == _CamStage.starting;

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_stage == _CamStage.starting) return; // start ke beech mein bahar nahi
        final stop = await _confirmStop();
        if (!stop) return;
        await _endSession(message: _t('live_cam_stopped'));
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('live_cam_title'))),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _CamStage.loading:
        return const LoadingView();
      case _CamStage.error:
        return _buildError();
      case _CamStage.ready:
      case _CamStage.starting:
        return _buildReady();
      case _CamStage.live:
        return _buildLive();
    }
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_rounded, size: 44, color: context.surfaces.textDim),
            const SizedBox(height: 12),
            Text(_errorText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 18),
            if (_permanentlyDenied)
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: Text(context.tr('live_cam_open_settings')),
              )
            else
              ElevatedButton.icon(
                onPressed: _initCamera,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.tr('live_cam_retry')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _preview({required Widget overlay}) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          ApiVideoCameraPreview(controller: c, fit: BoxFit.cover),
          overlay,
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap, {Color? color}) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color ?? Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildReady() {
    final starting = _stage == _CamStage.starting;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LiveLimitBanner(limits: _limits, waitSeconds: _waitSeconds),
              const SizedBox(height: 14),
              AspectRatio(
                aspectRatio: 3 / 4,
                child: _preview(
                  overlay: Positioned(
                    top: 10,
                    right: 10,
                    child: _roundButton(Icons.cameraswitch_rounded, _switchCamera),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _titleCtrl,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: context.tr('live_stream_title_label'),
                  hintText: context.tr('live_cam_title_hint'),
                ),
              ),
              if (starting && _connectInfo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_connectInfo, style: const TextStyle(color: AppColors.purple, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              Text(
                context.tr('live_cam_note'),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: context.surfaces.border)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (starting || _blocked) ? null : _goLive,
              icon: starting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.podcasts_rounded, size: 18),
              label: Text(context.tr(starting ? 'live_btn_starting' : 'live_btn_go_live')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLive() {
    final remaining = (_secondsAllowed - _secondsElapsed).clamp(0, _secondsAllowed);

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _preview(
              overlay: Stack(
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(999)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: _ytActive ? Colors.redAccent : Colors.orange, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _ytActive ? 'LIVE  ${formatCountdown(_secondsElapsed)}' : context.tr('live_cam_no_data_badge'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Column(
                      children: [
                        _roundButton(Icons.cameraswitch_rounded, _switchCamera),
                        const SizedBox(height: 8),
                        _roundButton(_muted ? Icons.mic_off_rounded : Icons.mic_rounded, _toggleMute,
                            color: _muted ? Colors.redAccent : Colors.white),
                        if (_watchUrl != null) ...[
                          const SizedBox(height: 8),
                          _roundButton(
                            Icons.open_in_new_rounded,
                            () => launchUrl(Uri.parse(_watchUrl!), mode: LaunchMode.externalApplication),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(top: BorderSide(color: context.surfaces.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('live_remaining').replaceAll('%1', formatCountdown(remaining)) +
                    (_isFreeTrial ? context.tr('live_free_trial_suffix') : '') +
                    (_waitSeconds > 0 ? context.tr('live_cam_next_short').replaceAll('%1', formatCountdown(_waitSeconds)) : ''),
                style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5),
              ),
              if (_ytHealth != null || _connectInfo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    context.tr('live_cam_health').replaceAll('%1', _ytHealth ?? '-').replaceAll('%2', _connectInfo),
                    style: TextStyle(color: context.surfaces.textDim, fontSize: 10.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
                  onPressed: _stopping ? null : () => _endSession(message: _t('live_cam_stopped')),
                  icon: const Icon(Icons.stop_circle_rounded, size: 18),
                  label: Text(context.tr('live_cam_btn_stop')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}