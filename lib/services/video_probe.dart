/// 读取本地 MP4 文件的真实分辨率。
///
/// 用途：抖音 CDN 可能把 1080P 请求降级成 720P 返回，光看请求参数无法判断，
/// 下载完成后直接读容器元数据最可靠（也用于向用户如实报告实际画质）。
///
/// 做法：按 ISO BMFF 结构顺序扫描顶层盒子，进入 `moov` → `trak` → `tkhd`，
/// 取 tkhd 末尾 8 字节的 width/height（16.16 定点数）。不做全文件读取，
/// 只按盒子头跳转，几十 MB 的视频也只需几次 seek。
library;

import 'dart:io';
import 'dart:typed_data';

class VideoSize {
  const VideoSize(this.width, this.height);

  final int width;
  final int height;

  /// 短边像素，竖屏 1080×1920 返回 1080。
  int get shortSide => width < height ? width : height;

  @override
  String toString() => '$width×$height';
}

/// 探测失败返回 null（例如非 MP4、文件损坏、moov 缺失）。
Future<VideoSize?> probeVideoSize(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final total = await raf.length();
    return await _scanBoxes(raf, 0, total, 0);
  } on Exception {
    return null;
  } finally {
    await raf?.close();
  }
}

Future<VideoSize?> _scanBoxes(
  RandomAccessFile raf,
  int start,
  int end,
  int depth,
) async {
  if (depth > 6) return null;
  var offset = start;
  while (offset + 8 <= end) {
    await raf.setPosition(offset);
    final header = await raf.read(8);
    if (header.length < 8) return null;

    var size = _u32(header, 0);
    final type = String.fromCharCodes(header.sublist(4, 8));
    var headerSize = 8;

    if (size == 1) {
      final ext = await raf.read(8);
      if (ext.length < 8) return null;
      size = _u64(ext);
      headerSize = 16;
    } else if (size == 0) {
      size = end - offset;
    }
    if (size < headerSize || offset + size > end) return null;

    final bodyStart = offset + headerSize;
    final bodyEnd = offset + size;

    if (type == 'moov') {
      final found = await _scanBoxes(raf, bodyStart, bodyEnd, depth + 1);
      if (found != null) return found;
    } else if (type == 'trak') {
      final found = await _scanBoxes(raf, bodyStart, bodyEnd, depth + 1);
      if (found != null) return found;
    } else if (type == 'tkhd') {
      final found = await _readTkhd(raf, bodyStart, bodyEnd);
      if (found != null) return found;
    }

    offset = bodyEnd;
  }
  return null;
}

Future<VideoSize?> _readTkhd(
  RandomAccessFile raf,
  int bodyStart,
  int bodyEnd,
) async {
  final length = bodyEnd - bodyStart;
  if (length < 84) return null;
  await raf.setPosition(bodyStart);
  final body = await raf.read(length);
  if (body.length < 84) return null;

  final width = _u32(body, body.length - 8);
  final height = _u32(body, body.length - 4);
  // 16.16 定点：整数部分是像素。音频轨宽高为 0，跳过。
  final w = width >> 16;
  final h = height >> 16;
  if (w <= 0 || h <= 0) return null;
  return VideoSize(w, h);
}

int _u32(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length) return 0;
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _u64(Uint8List bytes) {
  if (bytes.length < 8) return 0;
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value = (value << 8) | bytes[i];
  }
  return value;
}
