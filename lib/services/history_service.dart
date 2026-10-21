/// 解析历史记录（存于本机 SharedPreferences，不上传）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_info.dart';

class HistoryService {
  static const String _key = 'douyin_history_v1';
  static const int _maxItems = 10;

  Future<List<VideoInfo>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((e) => VideoInfo.fromJson(e.cast<String, dynamic>()))
          .toList();
    } on Exception {
      return [];
    }
  }

  /// 新增一条记录（同一作品会去重并置顶），返回更新后的列表。
  Future<List<VideoInfo>> add(VideoInfo info) async {
    final list = await load();
    list.removeWhere((item) => item.awemeId == info.awemeId);
    list.insert(0, info);

    final trimmed = list.take(_maxItems).toList();
    await _save(trimmed);
    return trimmed;
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } on Exception {
      // 忽略
    }
  }

  Future<void> _save(List<VideoInfo> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.map((e) => e.toJson()).toList()),
      );
    } on Exception {
      // 存储不可用时忽略，不影响主流程
    }
  }
}
