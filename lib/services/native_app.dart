import 'package:flutter/services.dart';

/// 与 Android 宿主通信的小通道：读版本号、拉起系统安装器。
///
/// 这两件事都不适合用 Dart 侧插件做：
///   * versionCode 是 Android 的构建号，Dart 的 package_info 拿不到（只有 versionName）；
///   * 安装 APK 必须经过 FileProvider + 系统安装器，插件会多引一个依赖。
class NativeApp {
  const NativeApp._();

  static const MethodChannel _channel = MethodChannel('douyin/app');

  /// 当前安装包的 versionCode（读不到时返回 0，调用方按「需要更新」处理前会再校验）。
  static Future<int> versionCode() async {
    try {
      final value = await _channel.invokeMethod<int>('getVersionCode');
      return value ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// 当前安装包的 versionName（如 1.2.0）。
  static Future<String> versionName() async {
    try {
      return await _channel.invokeMethod<String>('getVersionName') ?? '';
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// 是否已获得「安装未知应用」权限。
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳转到系统的「安装未知应用」授权页。
  static Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on PlatformException {
      // 打不开就只能让用户自己去设置里找，不阻断流程
    } on MissingPluginException {
      // 同上
    }
  }

  /// 打开微信（只到首页）。返回值：wechat / notInstalled。
  ///
  /// 微信扫一扫没有第三方唤起方式：`weixin://dl/scan` 会被微信接管并渲染
  /// 「对不起，当前页面无法访问」，比不跳转更糟。所以原生侧只用系统 launcher
  /// intent 打开微信首页，剩下的步骤交给用户。
  static Future<String> openWeChatScan() async {
    try {
      return await _channel.invokeMethod<String>('openWeChatScan') ?? 'notInstalled';
    } on PlatformException {
      return 'notInstalled';
    } on MissingPluginException {
      return 'notInstalled';
    }
  }

  /// 拉起系统安装器。返回值：ok / needPermission / failed。
  static Future<String> installApk(String path) async {
    try {
      return await _channel.invokeMethod<String>('installApk', {'path': path}) ??
          'failed';
    } on PlatformException {
      return 'failed';
    } on MissingPluginException {
      return 'failed';
    }
  }
}
