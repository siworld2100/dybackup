/// 抖音分享链接解析核心（Dart 版）。
///
/// 与 Python 版 `douyin.py` 保持同一套解析思路：
///   1. 从分享文案中提取 URL
///   2. 手动跟随 302，取出作品 ID（aweme_id）
///   3. 用移动端 UA 请求 iesdouyin 分享页（关键：否则拿到加密源码）
///   4. 从页面内嵌的 window._ROUTER_DATA 中提取结构化数据
///   5. play_addr 中 playwm 换 play，得到可直接访问的播放地址
///
/// 与 Python 版的两处实现差异：
///   * Python 用 `json.JSONDecoder().raw_decode()` 精确截取 JSON；
///     Dart 无对应能力，改为手写「括号配对扫描器」，正确处理字符串与转义。
///   * Dart 的 http 包无法读取跳转后的最终 URL；改为关闭自动跳转、手动跟随。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video_info.dart';

/// 面向用户的可读错误。
class DouyinException implements Exception {
  DouyinException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 移动端 UA —— 必须使用，否则抖音返回加密后的页面源码。
const String kMobileUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
    'Mobile/15E148 Safari/604.1';

const Map<String, String> webHeaders = {
  'User-Agent': kMobileUserAgent,
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  'Referer': 'https://www.douyin.com/',
};

final RegExp _urlPattern = RegExp(
  r'https?://[^\s\u4e00-\u9fff，。、；：！？“”‘’（）【】《》"<>]+',
);
final RegExp _bareDomainPattern = RegExp(r'^[\w.\-]+\.\w{2,}(/\S*)?$');
final RegExp _trailingPunctuation = RegExp(r'[，。、；：！？.,;)\]}]+$');

final List<RegExp> _awemeIdPatterns = [
  RegExp(r'/video/(\d{6,})'),
  RegExp(r'/note/(\d{6,})'),
  RegExp(r'/slides/(\d{6,})'),
  RegExp(r'modal_id=(\d{6,})'),
  RegExp(r'/share/video/(\d{6,})'),
  RegExp(r'/share/note/(\d{6,})'),
  RegExp(r'/share/slides/(\d{6,})'),
  RegExp(r'item_ids=(\d{6,})'),
];

const Duration _requestTimeout = Duration(seconds: 20);

// ------------------------------------------------------------ 纯函数（可单测）

/// 从分享文案中提取第一个链接。
String extractUrl(String shareText) {
  final text = shareText.trim();
  if (text.isEmpty) {
    throw DouyinException('请先粘贴抖音的分享链接或分享文案。');
  }

  final match = _urlPattern.firstMatch(text);
  if (match == null) {
    // 用户可能只粘贴了一串不带协议头的链接
    if (_bareDomainPattern.hasMatch(text)) {
      return 'https://${text.replaceFirst(RegExp(r'^/+'), '')}';
    }
    throw DouyinException('没有识别到有效链接，请确认粘贴的是抖音分享链接。');
  }

  var url = match.group(0)!;
  url = url.replaceFirst(_trailingPunctuation, '');
  if (!url.startsWith('http')) url = 'https://$url';
  return url;
}

/// 尝试从 URL 中直接取出作品 ID。
String? awemeIdFromUrl(String url) {
  for (final pattern in _awemeIdPatterns) {
    final match = pattern.firstMatch(url);
    if (match != null) return match.group(1);
  }
  return null;
}

/// 播放地址归一化：把 playwm 路径纠正为 play 路径，得到可直连的播放地址。
String normalizePlayUrl(String url) {
  if (url.isEmpty) return '';
  return url.replaceAll('/playwm/', '/play/').replaceAll('playwm', 'play');
}

/// 从 HTML 中提取 window._ROUTER_DATA / __INITIAL_STATE__ 并解析为 Map。
Map<String, dynamic>? extractRouterData(String html) {
  for (final marker in const [
    'window._ROUTER_DATA',
    'window.__INITIAL_STATE__',
    '_ROUTER_DATA',
  ]) {
    final markerIndex = html.indexOf(marker);
    if (markerIndex < 0) continue;

    final start = html.indexOf('{', markerIndex);
    if (start < 0) continue;

    final json = _scanBalancedJson(html, start);
    if (json == null) continue;

    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// 括号配对扫描：从 [start]（一个 `{`）起找到与之配对的 `}`，返回完整 JSON 子串。
///
/// 必须正确跳过字符串字面量内部的花括号与转义符，否则页面里的
/// `{` / `}` 会提前打断截取（这是 Python raw_decode 帮我们做的事）。
String? _scanBalancedJson(String text, int start) {
  var depth = 0;
  var inString = false;
  var escaped = false;

  for (var i = start; i < text.length; i++) {
    final code = text.codeUnitAt(i);

    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5C) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }

    if (code == 0x22) {
      inString = true;
    } else if (code == 0x7B) {
      depth++;
    } else if (code == 0x7D) {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

// ------------------------------------------------------------ 解析器

class DouyinParser {
  DouyinParser({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 解析分享文案，返回作品信息。
  Future<VideoInfo> parse(String shareText) async {
    final url = extractUrl(shareText);
    final awemeId = await resolveAwemeId(url);

    DouyinException? lastError;
    for (final path in const ['video', 'note']) {
      final shareUrl = 'https://www.iesdouyin.com/share/$path/$awemeId/';
      try {
        final res = await _get(shareUrl);
        if (res.statusCode >= 400) {
          lastError = DouyinException('分享页请求失败（HTTP ${res.statusCode}）');
          continue;
        }

        final state = extractRouterData(res.body);
        if (state == null) {
          lastError = DouyinException(
            '分享页结构解析失败。抖音可能调整了页面格式，或该作品已被限制访问。',
          );
          continue;
        }

        return buildVideoInfo(_findItem(state), awemeId);
      } on DouyinException catch (e) {
        lastError = e;
      } on TimeoutException {
        lastError = DouyinException('请求超时，请检查网络后重试。');
      } on Exception catch (e) {
        lastError = DouyinException('请求分享页时出错：$e');
      }
    }

    throw lastError ?? DouyinException('解析失败，请稍后重试。');
  }

  /// 把短链还原成作品 ID。
  Future<String> resolveAwemeId(String url) async {
    final direct = awemeIdFromUrl(url);
    if (direct != null) return direct;

    final fetched = await _followRedirects(url);
    final fromUrl = awemeIdFromUrl(fetched.url);
    if (fromUrl != null) return fromUrl;

    // 兜底：跳到了需要 JS 渲染的页面，从 HTML 源码里捞 ID
    for (final pattern in [
      RegExp(r'"aweme_id"\s*:\s*"(\d{6,})"'),
      RegExp(r'video/(\d{16,})'),
      RegExp(r'(\d{19})'),
    ]) {
      final match = pattern.firstMatch(fetched.body);
      if (match != null) return match.group(1)!;
    }

    throw DouyinException('无法从该链接中解析出作品 ID，请确认链接来自抖音 App 的分享。');
  }

  /// 手动跟随重定向链，返回最终地址与响应体。
  Future<_Fetched> _followRedirects(String url) async {
    var current = url;
    for (var hop = 0; hop < 8; hop++) {
      final res = await _get(current);
      final location = res.headers['location'];

      if (res.statusCode >= 300 && res.statusCode < 400 && location != null) {
        current = Uri.parse(current).resolve(location).toString();
        continue;
      }
      return _Fetched(current, res.body, res.statusCode);
    }
    return _Fetched(current, '', 0);
  }

  Future<_RawResponse> _get(String url) async {
    final request = http.Request('GET', Uri.parse(url))
      ..followRedirects = false
      ..headers.addAll(webHeaders);

    final streamed = await _client.send(request).timeout(_requestTimeout);
    final body = await streamed.stream.bytesToString();
    return _RawResponse(streamed.statusCode, streamed.headers, body);
  }

  void dispose() => _client.close();
}

// ------------------------------------------------------------ 字段提取

/// 在 loaderData 中定位作品信息节点。
Map<String, dynamic> _findItem(Map<String, dynamic> state) {
  final loader = state['loaderData'];
  if (loader is Map) {
    for (final value in loader.values) {
      if (value is! Map) continue;
      final info = value['videoInfoRes'];
      if (info is! Map) continue;

      final items = info['item_list'];
      if (items is List && items.isNotEmpty) {
        final first = items.first;
        if (first is Map) return first.cast<String, dynamic>();
      }

      final filters = info['filter_list'];
      if (filters is List) {
        for (final entry in filters) {
          if (entry is! Map) continue;
          final reason = entry['detail_msg'] ?? entry['filter_reason'];
          if (reason is String && reason.isNotEmpty) {
            throw DouyinException('该作品无法解析：$reason');
          }
        }
      }
    }
  }

  throw DouyinException('未取到作品信息，可能作品已删除、设为私密或链接已过期。');
}

/// 从完整的 _ROUTER_DATA 状态中构建作品信息。
///
/// 供 WebView 解析流程使用：WebView 里通过 JS 拿到的就是已解析好的 Map，
/// 无需再走 HTML 文本截取。
VideoInfo videoInfoFromRouterData(
  Map<String, dynamic> state, {
  String? fallbackId,
}) {
  final item = _findItem(state);
  final fromItem = (item['aweme_id'] ?? '').toString();
  final id = fromItem.isNotEmpty
      ? fromItem
      : (fallbackId ?? '');
  return buildVideoInfo(item, id);
}

/// 把原始 item 转换为 App 使用的模型。公开以便单测。
VideoInfo buildVideoInfo(Map<String, dynamic> item, String awemeId) {  final video = _asMap(item['video']);
  final author = _asMap(item['author']);
  final stats = _asMap(item['statistics']);
  final music = _asMap(item['music']);

  final images = <String>[];
  for (final image in (item['images'] as List?) ?? const []) {
    if (image is! Map) continue;
    final urls = ((image['url_list'] as List?) ?? const [])
        .whereType<String>()
        .where((u) => u.isNotEmpty)
        .toList();
    // 通常最后一个为原图
    if (urls.isNotEmpty) images.add(urls.last);
  }

  final qualities = _buildQualities(video);
  final primary = qualities.firstWhere(
    (q) => q.isDefault,
    orElse: () => qualities.isEmpty
        ? const Quality(label: '默认', url: '', isDefault: true)
        : qualities.first,
  );

  final title = ((item['desc'] as String?) ?? '').trim();
  final nickname = ((author['nickname'] as String?) ?? '').trim();
  final avatar =
      _firstUrl(author['avatar_larger']).isNotEmpty
      ? _firstUrl(author['avatar_larger'])
      : _firstUrl(author['avatar_thumb']);

  return VideoInfo(
    awemeId: awemeId,
    type: images.isEmpty ? 'video' : 'images',
    title: title.isEmpty ? '抖音作品 $awemeId' : title,
    author: Author(
      nickname: nickname.isEmpty ? '未知作者' : nickname,
      avatar: avatar,
      uniqueId: (author['unique_id'] ?? author['short_id'] ?? '').toString(),
    ),
    stats: Stats(
      digg: _asInt(stats['digg_count']),
      comment: _asInt(stats['comment_count']),
      collect: _asInt(stats['collect_count']),
      share: _asInt(stats['share_count']),
    ),
    createTime: _formatTime(item['create_time']),
    durationMs: _asInt(video['duration']),
    cover: _pickCover(video),
    playUrl: primary.url,
    qualities: qualities,
    music: Music(
      title: ((music['title'] as String?) ?? '').trim(),
      author: ((music['author'] as String?) ?? '').trim(),
      url: _firstUrl(music['play_url']),
    ),
    images: images,
  );
}

List<Quality> _buildQualities(Map<String, dynamic> video) {
  final result = <Quality>[];
  final seen = <String>{};

  void add(String label, Object? node, {int pixels = 0, Object? size}) {
    final urls = _allUrls(node);
    if (urls.isEmpty) return;
    final primary = urls.first;
    if (!seen.add(primary)) return;
    result.add(
      Quality(
        label: label,
        url: primary,
        size: size is num ? size.toInt() : null,
        pixels: pixels > 0 ? pixels : null,
        mirrors: _dedupe(urls.skip(1)),
      ),
    );
  }

  final primaryAddr = _asMap(video['play_addr']);
  final primaryPixels = _shortSide(primaryAddr);
  add(
    primaryPixels > 0 ? '${primaryPixels}P' : '默认',
    primaryAddr,
    size: primaryAddr['data_size'],
    pixels: primaryPixels,
  );

  final bitRates = (video['bit_rate'] as List?) ?? const [];
  for (var i = 0; i < bitRates.length; i++) {
    final entry = bitRates[i];
    if (entry is! Map) continue;
    final map = entry.cast<String, dynamic>();
    final playAddr = _asMap(map['play_addr']);
    final pixels = _shortSide(playAddr);
    add(
      _qualityLabel(map, i, pixels),
      playAddr,
      size: playAddr['data_size'],
      pixels: pixels,
    );
  }

  // 分享页里的 playwm 地址最高只有 720P（带水印源）。
  // 原画 1080P 要用 video.play_addr.uri 走官方 play 接口，
  // 且必须显式带 ratio=1080p（ratio=4k/origin 会被服务端回落到 1080p）。
  final uri = (primaryAddr['uri'] as String? ??
          (video['vid'] as String?) ??
          '')
      .trim();
  final has1080 = result.any(
    (q) => (q.pixels ?? _pixelsFromLabel(q.label)) >= 1080,
  );
  if (uri.isNotEmpty && !has1080) {
    final legacy = _legacyPlayUrls(uri);
    if (legacy.isNotEmpty && seen.add(legacy.first)) {
      result.add(
        Quality(
          label: '1080P',
          url: legacy.first,
          pixels: 1080,
          mirrors: _dedupe(legacy.skip(1)),
        ),
      );
    }
  }

  // 兜底：完全没拿到可用地址时，仍用 uri 拼一个可尝试的地址
  if (result.isEmpty && uri.isNotEmpty) {
    final legacy = _legacyPlayUrls(uri);
    if (legacy.isNotEmpty) {
      result.add(
        Quality(
          label: '默认',
          url: legacy.first,
          mirrors: _dedupe(legacy.skip(1)),
          isDefault: true,
        ),
      );
    }
    return result;
  }

  // 按清晰度从高到低排序：短边像素优先，其次文件体积。
  // 排序后第一档即「最清晰」，作为默认下载档。
  result.sort((a, b) {
    final pa = a.pixels ?? _pixelsFromLabel(a.label);
    final pb = b.pixels ?? _pixelsFromLabel(b.label);
    if (pa != pb) return pb.compareTo(pa);
    return (b.size ?? 0).compareTo(a.size ?? 0);
  });

  return [
    for (var i = 0; i < result.length; i++)
      Quality(
        label: result[i].label,
        url: result[i].url,
        size: result[i].size,
        pixels: result[i].pixels,
        mirrors: result[i].mirrors,
        isDefault: i == 0,
      ),
  ];
}

/// 同一档位的多个 CDN 主机，主地址失败时依次重试。
List<String> _legacyPlayUrls(String uri) {
  final encoded = Uri.encodeQueryComponent(uri);
  return [
    for (final host in const [
      'aweme.snssdk.com',
      'www.iesdouyin.com',
      'api.amemv.com',
    ])
      'https://$host/aweme/v1/play/?video_id=$encoded&ratio=1080p&line=0',
  ];
}

/// 取节点下所有可用播放地址（去重、保序）。
List<String> _allUrls(Object? node) {
  if (node is! Map) return const [];
  final urls = node['url_list'];
  if (urls is! List) return const [];
  final result = <String>[];
  for (final raw in urls) {
    if (raw is! String) continue;
    final clean = normalizePlayUrl(raw);
    if (clean.isEmpty || result.contains(clean)) continue;
    result.add(clean);
  }
  return result;
}

List<String> _dedupe(Iterable<String> urls) {
  final result = <String>[];
  for (final url in urls) {
    if (url.isEmpty || result.contains(url)) continue;
    result.add(url);
  }
  return result;
}

/// 档位的短边像素（竖屏 1080×1920 返回 1080），拿不到返回 0。
int _shortSide(Map<String, dynamic> addr) {
  final w = _asInt(addr['width']);
  final h = _asInt(addr['height']);
  if (w <= 0 || h <= 0) return 0;
  return w < h ? w : h;
}

int _pixelsFromLabel(String label) {
  final match = RegExp(r'^(\d{3,4})P$').firstMatch(label);
  return match == null ? 0 : (int.tryParse(match.group(1)!) ?? 0);
}

String _qualityLabel(Map<String, dynamic> bitRate, int index, int pixels) {
  if (pixels > 0) return '${pixels}P';
  final gear = (bitRate['gear_name'] as String?) ?? '';
  final match = RegExp(r'(\d{3,4})').firstMatch(gear);
  if (match != null) {
    final value = int.tryParse(match.group(1)!) ?? 0;
    if (value >= 144 && value <= 4320) return '${value}P';
  }
  final quality = bitRate['quality_type'];
  if (quality is int && quality > 0) return '画质档 $quality';
  return '清晰度 ${index + 1}';
}

String _pickCover(Map<String, dynamic> video) {
  for (final key in const ['cover', 'origin_cover', 'dynamic_cover']) {
    final url = _firstUrl(video[key]);
    if (url.isNotEmpty) return url;
  }
  return '';
}

String _firstUrl(Object? node) {
  if (node is Map) {
    final urls = node['url_list'];
    if (urls is List) {
      for (final url in urls) {
        if (url is String && url.isNotEmpty) return url;
      }
    }
  }
  return '';
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const <String, dynamic>{};

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 时间戳（秒）→ 北京时间字符串。
String _formatTime(Object? timestamp) {
  if (timestamp is! num || timestamp <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(
    timestamp.toInt() * 1000,
    isUtc: true,
  ).add(const Duration(hours: 8));

  String two(int n) => n.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}';
}

// ------------------------------------------------------------ 内部类型

class _RawResponse {
  _RawResponse(this.statusCode, this.headers, this.body);

  final int statusCode;
  final Map<String, String> headers;
  final String body;
}

class _Fetched {
  _Fetched(this.url, this.body, this.statusCode);

  final String url;
  final String body;
  final int statusCode;
}
