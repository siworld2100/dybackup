import 'package:flutter/material.dart';

import '../services/update_service.dart';

const Color _ink = Color(0xFF161823);
const Color _ink3 = Color(0xFF858B99);
const Color _brand = Color(0xFFFE2C55);

/// 检查更新并走完「提示 → 下载 → 安装」全流程。
///
/// [silent] 为 true 时（启动静默检查）服务不可达不打扰用户；
/// 为 false 时（用户主动点「检查更新」）会把失败原因说清楚，
/// 否则用户点了按钮没反应，会以为功能坏了。
Future<void> checkUpdateAndPrompt(
  BuildContext context, {
  bool silent = true,
  UpdateService? service,
}) async {
  final svc = service ?? UpdateService();
  final messenger = ScaffoldMessenger.maybeOf(context);
  // 用户主动点的检查不受「24 小时内只提示一次」约束：
  // 节流的目的是别在启动时反复打扰，而不是拒绝用户的明确请求。
  // 否则取消过一次之后，按钮会连续 24 小时毫无反应。
  final manual = !silent;

  UpdateInfo? info;
  try {
    info = await svc.checkForUpdate(silent: silent);
  } on UpdateException catch (e) {
    // 服务不可达、地址填错、签名异常……对用户来说都只意味着「这次没查到新版本」。
    // 真实的失败原因留在日志里，给排查用，不甩到用户脸上。
    debugPrint('检查更新失败：${e.message}');
    if (manual && messenger != null) {
      messenger.showSnackBar(_snack('暂无新版本'));
    }
    return;
  }
  if (!context.mounted) return;

  if (info == null) {
    if (manual && messenger != null) {
      messenger.showSnackBar(_snack('暂无新版本'));
    }
    return;
  }

  if (!manual && !await svc.shouldPrompt(info.versionCode)) return;
  // 记下这次提示，避免随后每次启动都再弹一次
  await svc.markPrompted(info.versionCode);
  if (!context.mounted) return;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '发现新版本',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _ink),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '版本 ${info!.versionName}${info.sizeText.isEmpty ? '' : ' · ${info.sizeText}'}',
            style: const TextStyle(fontSize: 13.5, color: _ink3),
          ),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              info.notes,
              style: const TextStyle(fontSize: 13.5, color: _ink, height: 1.55),
            ),
          ],
          if (info.force) ...[
            const SizedBox(height: 10),
            const Text(
              '当前版本已无法继续使用，需要更新后才能解析新链接。',
              style: TextStyle(fontSize: 12.5, color: _brand, height: 1.5),
            ),
          ],
        ],
      ),
      actions: [
        if (!info.force)
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('稍后', style: TextStyle(color: _ink3)),
          ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _brand),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('立即更新'),
        ),
      ],
    ),
  );

  if (accepted != true || !context.mounted) return;

  await _downloadAndInstall(context, svc, info);
}

Future<void> _downloadAndInstall(
  BuildContext context,
  UpdateService service,
  UpdateInfo info,
) async {
  final progress = ValueNotifier<double>(0);
  final dialogContext = context;
  // 提前取好 messenger：catch 块在 await 之后，直接摸 BuildContext 会触发
  // use_build_context_synchronously，而且此时页面可能已经销毁。
  final messenger = ScaffoldMessenger.maybeOf(context);

  // 下载期间不提供「取消」以外的交互，避免用户重复点击导致多份下载
  showDialog<void>(
    context: dialogContext,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '正在下载更新',
        style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: _ink),
      ),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value == 0 ? null : value,
                minHeight: 6,
                backgroundColor: const Color(0xFFEDEEF2),
                valueColor: const AlwaysStoppedAnimation(_brand),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              value == 0 ? '正在连接…' : '${(value * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12.5, color: _ink3),
            ),
          ],
        ),
      ),
    ),
  );

  try {
    final file = await service.download(
      info,
      onProgress: (p) => progress.value = p,
    );
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();

    final result = await service.install(file);
    if (!dialogContext.mounted) return;

    if (result == 'needPermission') {
      await showDialog<void>(
        context: dialogContext,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            '需要一次授权',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: _ink),
          ),
          content: const Text(
            '系统需要你允许「抖音视频备份」安装应用。已为你打开设置页，'
            '打开「允许安装未知应用」后回到 App 再点一次更新即可。',
            style: TextStyle(fontSize: 13.5, color: _ink, height: 1.6),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _brand),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } else if (result != 'ok') {
      ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
        _snack('安装器启动失败，请到「使用说明」里手动下载', isError: true),
      );
    }
  } on UpdateException catch (e) {
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    messenger?.showSnackBar(
      _snack(e.message, isError: true),
    );
  } on Exception catch (e) {
    if (dialogContext.mounted) Navigator.of(dialogContext).pop();
    messenger?.showSnackBar(
      _snack('更新失败：$e', isError: true),
    );
  } finally {
    progress.dispose();
  }
}

SnackBar _snack(String message, {bool isError = false}) {
  return SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    backgroundColor: isError ? const Color(0xFFD92D20) : const Color(0xFF12A150),
    duration: Duration(seconds: isError ? 4 : 2),
  );
}
