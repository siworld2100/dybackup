/// 媒体下载与保存到系统相册。
///
/// 关键点：
///   * 抖音 CDN 会校验 Referer 与 UA，直连会 403，必须带上请求头
///   * 扩展名按上游实际响应类型推断（封面可能是 webp、原声可能是 m4a），
///     否则相册里会出现「打不开」的文件
///   * 临时文件下载完成后必须清理，避免占满用户存储
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'douyin_parser.dart';
import 'video_probe.dart';

/// 下载进度回调：0.0 ~ 1.0；总大小未知时传 -1。
typedef ProgressCallback = void Function(double progress);

class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 保存到相册时使用的相册名。
const String kAlbumName = '抖音视频备份';

const Map<String, String> mediaHeaders = {
  'User-Agent': kMobileUserAgent,
  'Referer': 'https://www.douyin.com/',
  'Accept': '*/*',
  'Accept-Language': 'zh-CN,zh;q=0.9',
};

const Map<String, String> _extByMime = {
  'video/mp4': '.mp4',
  'video/quicktime': '.mov',
  'video/x-flv': '.flv',
  'video/webm': '.webm',
  'audio/mpeg': '.mp3',
  'audio/mp4': '.m4a',
  'audio/aac': '.aac',
  'audio/x-m4a': '.m4a',
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
};

class DownloadService {
  DownloadService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 下载视频并保存到相册。
  ///
  /// [mirrors] 是同一档位的备用 CDN 地址，主地址失败时按顺序重试；
  /// 返回实际下载到的分辨率（读取 MP4 容器元数据，失败为 null）。
  Future<VideoSize?> saveVideo({
    required String url,
    List<String> mirrors = const [],
    required String baseName,
    ProgressCallback? onProgress,
    String fallbackExt = '.mp4',
  }) async {
    final urls = [url, ...mirrors].where((e) => e.isNotEmpty).toList();
    DownloadException? lastError;
    for (var i = 0; i < urls.length; i++) {
      try {
        return await _downloadAndSave(
          url: urls[i],
          baseName: baseName,
          isVideo: true,
          onProgress: onProgress,
          fallbackExt: fallbackExt,
        );
      } on DownloadException catch (e) {
        lastError = e;
        if (i < urls.length - 1) {
          onProgress?.call(-1); // 切线路：进度条转为不定态
        }
      }
    }
    throw lastError ?? DownloadException('没有可用的下载地址，请重新解析。');
  }

  /// 下载图片（封面 / 图文原图）并保存到相册。
  Future<void> saveImage({
    required String url,
    required String baseName,
    ProgressCallback? onProgress,
    String fallbackExt = '.jpg',
  }) async {
    await _downloadAndSave(
      url: url,
      baseName: baseName,
      isVideo: false,
      onProgress: onProgress,
      fallbackExt: fallbackExt,
    );
  }

  /// 下载音频（原声）并保存到相册。
  ///
  /// 注意：gal 只能写入系统相册（图片/视频），音频会保存到 App 外部目录。
  Future<String> saveAudio({
    required String url,
    required String baseName,
    ProgressCallback? onProgress,
  }) async {
    final file = await _download(
      url: url,
      baseName: baseName,
      onProgress: onProgress,
      fallbackExt: '.mp3',
    );

    final musicDir = Directory(
      '${(await getExternalStorageDirectory())?.path ?? (await getTemporaryDirectory()).path}/原声',
    );
    await musicDir.create(recursive: true);

    final target = File('${musicDir.path}/${file.uri.pathSegments.last}');
    try {
      await file.copy(target.path);
    } finally {
      await _deleteQuietly(file);
    }
    return target.path;
  }

  Future<VideoSize?> _downloadAndSave({
    required String url,
    required String baseName,
    required bool isVideo,
    ProgressCallback? onProgress,
    required String fallbackExt,
  }) async {
    final file = await _download(
      url: url,
      baseName: baseName,
      onProgress: onProgress,
      fallbackExt: fallbackExt,
    );

    try {
      final size = isVideo ? await probeVideoSize(file) : null;
      await _ensureGalleryAccess();
      if (isVideo) {
        await Gal.putVideo(file.path, album: kAlbumName);
      } else {
        await Gal.putImage(file.path, album: kAlbumName);
      }
      return size;
    } on GalException catch (e) {
      throw DownloadException(_galMessage(e.type));
    } finally {
      await _deleteQuietly(file);
    }
  }

  Future<File> _download({
    required String url,
    required String baseName,
    ProgressCallback? onProgress,
    required String fallbackExt,
  }) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers.addAll(mediaHeaders);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw DownloadException('连接超时，请检查网络后重试。');
    } on Exception catch (e) {
      throw DownloadException('网络请求失败：$e');
    }

    if (response.statusCode >= 400) {
      throw DownloadException(
        '资源获取失败（HTTP ${response.statusCode}），地址可能已过期，请重新解析。',
      );
    }

    final ext = _extensionFor(response.headers['content-type'], fallbackExt);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_safe(baseName)}$ext');

    final total = response.contentLength ?? 0;
    var received = 0;

    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) {
          onProgress(total > 0 ? received / total : -1);
        }
      }
    } on Exception catch (e) {
      await sink.close();
      await _deleteQuietly(file);
      throw DownloadException('下载中断：$e');
    }
    await sink.close();

    if (received == 0) {
      await _deleteQuietly(file);
      throw DownloadException('下载内容为空，地址可能已失效，请重新解析。');
    }

    return file;
  }

  /// 把打包进 App 的图片资源存进系统相册。
  ///
  /// 赞赏码必须变成相册里一张真实图片，用户才能在微信
  /// 「扫一扫 → 相册」里选中它——这是个人开发者唯一能走通的路径。
  Future<void> saveAssetImage(String assetPath, String fileName) async {
    await _ensureGalleryAccess();

    final data = await rootBundle.load(assetPath);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);

    await Gal.putImage(file.path, album: kAlbumName);
    // 不删临时文件：部分 ROM 的相册是异步落盘的，立即删除可能得到空图。
    // 它在应用缓存目录里，系统会自行回收。
  }

  Future<void> _ensureGalleryAccess() async {
    // 需要写入相册权限（Android 10+ 走 MediaStore，Android 13+ 走相册访问）
    if (await Gal.hasAccess(toAlbum: true)) return;
    if (await Gal.requestAccess(toAlbum: true)) return;

    // 部分系统只需基础权限
    if (await Gal.hasAccess()) return;
    if (await Gal.requestAccess()) return;

    throw DownloadException('没有相册权限，请在弹出的系统提示中允许，或到系统设置里手动开启。');
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 清理失败不影响主流程
    }
  }

  void dispose() => _client.close();
}

String _extensionFor(String? contentType, String fallback) {
  final mime = (contentType ?? '').split(';').first.trim().toLowerCase();
  return _extByMime[mime] ?? fallback;
}

String _safe(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return 'douyin_${DateTime.now().millisecondsSinceEpoch}';
  return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
}

String _galMessage(GalExceptionType type) => switch (type) {
  GalExceptionType.accessDenied => '相册权限被拒绝，请在系统设置中开启后重试。',
  GalExceptionType.notEnoughSpace => '设备存储空间不足，请清理后重试。',
  GalExceptionType.notSupportedFormat => '该文件格式不受系统相册支持。',
  GalExceptionType.unexpected => '保存到相册时发生未知错误。',
};
