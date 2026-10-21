import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/video_info.dart';
import '../services/douyin_parser.dart';

const Color _ink = Color(0xFF161823);
const Color _ink3 = Color(0xFF858B99);
const Color _line = Color(0xFFE9EAEE);
const Color _brand = Color(0xFFFE2C55);

/// 解析结果：成功时 [info] 非 null；失败时 [error] 非 null。
class ParseSheetResult {
  const ParseSheetResult.success(this.info) : error = null;
  const ParseSheetResult.failure(this.error) : info = null;

  final VideoInfo? info;
  final String? error;
}

/// WebView 解析面板。
///
/// 抖音已上线基于 JS 挑战（__ac_nonce + acrawler）的反爬：纯 HTTP 客户端
/// 请求短链只会被 302 到首页，分享页也只会返回反爬挑战页。
/// 只有真实浏览器引擎执行了挑战脚本、种下 Cookie 之后才能拿到数据。
///
/// 因此解析过程交给内嵌 WebView 完成：
///   1. 加载分享短链，等待挑战脚本自动完成跳转
///   2. 从最终地址提取作品 ID（aweme_id）
///   3. 执行 JS 读取 window._ROUTER_DATA
///   4. 失败则回退读取整页 HTML 离线提取，或主动跳到 iesdouyin 分享页
class ParseSheet extends StatefulWidget {
  const ParseSheet({super.key, required this.shareText});

  final String shareText;

  /// 以底部弹层形式展示解析面板，关闭时返回结果；用户手动关闭返回 null。
  static Future<ParseSheetResult?> show(BuildContext context, String shareText) {
    return showModalBottomSheet<ParseSheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ParseSheet(shareText: shareText),
    );
  }

  @override
  State<ParseSheet> createState() => _ParseSheetState();
}

class _ParseSheetState extends State<ParseSheet> {
  static const _overallTimeout = Duration(seconds: 45);

  WebViewController? _controller;
  Timer? _poll;
  Timer? _overall;

  bool _checking = false;
  bool _finished = false;
  bool _started = false;
  int _shareLoads = 0;
  String _status = '正在打开分享链接…';

