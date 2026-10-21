import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_app.dart';
import 'update_config.dart';

/// 面向用户可读的更新异常。
class UpdateException implements Exception {
  UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 服务端下发的一次版本描述（已验签）。
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
    required this.force,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final String sha256;
  final int size;
  final String notes;
  final bool force;

  String get sizeText {
    if (size <= 0) return '';
    final mb = size / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// 严格解析，缺字段直接抛错——宁可提示失败，也不要拿半份清单去下载。
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final code = json['versionCode'];
    final url = json['url'];
    final sha = json['sha256'];
    if (code is! int || code <= 0) {
      throw UpdateException('版本清单格式不正确（versionCode）');
    }
    if (url is! String || !url.startsWith('http')) {
      throw UpdateException('版本清单格式不正确（下载地址）');
    }
    if (sha is! String || sha.length != 64) {
      throw UpdateException('版本清单格式不正确（校验值）');
    }
    return UpdateInfo(
      versionCode: code,
      versionName: (json['versionName'] as String?) ?? '新版本',
      url: url,
      sha256: sha.toLowerCase(),
      size: (json['size'] as num?)?.toInt() ?? 0,
      notes: (json['notes'] as String?) ?? '',
      force: json['force'] == true,
    );
  }
}

/// 在线更新：拉清单 → 验签 → 比对版本 → 下载 → 校验 → 拉起安装器。
///
/// 全流程只有一次网络请求是有意义的（清单），其余都在本地完成。
class UpdateService {
  UpdateService({http.Client? client, String? manifestKey})
      : _client = client ?? http.Client(),
        _key = manifestKey ?? UpdateConfig.manifestKey;

  final http.Client _client;

  /// 验签密钥。默认取构建期注入的 [UpdateConfig.manifestKey]；
  /// 单元测试通过构造参数注入固定值，这样仓库里不必保留任何真实密钥。
  final String _key;

  static const _kPromptedCode = 'update.prompted.code';
  static const _kPromptedAt = 'update.prompted.at';
  static const _kUrlOverride = 'update.manifestUrl';

  // ---------------------------------------------------------------- 地址

