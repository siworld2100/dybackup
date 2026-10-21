import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_info.dart';
import '../services/douyin_parser.dart' show extractUrl;
import '../services/download_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/share_receiver.dart';
import '../services/update_config.dart';
import '../services/video_probe.dart';
import '../widgets/update_flow.dart';
import 'parse_sheet.dart';
import 'usage_guide_page.dart';

// ------------------------------------------------------------ 主题常量

const Color _ink = Color(0xFF161823);
const Color _ink2 = Color(0xFF4A4F5C);
const Color _ink3 = Color(0xFF858B99);
const Color _line = Color(0xFFE9EAEE);
const Color _brand = Color(0xFFFE2C55);
const Color _bgSoft = Color(0xFFFCFCFD);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final TextEditingController _input = TextEditingController();
  final DownloadService _downloader = DownloadService();
  final HistoryService _history = HistoryService();
  final SettingsService _settings = SettingsService();

  bool _parsing = false;
  VideoInfo? _info;
  String? _error;
  List<VideoInfo> _recent = [];

  /// 正在下载的目标标识，null 表示空闲。
  String? _busyKey;
  double _progress = 0;
  bool _indeterminate = false;

  int _qualityIndex = 0;

  /// 「解析成功后自动下载视频」开关。
  bool _autoDownload = false;

  /// 上一次弹窗询问过的剪贴板内容，避免同一链接反复打扰。
  String _lastPromptText = '';

  /// 解析/下载进行中收到的分享，暂存到空闲后再处理。
  String? _queuedShare;

  /// 启动时的更新检查定时器，销毁时必须取消。
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreHistory();
    _loadSettings();
    ShareReceiver.listen(
      onShare: _handleSharedText,
      onParseClipboard: _parseClipboardShortcut,
    );
    // 首帧渲染完成后：优先处理系统分享 / 快捷入口，其次才是剪贴板提示
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shared = await ShareReceiver.initial();
      if (!mounted) return;
      if (shared != null) {
        _handleSharedText(shared);
        return;
      }
      final byParseEntry = await ShareReceiver.initialParseClipboard();
      if (!mounted) return;
      if (byParseEntry) {
        await _parseClipboardShortcut();
        return;
      }
      _checkClipboardPrompt();
    });
    // 静默检查新版本：延后一段时间，避免和首帧渲染、剪贴板检测抢网络与主线程。
    // 失败一律不打扰——用户此刻关心的是「能不能下载」，不是版本号。
    if (UpdateConfig.autoCheckOnStartup) {
      _updateTimer = Timer(UpdateConfig.startupDelay, () {
        if (mounted) checkUpdateAndPrompt(context);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _input.dispose();
    _downloader.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从抖音复制链接后切回 App，是最典型的使用路径
    if (state == AppLifecycleState.resumed) {
      _checkClipboardPrompt();
    }
  }

  // ---------------------------------------------------------- 业务动作

  Future<void> _loadSettings() async {
    final enabled = await _settings.autoDownloadEnabled();
    if (mounted) setState(() => _autoDownload = enabled);
  }

  Future<void> _toggleAutoDownload(bool value) async {
    await _settings.setAutoDownload(value);
    if (mounted) {
      setState(() => _autoDownload = value);
      _snack(value ? '已开启：解析成功后自动下载视频' : '已关闭自动下载');
    }
  }

  /// 处理系统分享进来的文本：直接解析，不再弹「是否粘贴」确认框
  /// （用户已经在分享面板里明确选择了本 App，多问一次只会碍事）。
  void _handleSharedText(String raw) {
    if (!mounted) return;
    final text = raw.trim();
    if (text.isEmpty) return;

    // 记下来，避免同一内容紧接着又被剪贴板检测弹一次
    _lastPromptText = text;

    if (!_looksLikeDouyinLink(text)) {
      _snack('分享内容里没有抖音链接，请确认后再试', isError: true);
      return;
    }

    // 正在解析/下载，或前台有弹层：排队，等空闲后自动处理
    if (_parsing || _busyKey != null || ModalRoute.of(context)?.isCurrent != true) {
      _queuedShare = text;
      _snack('当前任务完成后会自动解析这条链接');
      return;
    }

    _input.text = text;
    _parse(text);
  }

  /// 桌面快捷方式 / 通知栏磁贴：直接读剪贴板并解析，省掉粘贴动作。
  Future<void> _parseClipboardShortcut() async {
    if (!mounted) return;
    // Android 10+ 只允许前台 App 读剪贴板；从磁贴拉起时可能还没真正获得焦点，
    // 空结果时短暂重试几次，避免「点了没反应」。
    var text = '';
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
      } on Exception {
        if (attempt == 2) {
          _snack('读取剪贴板失败，请手动粘贴', isError: true);
          return;
        }
      }
      if (text.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    if (!mounted) return;
    if (text.isEmpty) {
      _snack('剪贴板是空的，先在抖音里点「分享」复制链接', isError: true);
      return;
    }
    if (!_looksLikeDouyinLink(text)) {
      _snack('剪贴板里没有抖音链接', isError: true);
      return;
    }
    _handleSharedText(text);
  }

  /// 空闲时消费排队的分享内容。
  void _drainQueuedShare() {
    final text = _queuedShare;
    if (text == null) return;
    if (_parsing || _busyKey != null) return;
    _queuedShare = null;
    // 下一帧再处理，避免在 setState / finally 中重入弹层
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handleSharedText(text);
    });
  }

  /// 检测剪贴板里是否有抖音链接，有则弹窗询问是否解析。
  Future<void> _checkClipboardPrompt() async {
    if (!mounted || _parsing || _busyKey != null) return;
    // 弹层/对话框开着时不打扰
    if (ModalRoute.of(context)?.isCurrent != true) return;

    String text;
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    } on Exception {
      return;
    }
    if (text.isEmpty || text == _lastPromptText || text == _input.text.trim()) {
      return;
    }
    if (!_looksLikeDouyinLink(text)) return;

    _lastPromptText = text;

    String preview = text;
    try {
      preview = extractUrl(text);
    } on Exception {
      // 提取失败就展示原文
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ClipboardPromptDialog(url: preview),
    );
    if (confirmed != true || !mounted) {
      // 弹窗期间可能收到系统分享，确认框关闭后补一次处理
      _drainQueuedShare();
      return;
    }

    _input.text = text;
    await _parse(text);
  }

  static bool _looksLikeDouyinLink(String text) {
    return text.contains('douyin.com') || text.contains('iesdouyin.com');
  }

  /// 下载地址序列：当前档位所有线路 → 更低档位。
  /// 最高档的 1080P 地址由接口拼接，个别作品可能失效，
  /// 依次回退可保证「最差也能下到能播的版本」，且提示里会报告真实分辨率。
  List<String> _videoSources(VideoInfo info) {
    final qualities = info.qualities;
    if (qualities.isEmpty) return [info.playUrl];
    final start = _qualityIndex.clamp(0, qualities.length - 1);
    final urls = <String>[];
    for (var i = start; i < qualities.length; i++) {
      for (final url in qualities[i].urls) {
        if (url.isNotEmpty && !urls.contains(url)) urls.add(url);
      }
    }
    if (urls.isEmpty && info.playUrl.isNotEmpty) urls.add(info.playUrl);
    return urls;
  }

  /// 下载成功提示：带上实际分辨率，避免「标称 1080P、实际 720P」的落差。
  String _videoSavedMessage(VideoSize? size, {bool auto = false}) {
    final prefix = auto ? '视频已自动保存' : '视频已保存';
    if (size == null) return '$prefix到相册「$kAlbumName」';
    final pixels = size.shortSide;
    final tag = pixels >= 1080 ? '高清' : (pixels >= 720 ? '标清' : '较低画质');
    return '$prefix（${size.width}×${size.height}，$tag）到相册「$kAlbumName」';
  }

  /// 解析成功后按开关自动下载视频。
  void _maybeAutoDownload(VideoInfo info) {
    if (!_autoDownload) return;
    if (info.isImages) return;
    final sources = _videoSources(info);
    if (sources.isEmpty) return;
    if (_busyKey != null) return;

    _runDownload<VideoSize?>(
      key: 'video',
      successBuilder: (size) => _videoSavedMessage(size, auto: true),
      action: (onProgress) => _downloader.saveVideo(
        url: sources.first,
        mirrors: sources.skip(1).toList(growable: false),
        baseName: info.safeTitle,
        onProgress: onProgress,
      ),
    );
  }

  Future<void> _restoreHistory() async {
    final list = await _history.load();
    if (mounted) setState(() => _recent = list);
  }

  Future<void> _parse([String? overrideText]) async {
    final text = (overrideText ?? _input.text).trim();
    if (text.isEmpty) {
      _snack('请先粘贴抖音分享链接');
      return;
    }

    setState(() {
      _parsing = true;
      _error = null;
    });

    try {
      // 解析交给内嵌 WebView 面板完成（抖音风控要求真实浏览器引擎）
      final result = await ParseSheet.show(context, text);
      if (!mounted) return;
      if (result == null) {
        // 用户手动取消
        setState(() => _parsing = false);
        return;
      }
      if (result.error != null) {
        setState(() {
          _error = result.error;
          _parsing = false;
        });
        return;
      }

      final info = result.info!;
      setState(() {
        _info = info;
        _qualityIndex = 0;
        _parsing = false;
      });

      final updated = await _history.add(info);
      if (mounted) setState(() => _recent = updated);

      // 开关打开时自动开始下载（仅视频作品）
      _maybeAutoDownload(info);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = '解析出错：$e';
          _parsing = false;
        });
      }
    } finally {
      _drainQueuedShare();
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (text.isEmpty) {
        _snack('剪贴板里没有文字内容');
        return;
      }
      _input.text = text;
      await _parse(text);
    } on Exception {
      _snack('读取剪贴板失败，请手动粘贴');
    }
  }

  Future<T?> _runDownload<T>({
    required String key,
    required Future<T> Function(ProgressCallback onProgress) action,
    String? successMessage,
    String Function(T result)? successBuilder,
  }) async {
    if (_busyKey != null) return null;
    setState(() {
      _busyKey = key;
      _progress = 0;
      _indeterminate = false;
    });

    try {
      final result = await action((p) {
        if (!mounted) return;
        setState(() {
          _indeterminate = p < 0;
          if (p >= 0) _progress = p;
        });
      });
      if (mounted) {
        final text = successBuilder != null
            ? successBuilder(result)
            : successMessage;
        if (text != null && text.isNotEmpty) _snack(text);
      }
      return result;
    } on DownloadException catch (e) {
      if (mounted) _snack(e.message, isError: true);
    } on Exception catch (e) {
      if (mounted) _snack('下载失败：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _busyKey = null;
          _progress = 0;
        });
      }
      _drainQueuedShare();
    }
    return null;
  }

  // ---------------------------------------------------------- 小工具

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFD92D20)
              : const Color(0xFF12A150),
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7F9),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: const Row(
          children: [
            _BrandMark(),
            SizedBox(width: 10),
            Text(
              '抖音视频备份',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => UsageGuidePage.open(context),
            icon: const Icon(Icons.menu_book_outlined, size: 17, color: _ink2),
            label: const Text(
              '使用说明',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _ink2,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          _buildInputCard(),
          _buildSettingsCard(),
          if (_error != null) _buildErrorCard(_error!),
          if (_info != null) ...[
            _buildInfoCard(_info!),
            _buildActionCard(_info!),
            if (_info!.isImages && _info!.images.isNotEmpty)
              _buildImagesCard(_info!),
          ],
          if (_recent.isNotEmpty) _buildHistoryCard(),
          const SizedBox(height: 4),
          _buildFooter(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- 输入区

  Widget _buildInputCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '分享链接',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ink3,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 5,
            style: const TextStyle(fontSize: 14, color: _ink),
            decoration: InputDecoration(
              hintText: '在此粘贴抖音分享链接，或直接粘贴 App 里复制的整段分享文案',
              hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA8ADBA)),
              filled: true,
              fillColor: _bgSoft,
              contentPadding: const EdgeInsets.all(12),
              border: _inputBorder(const Color(0xFFDCDEE4)),
              enabledBorder: _inputBorder(const Color(0xFFDCDEE4)),
              focusedBorder: _inputBorder(_brand, width: 1.5),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _parsing ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded, size: 17),
                label: const Text('读取剪贴板', style: TextStyle(fontSize: 13.5)),
                style: TextButton.styleFrom(foregroundColor: _ink2),
              ),
              TextButton(
                onPressed: _parsing
                    ? null
                    : () => setState(() {
                        _input.clear();
                        _error = null;
                        _info = null;
                      }),
                style: TextButton.styleFrom(foregroundColor: _ink3),
                child: const Text('清空', style: TextStyle(fontSize: 13.5)),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _parsing ? null : () => _parse(),
                style: FilledButton.styleFrom(
                  backgroundColor: _brand,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _parsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '开始解析',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  // ---------------------------------------------------------- 设置区

  Widget _buildSettingsCard() {
    return _card(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          const Icon(Icons.download_for_offline_outlined,
              size: 20, color: _ink2),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '自动下载视频',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '粘贴确认解析成功后，自动保存到相册',
                  style: TextStyle(fontSize: 11.5, color: _ink3),
                ),
              ],
            ),
          ),
          Switch(
            value: _autoDownload,
            activeThumbColor: _brand,
            onChanged: _busyKey != null ? null : _toggleAutoDownload,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFD92D20), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13.5, color: Color(0xFFD92D20), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- 作品信息

  Widget _buildInfoCard(VideoInfo info) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  info.isImages ? '图文作品' : '视频作品',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _brand,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'ID ${info.awemeId}',
                style: const TextStyle(fontSize: 11.5, color: _ink3),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: _cover(info),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: info.author.avatar.isEmpty
                                ? const ColoredBox(color: Color(0xFFF2F3F5))
                                : Image.network(
                                    info.author.avatar,
                                    headers: mediaHeaders,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const ColoredBox(color: Color(0xFFF2F3F5)),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                info.author.nickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _ink,
                                ),
                              ),
                              if (info.author.uniqueId.isNotEmpty)
                                Text(
                                  '抖音号 ${info.author.uniqueId}',
                                  style: const TextStyle(fontSize: 11.5, color: _ink3),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statChip('点赞', info.stats.digg),
                        _statChip('评论', info.stats.comment),
                        _statChip('收藏', info.stats.collect),
                        _statChip('分享', info.stats.share),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (info.createTime.isNotEmpty || info.durationText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (info.createTime.isNotEmpty)
                  Text('发布 ${info.createTime}',
                      style: const TextStyle(fontSize: 12, color: _ink3)),
                if (info.durationText.isNotEmpty)
                  Text('时长 ${info.durationText}',
                      style: const TextStyle(fontSize: 12, color: _ink3)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cover(VideoInfo info) {
    if (info.cover.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFF2F3F5),
        child: Center(
          child: Icon(Icons.image_outlined, color: Color(0xFFB4B2A9), size: 28),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          info.cover,
          headers: mediaHeaders,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const ColoredBox(color: Color(0xFFF2F3F5)),
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFFF2F3F5),
            child: Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Color(0xFFB4B2A9), size: 24),
            ),
          ),
        ),
        if (!info.isImages)
          const Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Color(0x8C161823),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 34,
                height: 34,
                child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),
      ],
    );
  }

  Widget _statChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Text(
        '$label ${_fmtCount(value)}',
        style: const TextStyle(fontSize: 11.5, color: _ink2),
      ),
    );
  }

  // ---------------------------------------------------------- 下载操作

  /// 下拉项文案：`1080P · 24.6MB · 最高`。列表已按画质降序，第一项即最高。
  String _qualityText(Quality quality, {bool isTop = false}) {
    final buffer = StringBuffer(quality.label);
    if (quality.size != null) {
      buffer.write(' · ${_fmtSize(quality.size!)}');
    }
    if (isTop) buffer.write(' · 最高');
    return buffer.toString();
  }

  Widget _buildActionCard(VideoInfo info) {
    final qualities = info.qualities;
    final showPicker = !info.isImages && qualities.length > 1;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPicker) ...[
            Row(
              children: [
                const Text('清晰度', style: TextStyle(fontSize: 12.5, color: _ink3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _bgSoft,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDCDEE4)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _qualityIndex,
                        isExpanded: true,
                        style: const TextStyle(fontSize: 13.5, color: _ink),
                        items: [
                          for (var i = 0; i < qualities.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                _qualityText(qualities[i], isTop: i == 0),
                              ),
                            ),
                        ],
                        onChanged: _busyKey != null
                            ? null
                            : (v) => setState(() => _qualityIndex = v ?? 0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (!info.isImages)
            _downloadButton(
              key: 'video',
              label: '保存视频',
              icon: Icons.download_rounded,
              primary: true,
              onTap: _videoSources(info).isEmpty
                  ? null
                  : () {
                      final sources = _videoSources(info);
                      _runDownload<VideoSize?>(
                        key: 'video',
                        successBuilder: _videoSavedMessage,
                        action: (onProgress) => _downloader.saveVideo(
                          url: sources.first,
                          mirrors: sources.skip(1).toList(growable: false),
                          baseName: info.safeTitle,
                          onProgress: onProgress,
                        ),
                      );
                    },
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _downloadButton(
                  key: 'cover',
                  label: '下载封面',
                  icon: Icons.image_outlined,
                  onTap: info.cover.isEmpty
                      ? null
                      : () => _runDownload(
                          key: 'cover',
                          successMessage: '封面已保存到相册「$kAlbumName」',
                          action: (onProgress) => _downloader.saveImage(
                            url: info.cover,
                            baseName: '${info.safeTitle}-封面',
                            onProgress: onProgress,
                          ),
                        ),
                ),
              ),
              if (info.music.hasUrl) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _downloadButton(
                    key: 'music',
                    label: '下载原声',
                    icon: Icons.music_note_outlined,
                    onTap: () => _runDownload(
                      key: 'music',
                      successMessage: '原声已保存到手机存储（App 外部目录）',
                      action: (onProgress) => _downloader.saveAudio(
                        url: info.music.url,
                        baseName: '${info.safeTitle}-原声',
                        onProgress: onProgress,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (_busyKey != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _indeterminate ? null : _progress,
                minHeight: 6,
                backgroundColor: const Color(0xFFF0F1F3),
                valueColor: const AlwaysStoppedAnimation<Color>(_brand),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _indeterminate
                  ? '正在下载…'
                  : '正在下载 ${(_progress * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: _ink3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _downloadButton({
    required String key,
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    bool primary = false,
  }) {
    final busy = _busyKey == key;
    final enabled = onTap != null && _busyKey == null;

    if (primary) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: enabled ? onTap : null,
          icon: busy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(icon, size: 18),
          label: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _ink,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 13.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: _ink,
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: const BorderSide(color: Color(0xFFDCDEE4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ---------------------------------------------------------- 图文

  Widget _buildImagesCard(VideoInfo info) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '图文原图（${info.images.length} 张）',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _ink3,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '点图片即保存',
                style: const TextStyle(fontSize: 11.5, color: _ink3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: info.images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3 / 4,
            ),
            itemBuilder: (context, index) {
              final url = info.images[index];
              final key = 'image_$index';
              final busy = _busyKey == key;

              return GestureDetector(
                onTap: _busyKey != null
                    ? null
                    : () => _runDownload(
                        key: key,
                        successMessage:
                            '第 ${index + 1} 张已保存到相册「$kAlbumName」',
                        action: (onProgress) => _downloader.saveImage(
                          url: url,
                          baseName: '${info.safeTitle}_${index + 1}',
                          onProgress: onProgress,
                        ),
                      ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        url,
                        headers: mediaHeaders,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : const ColoredBox(color: Color(0xFFF2F3F5)),
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Color(0xFFF2F3F5)),
                      ),
                      if (busy)
                        const ColoredBox(
                          color: Color(0x73000000),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- 历史记录

  Widget _buildHistoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '最近解析',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink3,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await _history.clear();
                  if (mounted) setState(() => _recent = []);
                },
                style: TextButton.styleFrom(
                  foregroundColor: _ink3,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('清除', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _recent.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: _line),
            _historyTile(_recent[i]),
          ],
        ],
      ),
    );
  }

  Widget _historyTile(VideoInfo info) {
    return InkWell(
      onTap: () {
        setState(() {
          _info = info;
          _qualityIndex = 0;
          _error = null;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 38,
                height: 38,
                child: info.cover.isEmpty
                    ? const ColoredBox(color: Color(0xFFF2F3F5))
                    : Image.network(
                        info.cover,
                        headers: mediaHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const ColoredBox(color: Color(0xFFF2F3F5)),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: _ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${info.author.nickname} · ${info.isImages ? '图文' : '视频'}',
                    style: const TextStyle(fontSize: 11.5, color: _ink3),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _ink3, size: 20),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- 通用

  Widget _card({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }

  Widget _buildFooter() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.only(top: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      child: const Text(
        '本工具仅用于个人学习与合理使用，请遵守抖音服务条款与《著作权法》，'
        '勿用于商业用途或二次分发。解析全部在本机完成，不收集、不上传任何数据。',
        style: TextStyle(fontSize: 11.5, color: _ink3, height: 1.7),
      ),
    );
  }
}

/// 头部品牌图：直接复用与桌面图标同一套代码生成的资源，保证完全一致。
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand_mark.png',
      width: 34,
      height: 34,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// 「检测到视频链接，是否粘贴？」确认弹窗。
class _ClipboardPromptDialog extends StatelessWidget {
  const _ClipboardPromptDialog({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              '检测到视频链接，是否粘贴？',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Text(
              url,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: _ink3, height: 1.5),
            ),
          ),
          const Divider(height: 1, color: _line),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: _ink2,
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: const Text('取消', style: TextStyle(fontSize: 15)),
                  ),
                ),
                const VerticalDivider(width: 1, color: _line),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF3B82F6),
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ 格式化

String _fmtCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

String _fmtSize(int bytes) {
  if (bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final digits = (size >= 100 || unit == 0) ? 0 : 1;
  return '${size.toStringAsFixed(digits)} ${units[unit]}';
}