  @override
  void initState() {
    super.initState();
    // initState 里不能直接 await，延后到首帧之后启动
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  @override
  void dispose() {
    _finished = true;
    _poll?.cancel();
    _overall?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------- 启动

  Future<void> _launch() async {
    if (_started) return;
    _started = true;

    String url;
    try {
      url = extractUrl(widget.shareText);
    } on DouyinException catch (e) {
      _fail(e.message);
      return;
    }

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _check(),
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && !_finished) {
              _setStatus('页面加载异常，正在重试…');
            }
          },
        ),
      );

    if (!mounted) return;
    setState(() => _controller = controller);

    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
    _overall = Timer(_overallTimeout, () {
      _fail('解析超时。可以先判断链接本身是否有效：把这条链接粘贴到手机浏览器打开，'
          '若浏览器里也看不到视频，说明链接已失效，请重新在抖音里复制一次。');
    });

    try {
      await controller.loadRequest(Uri.parse(url));
    } on Exception catch (e) {
      _fail('无法打开分享链接：$e');
    }
  }

  // ---------------------------------------------------------- 轮询检测

  /// 每秒检查一次当前页面：
  ///   * 能读到 _ROUTER_DATA → 解析完成
  ///   * 地址里已有作品 ID 但不是分享页 → 主动跳 iesdouyin 分享页
  Future<void> _check() async {
    if (_finished || _checking) return;
    final controller = _controller;
    if (controller == null) return;

    _checking = true;
    try {
      final current = await controller.currentUrl();
      if (current == null || current.isEmpty) return;

      // 1) 直接向页面要路由数据
      var state = await _readRouterState(controller);

      // 2) 兜底：读整页 HTML，离线提取（覆盖数据挂在别的全局变量上的情况）
      state ??= await _readFromHtml(controller);

      if (state != null) {
        _finish(state, awemeIdFromUrl(current));
        return;
      }

      // 3) 兜底：页面已渲染出播放器时，直接从 DOM 抓播放地址
      final fromDom = await _readFromDom(controller, awemeIdFromUrl(current));
      if (fromDom != null) {
        _close(ParseSheetResult.success(fromDom));
        return;
      }

      // 4) 已有作品 ID，但当前不在 iesdouyin 分享页 → 主动跳过去
      final id = awemeIdFromUrl(current);
      if (id != null &&
          !current.contains('iesdouyin.com/share') &&
          _shareLoads < 2) {
        _shareLoads++;
        _setStatus('已定位作品，正在读取数据…');
        await controller.loadRequest(
          Uri.parse('https://www.iesdouyin.com/share/video/$id/'),
        );
      }
    } on Exception {
      // WebView 尚未就绪等瞬时异常，等下一轮再试
    } finally {
      _checking = false;
    }
  }

  Future<Map<String, dynamic>?> _readRouterState(WebViewController c) async {
    final raw = await c.runJavaScriptReturningResult(
      'window._ROUTER_DATA ? JSON.stringify(window._ROUTER_DATA) : "null"',
    );
    return _decodeJsonPayload(raw);
  }

  Future<Map<String, dynamic>?> _readFromHtml(WebViewController c) async {
    final raw = await c.runJavaScriptReturningResult(
      'document.documentElement.outerHTML',
    );
    var html = raw.toString();
    if (html.startsWith('"')) {
      try {
        final inner = jsonDecode(html);
        if (inner is String) html = inner;
      } on FormatException {
        // 保持原样，交给 extractRouterData 尝试
      }
    }
    if (html.isEmpty) return null;
    return extractRouterData(html);
  }

  /// 页面已渲染出播放器时，直接从 DOM 抓播放地址与标题。
  /// 这是 _ROUTER_DATA 被抖音移除后的最后一条数据通道。
  Future<VideoInfo?> _readFromDom(WebViewController c, String? urlId) async {
    final raw = await c.runJavaScriptReturningResult('''
(function() {
  var v = document.querySelector('video');
  var src = '';
  if (v) {
    var s = v.querySelector('source');
    src = v.src || (s ? s.src : '');
  }
  if (!src) {
    var og = document.querySelector('meta[property="og:video:url"], meta[property="og:video"], meta[property="og:video:secure_url"]');
    src = og ? og.content : '';
  }
  return JSON.stringify({src: src || '', title: document.title || ''});
})()
''');

    final payload = _decodeJsonPayload(raw);
    if (payload == null) return null;

    final src = (payload['src'] as String?) ?? '';
    if (src.isEmpty || !src.startsWith('http')) return null;

    final docTitle = ((payload['title'] as String?) ?? '').trim();
    final id = urlId ?? '';

    return VideoInfo(
      awemeId: id,
      type: 'video',
      title: docTitle.isEmpty ? '抖音作品 ${id.isEmpty ? '' : id}' : docTitle,
      author: const Author(nickname: '未知作者'),
      stats: const Stats(),
      playUrl: normalizePlayUrl(src),
      qualities: [Quality(label: '默认', url: normalizePlayUrl(src), isDefault: true)],
    );
  }

  /// WebView 返回的字符串结果在 Android 上会再被 JSON 编码一层（带引号与转义），
  /// 需要先剥掉外层，再反序列化成 Map。
  Map<String, dynamic>? _decodeJsonPayload(Object? raw) {
    var text = raw?.toString() ?? '';
    if (text.isEmpty || text == 'null' || text == 'undefined') return null;

    if (text.startsWith('"')) {
      try {
        final inner = jsonDecode(text);
        if (inner is String) text = inner;
      } on FormatException {
        // 不是合法的 JSON 字符串，按原文继续
      }
    }
    if (text.isEmpty || text == 'null') return null;

    try {
      final value = jsonDecode(text);
      if (value is Map) return value.cast<String, dynamic>();
    } on FormatException {
      // 数据还没就绪
    }
    return null;
  }

  // ---------------------------------------------------------- 结果

  void _finish(Map<String, dynamic> state, String? urlId) {
    if (_finished) return;
    try {
      final info = videoInfoFromRouterData(state, fallbackId: urlId);
      _close(ParseSheetResult.success(info));
    } on DouyinException catch (e) {
      _fail(e.message);
    }
  }

  void _fail(String message) {
    _close(ParseSheetResult.failure(message));
  }

  void _close(ParseSheetResult result) {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    _overall?.cancel();
    if (mounted) Navigator.of(context).pop(result);
  }

  void _setStatus(String text) {
    if (!mounted || _finished) return;
    setState(() => _status = text);
  }

  // ---------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.68;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: _line),
          Expanded(
            child: _controller == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: _brand, strokeWidth: 2.5),
                        SizedBox(height: 12),
                        Text(
                          '正在启动内嵌浏览器…',
                          style: TextStyle(fontSize: 13, color: _ink3),
                        ),
                      ],
                    ),
                  )
                : WebViewWidget(controller: _controller!),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFFCFCFD),
              border: Border(top: BorderSide(color: _line)),
            ),
            child: const Text(
              '解析通过内嵌浏览器在本机完成，过程可见、不留存、不上传任何数据。',
              style: TextStyle(fontSize: 11.5, color: _ink3, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(color: _brand, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20, color: _ink3),
            tooltip: '取消',
          ),
        ],
      ),
    );
  }
}