  /// 实际使用的清单地址：App 内设置过的优先，否则用编译期常量。
  ///
  /// 家宽的公网 IP 会变、局域网 IP 换 WiFi 就会变，把地址写死在包里
  /// 意味着每换一次网络就要重新打包。这个覆盖入口让验证阶段不必反复出包。
  static Future<String> effectiveManifestUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = prefs.getString(_kUrlOverride)?.trim() ?? '';
    return custom.isEmpty ? UpdateConfig.manifestUrl : custom;
  }

  /// 传入 null 或空串即恢复默认地址。
  static Future<void> setManifestUrlOverride(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final value = url?.trim() ?? '';
    if (value.isEmpty) {
      await prefs.remove(_kUrlOverride);
    } else {
      await prefs.setString(_kUrlOverride, value);
    }
  }

  /// 是否正在使用自定义地址（用于界面上给出提示）。
  static Future<bool> hasUrlOverride() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kUrlOverride)?.trim() ?? '').isNotEmpty;
  }

  // ---------------------------------------------------------------- 检查

  /// 拉取最新版本信息。无更新或服务不可达时返回 null，不抛异常。
  ///
  /// [silent] 为 true 时（启动静默检查）把所有异常吞掉并返回 null，
  /// 避免用户每次启动都看到「检查更新失败」这种与他无关的噪音。
  Future<UpdateInfo?> checkForUpdate({bool silent = true}) async {
    try {
      return await _fetch();
    } on UpdateException {
      if (silent) return null;
      rethrow;
    } on TimeoutException {
      if (silent) return null;
      throw UpdateException('连接更新服务超时，请确认电脑端的发布服务已启动');
    } on SocketException {
      if (silent) return null;
      throw UpdateException('连不上更新服务，请检查公网 IP、端口和路由器映射');
    } on http.ClientException {
      if (silent) return null;
      throw UpdateException('更新服务返回异常，请确认地址是否正确');
    } on FormatException {
      if (silent) return null;
      throw UpdateException('版本清单不是合法的 JSON');
    }
  }

  Future<UpdateInfo?> _fetch() async {
    // 从源码直接构建、又没注入地址和密钥时，这里会提前退出。
    // 用异常而不是静默 return，是为了让「手动检查更新」能给出确定的结果。
    if (_key.isEmpty) {
      throw UpdateException('未配置更新签名密钥，已跳过检查');
    }

    final manifestUrl = await effectiveManifestUrl();
    if (manifestUrl.isEmpty) {
      throw UpdateException('未配置更新地址，已跳过检查');
    }

    final res = await _client
        .get(Uri.parse(manifestUrl))
        .timeout(UpdateConfig.requestTimeout);

    if (res.statusCode != 200) {
      throw UpdateException('更新服务返回 HTTP ${res.statusCode}');
    }

    final envelope = jsonDecode(utf8.decode(res.bodyBytes));
    if (envelope is! Map) {
      throw UpdateException('版本清单结构不正确');
    }

    // 服务端把清单原文当作一个字符串字段下发，方便逐字节验签：
    // 若直接下发对象，Python 与 Dart 的键序/转义差异会导致签名对不上。
    final payload = envelope['payload'];
    final sig = envelope['sig'];
    if (payload is! String || sig is! String) {
      throw UpdateException('版本清单缺少签名');
    }

    final expected =
        Hmac(sha256, utf8.encode(_key))
            .convert(utf8.encode(payload))
            .toString();
    if (!_sameText(expected, sig.toLowerCase())) {
      throw UpdateException('版本清单签名校验失败，已拒绝本次更新');
    }

    final map = jsonDecode(payload);
    if (map is! Map<String, dynamic>) {
      throw UpdateException('版本清单内容不正确');
    }

    final info = UpdateInfo.fromJson(map);
    final current = await NativeApp.versionCode();
    if (current > 0 && info.versionCode <= current) return null;
    return info;
  }

  // ---------------------------------------------------------------- 提醒节流

  /// 同一版本在 [UpdateConfig.remindInterval] 内只提示一次。
  Future<bool> shouldPrompt(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCode = prefs.getInt(_kPromptedCode) ?? 0;
    final lastAt = prefs.getInt(_kPromptedAt) ?? 0;
    if (lastCode != versionCode) return true;

    final elapsed = DateTime.now().millisecondsSinceEpoch - lastAt;
    return elapsed >= UpdateConfig.remindInterval.inMilliseconds;
  }

  Future<void> markPrompted(int versionCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPromptedCode, versionCode);
    await prefs.setInt(
      _kPromptedAt,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  // ---------------------------------------------------------------- 下载

  /// 下载安装包到缓存目录，并校验 sha256。
  ///
  /// 校验失败会删掉残包再抛错——半个 APK 留在手机上既没用又占空间。
  Future<File> download(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/dybackup-${info.versionCode}.apk');
    if (await file.exists()) {
      await file.delete();
    }

    final request = http.Request('GET', Uri.parse(info.url));
    final response = await _client.send(request).timeout(
      const Duration(seconds: 30),
    );
    if (response.statusCode != 200) {
      throw UpdateException('下载失败，服务端返回 HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? info.size;
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress?.call((received / total).clamp(0.0, 1.0));
        }
      }
    } on Exception catch (e) {
      await sink.close();
      if (await file.exists()) await file.delete();
      throw UpdateException('下载中断：$e');
    }
    await sink.flush();
    await sink.close();

    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (!_sameText(actual, info.sha256)) {
      await file.delete();
      throw UpdateException('安装包校验失败（可能下载不完整），请重试');
    }

    onProgress?.call(1.0);
    return file;
  }

  /// 拉起系统安装器。返回 ready / needPermission / failed。
  Future<String> install(File apk) async {
    if (!await NativeApp.canInstall()) {
      await NativeApp.openInstallSettings();
      return 'needPermission';
    }
    return NativeApp.installApk(apk.path);
  }

  // ---------------------------------------------------------------- 工具

  /// 定长比较，避免因提前返回而泄露签名差异位置。
  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
