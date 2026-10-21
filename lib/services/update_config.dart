/// 在线更新链路的集中配置。
///
/// **本文件不保存任何真实地址或密钥。** 两处取值都在构建期注入：
///
/// ```
/// flutter build apk --release \
///   --dart-define=MANIFEST_URL=http://你的地址:8080/latest.json \
///   --dart-define=MANIFEST_KEY=你的密钥
/// ```
///
/// 仓库里的 `build_apk.bat` 会自动从 `tools/server/secret.env`（已 gitignore）
/// 读取这两个值并拼成上述参数，所以本地打包不需要手敲。
///
/// 未注入时：[manifestUrl] 与 [manifestKey] 都是空串，App 会**安静地跳过**在线更新，
/// 解析与下载功能完全不受影响。
///
/// 为什么升级走明文 HTTP 还能安全：
/// 版本清单是一段被 [manifestKey] 签名的原文，App 先验签再读内容，
/// 安装包下载完还会再核对一遍 sha256。因此中间人即使篡改响应，
/// 也无法把下载地址指向别的 APK —— 唯一泄露的只是「你在下载升级包」这件事本身，
/// 而这份清单里没有任何个人数据。
class UpdateConfig {
  const UpdateConfig._();

  /// 版本清单地址，构建期注入；也可在 App 内临时覆盖
  /// （见 [UpdateService.setManifestUrlOverride]，入口是「使用说明」页连点版本号 5 次）。
  ///
  /// 家宽的公网 IP 会变、局域网 IP 换 WiFi 就会变，所以留了运行时可改的入口，
  /// 验证阶段不必为了换个地址反复出包。
  static const String manifestUrl = String.fromEnvironment('MANIFEST_URL');

  /// 清单签名密钥，必须与 `tools/server/make_manifest.py` 使用的密钥一致。
  ///
  /// 这是对称密钥，会随安装包分发，理论上可从包里逆向取得。它挡住的是
  /// 「半路劫持改地址」这类低成本的中间人，挡不住愿意逆向的职业攻击者。
  /// 真要对抗后者，把这里换成非对称验签（公钥在端上、私钥只在电脑上）。
  static const String manifestKey = String.fromEnvironment('MANIFEST_KEY');

  /// 更新链路是否已配置齐全。缺任意一项就整体禁用，避免发起注定失败的请求。
  static bool get isConfigured => manifestUrl.isNotEmpty && manifestKey.isNotEmpty;

  /// 清单请求超时。启动时的静默检查必须够短，失败就悄悄放弃。
  static const Duration requestTimeout = Duration(seconds: 6);

  /// 同一个版本在多少时间内不重复提醒。
  static const Duration remindInterval = Duration(hours: 24);

  /// 启动后延迟多久再检查，避免和首帧渲染、剪贴板检测抢资源。
  static const Duration startupDelay = Duration(seconds: 3);

  /// 是否允许在启动时自动检查更新。
  ///
  /// 组件测试里必须置为 false：否则会留下一个未完成的定时器并触发真实网络请求，
  /// 测试框架会把「pending timer」直接判为失败。
  static bool autoCheckOnStartup = true;
}
