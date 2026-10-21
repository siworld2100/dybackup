import 'package:shared_preferences/shared_preferences.dart';

/// App 设置（SharedPreferences 持久化）。
class SettingsService {
  static const _kAutoDownload = 'auto_download_video';

  /// 是否开启「解析成功后自动下载视频」。
  Future<bool> autoDownloadEnabled() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kAutoDownload) ?? false;
  }

  Future<void> setAutoDownload(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAutoDownload, value);
  }
}
