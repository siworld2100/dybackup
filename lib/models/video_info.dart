/// 抖音作品数据模型。
///
/// 与 Python 版 `douyin.py` 的 `build_result()` 输出结构保持一致，
/// 便于两端对照维护。
library;

/// 单个清晰度选项（均为可直连的播放地址）。
class Quality {
  const Quality({
    required this.label,
    required this.url,
    this.size,
    this.pixels,
    this.mirrors = const [],
    this.isDefault = false,
  });

  final String label;
  final String url;
  final int? size;

  /// 画质的短边像素（如竖屏 1080×1920 记为 1080）。
  /// 抖音多数档位会给 width/height，缺省时为 null，排序时退回按标签解析。
  final int? pixels;

  /// 同一档位的备用地址（CDN 多线路），主地址失败时按顺序重试。
  final List<String> mirrors;

  final bool isDefault;

  /// 主地址 + 备用地址，按顺序尝试。
  List<String> get urls => url.isEmpty ? mirrors : [url, ...mirrors];

  factory Quality.fromJson(Map<String, dynamic> json) => Quality(
    label: (json['label'] as String?)?.trim().isNotEmpty == true
        ? json['label'] as String
        : '默认',
    url: json['url'] as String? ?? '',
    size: json['size'] as int?,
    pixels: json['pixels'] as int?,
    mirrors:
        (json['mirrors'] as List?)?.whereType<String>().toList(growable: false) ??
        const [],
    isDefault: json['default'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'url': url,
    'size': size,
    'pixels': pixels,
    'mirrors': mirrors,
    'default': isDefault,
  };
}

/// 作者信息。
class Author {
  const Author({this.nickname = '', this.avatar = '', this.uniqueId = ''});

  final String nickname;
  final String avatar;
  final String uniqueId;

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    nickname: json['nickname'] as String? ?? '',
    avatar: json['avatar'] as String? ?? '',
    uniqueId: json['unique_id'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'nickname': nickname,
    'avatar': avatar,
    'unique_id': uniqueId,
  };
}

/// 互动数据。
class Stats {
  const Stats({this.digg = 0, this.comment = 0, this.collect = 0, this.share = 0});

  final int digg;
  final int comment;
  final int collect;
  final int share;

  factory Stats.fromJson(Map<String, dynamic> json) => Stats(
    digg: _asInt(json['digg']),
    comment: _asInt(json['comment']),
    collect: _asInt(json['collect']),
    share: _asInt(json['share']),
  );

  Map<String, dynamic> toJson() => {
    'digg': digg,
    'comment': comment,
    'collect': collect,
    'share': share,
  };
}

/// 背景音乐。
class Music {
  const Music({this.title = '', this.author = '', this.url = ''});

  final String title;
  final String author;
  final String url;

  bool get hasUrl => url.isNotEmpty;

  factory Music.fromJson(Map<String, dynamic> json) => Music(
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    url: json['url'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'title': title, 'author': author, 'url': url};
}

/// 一个抖音作品（视频或图文）。
class VideoInfo {
  const VideoInfo({
    required this.awemeId,
    required this.type,
    required this.title,
    required this.author,
    required this.stats,
    this.createTime = '',
    this.durationMs = 0,
    this.cover = '',
    this.playUrl = '',
    this.qualities = const [],
    this.music = const Music(),
    this.images = const [],
  });

  final String awemeId;

  /// `video` 或 `images`
  final String type;
  final String title;
  final Author author;
  final Stats stats;
  final String createTime;
  final int durationMs;
  final String cover;
  final String playUrl;
  final List<Quality> qualities;
  final Music music;
  final List<String> images;

  bool get isImages => type == 'images';

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    final video = (json['video'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawQualities = (video['qualities'] as List?) ?? const [];

    return VideoInfo(
      awemeId: json['aweme_id'] as String? ?? '',
      type: json['type'] as String? ?? 'video',
      title: json['title'] as String? ?? '',
      author: Author.fromJson(
        (json['author'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      stats: Stats.fromJson(
        (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      createTime: json['create_time'] as String? ?? '',
      durationMs: _asInt(json['duration_ms']),
      cover: json['cover'] as String? ?? '',
      playUrl: video['play_url'] as String? ?? '',
      qualities: rawQualities
          .whereType<Map>()
          .map((e) => Quality.fromJson(e.cast<String, dynamic>()))
          .toList(),
      music: Music.fromJson(
        (json['music'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      images: ((json['images'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'aweme_id': awemeId,
    'type': type,
    'title': title,
    'author': author.toJson(),
    'stats': stats.toJson(),
    'create_time': createTime,
    'duration_ms': durationMs,
    'cover': cover,
    'video': {
      'play_url': playUrl,
      'qualities': qualities.map((q) => q.toJson()).toList(),
    },
    'music': music.toJson(),
    'images': images,
  };

  /// 用于文件名 / 相册文件名的主干，已去除非法字符。
  String get safeTitle {
    final cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'douyin_$awemeId';
    return cleaned.length > 40 ? cleaned.substring(0, 40).trim() : cleaned;
  }

  /// 时长格式化，如 `1:23`。
  String get durationText {
    if (durationMs <= 0) return '';
    final total = (durationMs / 1000).round();
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
