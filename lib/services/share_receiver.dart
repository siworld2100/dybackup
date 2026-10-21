/// 接收原生侧传入的两种入口：
///   * 系统分享（ACTION_SEND）的文本；
///   * 「解析剪贴板」快捷入口（桌面长按图标 / 通知栏磁贴）。
///
/// 与原生侧约定：
///   * Dart → 原生 `getInitialShare` / `getInitialParse`：冷启动主动拉取一次，取走即清空；
///   * 原生 → Dart `onShare` / `onParseClipboard`：热启动时由 onNewIntent 推送。
library;

import 'package:flutter/services.dart';

class ShareReceiver {
  const ShareReceiver._();

  static const MethodChannel _channel = MethodChannel('douyin/share');

  /// 冷启动时读取一次性分享内容，没有则返回 null。
  static Future<String?> initial() async {
    try {
      final text = await _channel.invokeMethod<String>('getInitialShare');
      return (text == null || text.trim().isEmpty) ? null : text.trim();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 冷启动是否由「解析剪贴板」快捷入口拉起。
  static Future<bool> initialParseClipboard() async {
    try {
      return await _channel.invokeMethod<bool>('getInitialParse') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 监听热启动事件。重复调用会覆盖上一个回调。
  static void listen({
    void Function(String text)? onShare,
    void Function()? onParseClipboard,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onShare':
          if (call.arguments is String && onShare != null) {
            final text = (call.arguments as String).trim();
            if (text.isNotEmpty) onShare(text);
          }
        case 'onParseClipboard':
          onParseClipboard?.call();
      }
      return null;
    });
  }
}
