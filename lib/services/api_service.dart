import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  final String? code;
  ApiException(this.message, {this.status, this.code});
  @override
  String toString() => message;
}

/// MultipartRequest jo upload ke dauraan bytes gin-ti hai (progress bar ke liye).
/// finalize() ki stream ko lazily transform karta hai, isliye back-pressure bana rehta hai —
/// 2GB file memory mein nahi bharti, aur progress asli network speed ke hisaab se chalta hai.
class _ProgressMultipartRequest extends http.MultipartRequest {
  final void Function(int sent, int total)? onProgress;
  _ProgressMultipartRequest(String method, Uri url, {this.onProgress}) : super(method, url);

  @override
  http.ByteStream finalize() {
    final byteStream = super.finalize();
    final total = contentLength;
    var sent = 0;
    final transformer = StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (data, sink) {
        sent += data.length;
        onProgress?.call(sent, total);
        sink.add(data);
      },
    );
    return http.ByteStream(byteStream.transform(transformer));
  }
}

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool retry = true,
  }) async {
    final token = await StorageService.getAccessToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    http.Response res;
    switch (method) {
      case 'POST':
        res = await http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PATCH':
        res = await http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        break;
      default:
        res = await http.get(uri, headers: headers);
    }

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (res.statusCode == 401 && data['code'] == 'TOKEN_EXPIRED' && retry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) return _request(path, method: method, body: body, retry: false);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(data['message'] ?? 'Request failed', status: res.statusCode, code: data['code']);
    }
    return data;
  }

  Future<bool> _refreshAccessToken() async {
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) return false;
      final res = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        await StorageService.setAccessToken(data['accessToken']);
        return true;
      }
    } catch (_) {}
    await StorageService.clearTokens();
    return false;
  }

  /// Multipart upload (video/thumbnail/screenshot files + form fields)
  Future<Map<String, dynamic>> uploadMultipart(
    String path, {
    required Map<String, String> fields,
    required List<http.MultipartFile> files,
    bool retry = true,
    String method = 'POST',
  }) async {
    final token = await StorageService.getAccessToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final request = http.MultipartRequest(method, uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    request.files.addAll(files);

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (res.statusCode == 401 && data['code'] == 'TOKEN_EXPIRED' && retry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) return uploadMultipart(path, fields: fields, files: files, retry: false, method: method);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(data['message'] ?? 'Upload failed', status: res.statusCode, code: data['code']);
    }
    return data;
  }

  /// Ek file upload karta hai aur [onProgress] se (sent, total) bytes batata hai.
  /// Token expire hone par naya token lekar file dobara bhejta hai (MultipartFile ek baar hi
  /// use ho sakti hai, isliye retry mein file path se naya object banta hai).
  Future<Map<String, dynamic>> _uploadFileWithProgress(
    String path, {
    required String fieldName,
    required String filePath,
    required http.MediaType contentType,
    void Function(int sent, int total)? onProgress,
    bool retry = true,
  }) async {
    final token = await StorageService.getAccessToken();
    final request = _ProgressMultipartRequest(
      'POST',
      Uri.parse('${AppConfig.apiBaseUrl}$path'),
      onProgress: onProgress,
    );
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath, contentType: contentType));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    Map<String, dynamic> data = {};
    if (res.body.isNotEmpty) {
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } catch (_) {}
    }

    if (res.statusCode == 401 && data['code'] == 'TOKEN_EXPIRED' && retry) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        return _uploadFileWithProgress(
          path,
          fieldName: fieldName,
          filePath: filePath,
          contentType: contentType,
          onProgress: onProgress,
          retry: false,
        );
      }
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(data['message'] ?? 'Upload failed', status: res.statusCode, code: data['code']);
    }
    return data;
  }

  // ---------------- Auth ----------------
  // ------ POST /api/auth/signup ------ //
  Future<Map<String, dynamic>> signup({required String name, required String email, required String password}) =>
      _request('/auth/signup', method: 'POST', body: {'name': name, 'email': email, 'password': password});

  // ------ POST /api/auth/login ------ //
  Future<Map<String, dynamic>> login({required String email, required String password}) =>
      _request('/auth/login', method: 'POST', body: {'email': email, 'password': password});

  // ------ POST /api/auth/google ------ //
  Future<Map<String, dynamic>> googleLogin(String idToken) =>
      _request('/auth/google', method: 'POST', body: {'idToken': idToken});

  // ------ POST /api/auth/logout ------ //
  Future<Map<String, dynamic>> logout() => _request('/auth/logout', method: 'POST');

  // ------ POST /api/auth/forgot-password ------ //
  Future<Map<String, dynamic>> forgotPassword(String email) =>
      _request('/auth/forgot-password', method: 'POST', body: {'email': email});

  // ------ GET /api/auth/me ------ //
  Future<Map<String, dynamic>> me() => _request('/auth/me');

  // ------ POST /api/auth/setup-username ------ //
  Future<Map<String, dynamic>> setupUsername({required String username, required String language, String? avatar}) =>
      _request('/auth/setup-username', method: 'POST', body: {
        'username': username,
        'language': language,
        if (avatar != null) 'avatar': avatar,
      });

  // ------ POST /api/auth/apply-referral ------ //
  Future<Map<String, dynamic>> applyReferralCode(String referralCode) =>
      _request('/auth/apply-referral', method: 'POST', body: {'referralCode': referralCode});

  // ------ DELETE /api/auth/delete-account ------ //
  Future<Map<String, dynamic>> deleteMyAccount() => _request('/auth/delete-account', method: 'DELETE');

  // ---------------- Dashboard ----------------
  // ------ GET /api/dashboard ------ //
  Future<Map<String, dynamic>> dashboard() => _request('/dashboard');

  // ---------------- YouTube (backend/routes/youtube.js) ----------------
  // ------ GET /api/youtube/oauth/url ------ //
  Future<Map<String, dynamic>> getYoutubeOAuthUrl() => _request('/youtube/oauth/url?platform=mobile');
  // ------ GET /api/youtube/channel ------ //
  Future<Map<String, dynamic>> getYoutubeChannel() => _request('/youtube/channel');
  // ------ DELETE /api/youtube/disconnect ------ //
  Future<Map<String, dynamic>> disconnectYoutube() => _request('/youtube/disconnect', method: 'DELETE');

  // "Apply to Video" reaching already-published channel videos + "My Videos" screen —
  // real channel videos straight from YouTube, not just TubePilot's own queued uploads.
  // ------ GET /api/youtube/my-videos ------ //
  // `max` (default 25, backend caps at 100) - SEO / thumbnail screens ask for 100.
  Future<Map<String, dynamic>> getMyYoutubeVideos({int max = 25}) => _request('/youtube/my-videos?max=$max');

  // ------ PATCH /api/youtube/my-videos/:videoId ------ //
  Future<Map<String, dynamic>> updateYoutubeVideoMetadata(
    String videoId, {
    String? title,
    String? description,
    List<String>? tags,
  }) =>
      _request('/youtube/my-videos/$videoId', method: 'PATCH', body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
      });

  // ------ PATCH /api/youtube/my-videos/:videoId/thumbnail ------ //
  Future<Map<String, dynamic>> updateYoutubeThumbnail(String videoId, String thumbnailPath) async {
    final mime = _lookupMimeOrDefault(thumbnailPath, 'image/jpeg');
    final file = await http.MultipartFile.fromPath('thumbnail', thumbnailPath, contentType: mime);
    return uploadMultipart('/youtube/my-videos/$videoId/thumbnail', method: 'PATCH', fields: {}, files: [file]);
  }

  // ------ DELETE /api/youtube/my-videos/:videoId ------ //
  Future<Map<String, dynamic>> deleteYoutubeOnlyVideo(String videoId) =>
      _request('/youtube/my-videos/$videoId', method: 'DELETE');

  // ---------------- Meta (Facebook + Instagram) ----------------
  // One OAuth flow + one status check covers BOTH platforms.
  // ------ GET /api/meta/oauth/url ------ //
  Future<Map<String, dynamic>> getMetaOAuthUrl() => _request('/meta/oauth/url?platform=mobile');
  // ------ GET /api/meta/status ------ //
  Future<Map<String, dynamic>> getMetaStatus() => _request('/meta/status');
  // ------ GET /api/meta/pages ------ //
  Future<Map<String, dynamic>> getMetaPendingPages() => _request('/meta/pages');
  // ------ PATCH /api/meta/select-page ------ //
  Future<Map<String, dynamic>> selectMetaPage(String pageId) =>
      _request('/meta/select-page', method: 'PATCH', body: {'pageId': pageId});
  // ------ DELETE /api/meta/facebook/disconnect ------ //
  Future<Map<String, dynamic>> disconnectFacebook() => _request('/meta/facebook/disconnect', method: 'DELETE');

  // ---------------- Videos (backend/routes/video.js — multi-platform) ----------------
  // ------ POST /api/videos/upload ------ //
  Future<Map<String, dynamic>> uploadVideo({
    required String videoPath,
    String? thumbnailPath,
    List<String>? mediaPaths, // Instagram/Facebook carousel — additional images
    required List<String> platforms,
    String? postType, // 'video' | 'reel' | 'carousel' | 'post'
    Map<String, dynamic>? youtube,
    Map<String, dynamic>? facebook,
    Map<String, dynamic>? instagram,
    bool autoSlot = false, // scheduled upload, let the server pick the best time (needs Auto-Slotting ON)
  }) async {
    final videoMime = _lookupMimeOrDefault(videoPath, 'video/mp4');
    final files = [
      await http.MultipartFile.fromPath('video', videoPath, contentType: videoMime),
    ];
    if (thumbnailPath != null) {
      final thumbMime = _lookupMimeOrDefault(thumbnailPath, 'image/jpeg');
      files.add(await http.MultipartFile.fromPath('thumbnail', thumbnailPath, contentType: thumbMime));
    }

    final fields = <String, String>{
      'platforms': jsonEncode(platforms),
      if (postType != null) 'postType': postType,
      if (youtube != null) 'youtube': jsonEncode(youtube),
      if (facebook != null) 'facebook': jsonEncode(facebook),
      if (instagram != null) 'instagram': jsonEncode(instagram),
      if (autoSlot) 'autoSlot': 'true',
    };

    return uploadMultipart('/videos/upload', fields: fields, files: files);
  }

  // ------ POST /api/videos/bulk-upload ------ //
  /// up to 30 files in one request, backend auto-slots them across days
  /// (today skipped, plan's daily cap applied). [items] is a per-file
  /// metadata list, index-aligned with [videoPaths].
  Future<Map<String, dynamic>> bulkUploadVideos({
    required List<String> videoPaths,
    required List<String> platforms,
    String? postType,
    List<Map<String, dynamic>>? items,
    String? preferredTime, // 'HH:mm', defaults to 10:00 on the backend
    bool autoSlot = false,
  }) async {
    final files = <http.MultipartFile>[];
    for (final path in videoPaths) {
      final mime = _lookupMimeOrDefault(path, 'video/mp4');
      files.add(await http.MultipartFile.fromPath('videos', path, contentType: mime));
    }

    final fields = <String, String>{
      'platforms': jsonEncode(platforms),
      if (postType != null) 'postType': postType,
      if (items != null) 'items': jsonEncode(items),
      if (preferredTime != null) 'preferredTime': preferredTime,
      if (autoSlot) 'autoSlot': 'true',
    };

    return uploadMultipart('/videos/bulk-upload', fields: fields, files: files);
  }

  // ------ GET / PATCH /api/videos/auto-slotting ------ //
  // GET -> { enabled, nextSlot (ISO|null), videosUsed, reason }
  Future<Map<String, dynamic>> getAutoSlotting() => _request('/videos/auto-slotting');
  Future<Map<String, dynamic>> setAutoSlotting(bool enabled) =>
      _request('/videos/auto-slotting', method: 'PATCH', body: {'enabled': enabled});

  // "My Videos" screen: single combined list (TubePilot DB records + real live YouTube videos).
  // MUST be called as its own path — do not confuse with listVideos() below.
  // ------ GET /api/videos/library ------ //
  Future<Map<String, dynamic>> getVideoLibrary() => _request('/videos/library');

  // ------ GET /api/videos ------ //
  Future<Map<String, dynamic>> listVideos({String? status}) =>
      _request('/videos${status != null ? '?status=$status' : ''}');
  // ------ GET /api/videos/:id ------ //
  Future<Map<String, dynamic>> getVideo(String id) => _request('/videos/$id');
  // ------ PATCH /api/videos/:id/schedule/:platform ------ //
  Future<Map<String, dynamic>> scheduleVideoPlatform(String id, String platform, String scheduledAt) =>
      _request('/videos/$id/schedule/$platform', method: 'PATCH', body: {'scheduledAt': scheduledAt});
  // ------ DELETE /api/videos/:id ------ //
  Future<Map<String, dynamic>> cancelVideo(String id) => _request('/videos/$id', method: 'DELETE');
  // ------ PATCH /api/videos/:id/metadata ------ //
  Future<Map<String, dynamic>> updateVideoMetadata(
    String id, {
    required String platform,
    String? title,
    String? description,
    String? caption,
    String? hashtags,
    String? tags,
  }) =>
      _request('/videos/$id/metadata', method: 'PATCH', body: {
        'platform': platform,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (caption != null) 'caption': caption,
        if (hashtags != null) 'hashtags': hashtags,
        if (tags != null) 'tags': tags,
      });

  // ------ PATCH /api/videos/:id/thumbnail ------ //
  Future<Map<String, dynamic>> updateDbVideoThumbnail(String id, String thumbnailPath) async {
    final mime = _lookupMimeOrDefault(thumbnailPath, 'image/jpeg');
    final file = await http.MultipartFile.fromPath('thumbnail', thumbnailPath, contentType: mime);
    return uploadMultipart('/videos/$id/thumbnail', method: 'PATCH', fields: {}, files: [file]);
  }

  // ---------------- Diamonds (PayU) ----------------
  // Flow:
  //   1. createPayuOrder()  — backend creates a pending order, returns `payu` params
  //                           (key, txnid, amount, surl/furl ...) for the PayU Flutter SDK.
  //   2. payuHash()         — the SDK asks for hashes; backend signs them with the secret salt
  //                           (only for this user's own pending order, exact amount).
  //   3. verifyPayuPayment()— after checkout closes; backend re-confirms directly with PayU's
  //                           server before crediting diamonds — never trust the SDK alone.
  // ------ GET /api/diamonds/packages ------ //
  Future<Map<String, dynamic>> getDiamondPackages() => _request('/diamonds/packages');

  // ------ POST /api/diamonds/create-order ------ //
  Future<Map<String, dynamic>> createPayuOrder(int diamondPackage) =>
      _request('/diamonds/create-order', method: 'POST', body: {'diamondPackage': diamondPackage});

  // ------ POST /api/diamonds/verify-payment ------ //
  Future<Map<String, dynamic>> verifyPayuPayment(String orderId) =>
      _request('/diamonds/verify-payment', method: 'POST', body: {'orderId': orderId});

  // ------ POST /api/diamonds/payu/hash ------ //
  Future<Map<String, dynamic>> payuHash({
    required String hashName,
    required String hashString,
    String? hashType,
    String? postSalt,
  }) =>
      _request('/diamonds/payu/hash', method: 'POST', body: {
        'hashName': hashName,
        'hashString': hashString,
        if (hashType != null) 'hashType': hashType,
        if (postSalt != null) 'postSalt': postSalt,
      });

  // Old names kept so cashfree_checkout.dart / Live Plans (still on Cashfree) keep compiling.
  Future<Map<String, dynamic>> createCashfreeOrder(int diamondPackage) => createPayuOrder(diamondPackage);
  Future<Map<String, dynamic>> verifyCashfreePayment(String orderId) => verifyPayuPayment(orderId);

  // ------ GET /api/diamonds/my-requests ------ //
  Future<Map<String, dynamic>> myPurchaseRequests() => _request('/diamonds/my-requests');

  // ---------------- Live Streaming Plans (Day Pass / Month Pass) ----------------
  // ------ GET /api/live-plans ------ //
  Future<Map<String, dynamic>> getLivePlans() => _request('/live-plans');

  // ------ POST /api/live-plans/create-order ------ //
  Future<Map<String, dynamic>> createLivePlanOrder({required String category, required String planName}) =>
      _request('/live-plans/create-order', method: 'POST', body: {'category': category, 'planName': planName});

  // ------ POST /api/live-plans/verify-payment ------ //
  Future<Map<String, dynamic>> verifyLivePlanPayment(String orderId) =>
      _request('/live-plans/verify-payment', method: 'POST', body: {'orderId': orderId});

  // ---------------- Live Streaming (upload + start/stop/status) ----------------
  // ------ POST /api/live-stream/upload-video ------ //
  Future<Map<String, dynamic>> uploadLiveVideo(
    String videoPath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    final mime = _lookupMimeOrDefault(videoPath, 'video/mp4');
    return _uploadFileWithProgress(
      '/live-stream/upload-video',
      fieldName: 'video',
      filePath: videoPath,
      contentType: mime,
      onProgress: onProgress,
    );
  }

  // ------ POST /api/live-stream/start ------ //
  Future<Map<String, dynamic>> startLiveStream({required String videoUrl, String? title, String? description}) =>
      _request('/live-stream/start', method: 'POST', body: {
        'videoUrl': videoUrl,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      });

  // ------ POST /api/live-stream/start-camera ------ //
  // Phone camera se live. Response: { streamId, rtmpUrl, streamKey, watchUrl, secondsAllowed, isFreeTrial, ... }
  Future<Map<String, dynamic>> startCameraLive({String? title, String? description}) =>
      _request('/live-stream/start-camera', method: 'POST', body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      });

  // ------ POST /api/live-stream/stop ------ //
  Future<Map<String, dynamic>> stopLiveStream(String streamId) =>
      _request('/live-stream/stop', method: 'POST', body: {'streamId': streamId});

  // ------ GET /api/live-stream/status/:streamId ------ //
  Future<Map<String, dynamic>> getLiveStreamStatus(String streamId) => _request('/live-stream/status/$streamId');

  // ---------------- Wallet ----------------
  // ------ GET /api/wallet ------ //
  Future<Map<String, dynamic>> getWallet() => _request('/wallet');

  // Real auto-refund history (days = 7 | 30 | 90).
  Future<Map<String, dynamic>> getRefundLogs({int days = 30}) => _request('/wallet/refunds?days=$days');

  // ---------------- AI (platform-aware) ----------------
  // ------ POST /api/ai/title ------ //
  Future<Map<String, dynamic>> aiTitle(String topic) => _request('/ai/title', method: 'POST', body: {'topic': topic});
  // ------ POST /api/ai/title-options ------ //
  Future<Map<String, dynamic>> aiTitleOptions(String topic, {int count = 5}) =>
      _request('/ai/title-options', method: 'POST', body: {'topic': topic, 'count': count});
  // ------ POST /api/ai/description ------ //
  Future<Map<String, dynamic>> aiDescription(String topic) =>
      _request('/ai/description', method: 'POST', body: {'topic': topic});
  // ------ POST /api/ai/description-options ------ //
  Future<Map<String, dynamic>> aiDescriptionOptions(String topic, {int count = 4}) =>
      _request('/ai/description-options', method: 'POST', body: {'topic': topic, 'count': count});
  // ------ POST /api/ai/tags ------ //
  Future<Map<String, dynamic>> aiTags(String topic) => _request('/ai/tags', method: 'POST', body: {'topic': topic});
  // ------ POST /api/ai/caption ------ //
  Future<Map<String, dynamic>> aiCaption(String topic, String platform) =>
      _request('/ai/caption', method: 'POST', body: {'topic': topic, 'platform': platform});
  // ------ POST /api/ai/hashtags ------ //
  Future<Map<String, dynamic>> aiHashtags(String topic, String platform) =>
      _request('/ai/hashtags', method: 'POST', body: {'topic': topic, 'platform': platform});
  // ------ POST /api/ai/ideas ------ //
  Future<Map<String, dynamic>> aiIdeas({required String niche, String platform = 'youtube', int count = 5}) =>
      _request('/ai/ideas', method: 'POST', body: {'niche': niche, 'platform': platform, 'count': count});
  // ------ POST /api/ai/seo-score ------ //
  Future<Map<String, dynamic>> aiSeoScore({
    required String title,
    String? description,
    List<String>? tags,
    String platform = 'youtube',
  }) =>
      _request('/ai/seo-score', method: 'POST', body: {
        'title': title,
        if (description != null) 'description': description,
        if (tags != null) 'tags': tags,
        'platform': platform,
      });

  // ---------------- Analytics: Competitors & Audit (backend/routes/analytics.js) ----------------
  // ------ GET /api/analytics/competitors ------ //
  Future<Map<String, dynamic>> listCompetitors() => _request('/analytics/competitors');

  /// Live channel-name search for the Competitor Radar "add competitor" autocomplete.
  // ------ GET /api/analytics/competitors/search ------ //
  Future<Map<String, dynamic>> searchCompetitors(String query) =>
      _request('/analytics/competitors/search?q=${Uri.encodeQueryComponent(query)}');

  // ------ POST /api/analytics/competitors ------ //
  Future<Map<String, dynamic>> addCompetitor({String? channelId, String? handle, String? label}) =>
      _request('/analytics/competitors', method: 'POST', body: {
        if (channelId != null) 'channelId': channelId,
        if (handle != null) 'handle': handle,
        if (label != null) 'label': label,
      });
  // ------ DELETE /api/analytics/competitors/:id ------ //
  Future<Map<String, dynamic>> deleteCompetitor(String id) =>
      _request('/analytics/competitors/$id', method: 'DELETE');

  // ------ GET /api/analytics/competitors/dashboard ------ //
  Future<Map<String, dynamic>> getCompetitorDashboard() =>
      _request('/analytics/competitors/dashboard');

  // ------ GET /api/analytics/competitors/:id ------ //
  Future<Map<String, dynamic>> getCompetitorDetail(String id) =>
      _request('/analytics/competitors/$id');

  // ------ GET /api/analytics/competitors/videos?sort= (or /:id/videos) ------ //
  Future<Map<String, dynamic>> getCompetitorVideos({String? competitorId, String sort = 'most_viewed', int limit = 30}) {
    final base = competitorId == null
        ? '/analytics/competitors/videos'
        : '/analytics/competitors/$competitorId/videos';
    return _request('$base?sort=$sort&limit=$limit');
  }

  // ------ GET /api/analytics/competitors/video/:videoId (description, tags) ------ //
  Future<Map<String, dynamic>> getCompetitorVideoDetails(String videoId) =>
      _request('/analytics/competitors/video/$videoId');
  // ------ GET /api/analytics/audit ------ //
  Future<Map<String, dynamic>> getChannelAudit() => _request('/analytics/audit');

  // ---------------- Milestones ----------------
  // ------ GET /api/milestones/pending ------ //
  Future<Map<String, dynamic>> getPendingMilestone() => _request('/milestones/pending');
  // ------ POST /api/milestones/:id/seen ------ //
  Future<Map<String, dynamic>> markMilestoneSeen(String id) =>
      _request('/milestones/$id/seen', method: 'POST');

  // ---------------- Notifications ----------------
  // ------ GET /api/notifications ------ //
  Future<Map<String, dynamic>> getNotifications() => _request('/notifications');
  // ------ PATCH /api/notifications/:id/read ------ //
  Future<Map<String, dynamic>> markNotificationRead(String id) =>
      _request('/notifications/$id/read', method: 'PATCH');
  // ------ PATCH /api/notifications/read-all ------ //
  Future<Map<String, dynamic>> markAllNotificationsRead() => _request('/notifications/read-all', method: 'PATCH');
  // ------ POST /api/notifications/register-device ------ //
  Future<Map<String, dynamic>> registerDeviceToken(String fcmToken) =>
      _request('/notifications/register-device', method: 'POST', body: {'fcmToken': fcmToken});
  // ------ POST /api/notifications/register-onesignal-player ------ //
  Future<Map<String, dynamic>> registerOneSignalPlayerId(String playerId) =>
      _request('/notifications/register-onesignal-player', method: 'POST', body: {'playerId': playerId});

  // ------ DELETE /api/notifications/:id ------ //
  Future<Map<String, dynamic>> deleteNotification(String id) =>
      _request('/notifications/$id', method: 'DELETE');

  // ------ DELETE /api/notifications ------ //
  Future<Map<String, dynamic>> deleteAllNotifications() =>
      _request('/notifications', method: 'DELETE');

  // ---------------- Analytics ----------------
  // ------ GET /api/analytics ------ //
  Future<Map<String, dynamic>> getAnalytics() => _request('/analytics');

  // ---------------- Ratings (Rate Us) ----------------
  // ------ GET /api/ratings/status ------ //
  Future<Map<String, dynamic>> getRatingStatus() => _request('/ratings/status');
  // ------ GET /api/ratings/suggest ------ //
  Future<Map<String, dynamic>> suggestRatingReview(int stars) => _request('/ratings/suggest?stars=$stars');
  // ------ POST /api/ratings ------ //
  Future<Map<String, dynamic>> submitRating({required int stars, required String reviewText, required String email}) =>
      _request('/ratings', method: 'POST', body: {'stars': stars, 'reviewText': reviewText, 'email': email});
  // ------ POST /api/ratings/dismiss ------ //
  Future<Map<String, dynamic>> dismissRating() => _request('/ratings/dismiss', method: 'POST');
  // ------ GET /api/ratings/mine ------ //
  Future<Map<String, dynamic>> getMyRating() => _request('/ratings/mine');

  // ---------------- Admin ----------------
  // ------ GET /api/admin/dashboard ------ //
  Future<Map<String, dynamic>> adminDashboard() => _request('/admin/dashboard');
  // ------ GET /api/admin/payments ------ //
  Future<Map<String, dynamic>> adminPayments({String? status}) =>
      _request('/admin/payments${status != null ? '?status=$status' : ''}');
  // ------ PATCH /api/admin/payments/:id/approve ------ //
  Future<Map<String, dynamic>> approvePayment(String id) => _request('/admin/payments/$id/approve', method: 'PATCH');
  // ------ PATCH /api/admin/payments/:id/reject ------ //
  Future<Map<String, dynamic>> rejectPayment(String id, String note) =>
      _request('/admin/payments/$id/reject', method: 'PATCH', body: {'note': note});
  // ------ GET /api/admin/payment-settings ------ //
  Future<Map<String, dynamic>> getAdminPaymentSettings() => _request('/admin/payment-settings');

  // ------ GET /api/admin/users ------ //
  Future<Map<String, dynamic>> adminUsers({String? search}) => _request(
      '/admin/users${search != null && search.trim().isNotEmpty ? '?search=${Uri.encodeQueryComponent(search.trim())}' : ''}');

  // ------ POST /api/admin/users/:id/force-logout ------ //
  Future<Map<String, dynamic>> forceLogoutUser(String id) =>
      _request('/admin/users/$id/force-logout', method: 'POST');

  // ------ PATCH /api/admin/users/:id/toggle-active ------ //
  Future<Map<String, dynamic>> toggleUserActive(String id) =>
      _request('/admin/users/$id/toggle-active', method: 'PATCH');

  // ------ DELETE /api/admin/users/:id ------ //
  Future<Map<String, dynamic>> deleteUserAccount(String id) => _request('/admin/users/$id', method: 'DELETE');

  // ---------------- Gift Codes ----------------
  // ------ POST /api/admin/gift-codes ------ //
  Future<Map<String, dynamic>> adminCreateGiftCode({String? code, required int diamondValue, String? label}) =>
      _request('/admin/gift-codes', method: 'POST', body: {
        if (code != null) 'code': code,
        'diamondValue': diamondValue,
        if (label != null) 'label': label,
      });
  // ------ GET /api/admin/gift-codes ------ //
  Future<Map<String, dynamic>> adminListGiftCodes() => _request('/admin/gift-codes');
  // ------ PATCH /api/admin/gift-codes/:id/toggle-active ------ //
  Future<Map<String, dynamic>> adminToggleGiftCode(String id) =>
      _request('/admin/gift-codes/$id/toggle-active', method: 'PATCH');
  // ------ POST /api/diamonds/redeem-gift-code ------ //
  Future<Map<String, dynamic>> redeemGiftCode(String code) =>
      _request('/diamonds/redeem-gift-code', method: 'POST', body: {'code': code});

  // ------ PATCH /api/admin/payment-settings ------ //
  Future<Map<String, dynamic>> updatePaymentSettings({
    required String upiId,
    required String accountName,
    required String merchantName,
    String? qrImagePath,
  }) async {
    if (qrImagePath != null) {
      final qrFile = await http.MultipartFile.fromPath('qrImage', qrImagePath);
      return uploadMultipart(
        '/admin/payment-settings',
        method: 'PATCH',
        fields: {
          'upiId': upiId,
          'accountName': accountName,
          'merchantName': merchantName,
        },
        files: [qrFile],
      );
    }
    return _request('/admin/payment-settings', method: 'PATCH', body: {
      'upiId': upiId,
      'accountName': accountName,
      'merchantName': merchantName,
    });
  }

  http.MediaType _lookupMimeOrDefault(String path, String fallback) {
    final ext = path.split('.').last.toLowerCase();
    const map = {
      'mp4': 'video/mp4', 'mov': 'video/quicktime', 'mkv': 'video/x-matroska',
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    };
    final full = map[ext] ?? fallback;
    final parts = full.split('/');
    return http.MediaType(parts[0], parts[1]);
  }
}