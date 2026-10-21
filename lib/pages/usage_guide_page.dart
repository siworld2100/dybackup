import 'package:flutter/material.dart';

import '../services/download_service.dart';
import '../services/native_app.dart';
import '../services/update_service.dart';
import '../widgets/update_flow.dart';

const Color _bg = Color(0xFFF6F7F9);
const Color _ink = Color(0xFF161823);
const Color _ink2 = Color(0xFF4A4F5C);
const Color _ink3 = Color(0xFF858B99);
const Color _line = Color(0xFFE9EAEE);
const Color _brand = Color(0xFFFE2C55);
const Color _bgSoft = Color(0xFFF6F7F9);

/// 使用说明页。
///
/// 这一页承担三个职责：教新用户跑通一次、回答「为什么失败」、放赞赏入口。
/// 前两个决定了 App 的口碑，第三个决定了它能不能有一点收入。
class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UsageGuidePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: const Text(
          '使用说明',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _ink,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: const [
          _SectionTitle('三步上手'),
          _StepsCard(),
          SizedBox(height: 18),
          _SectionTitle('更快的两个入口'),
          _ShortcutCard(),
          SizedBox(height: 18),
          _SectionTitle('文件保存在哪里'),
          _StorageCard(),
          SizedBox(height: 18),
          _SectionTitle('常见问题'),
          _FaqCard(),
          SizedBox(height: 18),
          _SectionTitle('赞赏支持'),
          _RewardCard(),
          SizedBox(height: 18),
          _AboutCard(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 通用组件

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _ink3,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text, {this.color = _ink2});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13.5, color: color, height: 1.65),
    );
  }
}

// ---------------------------------------------------------------- 各分区

class _StepsCard extends StatelessWidget {
  const _StepsCard();

  static const _steps = [
    ('复制链接', '在抖音视频页点「分享」，选择「复制链接」。复制整段分享文案也可以，App 会自动挑出链接。'),
    ('粘贴解析', '回到本 App，链接会自动填进输入框（也可以手动粘贴），点「解析」。'),
    ('保存到相册', '解析成功后点「保存视频」。完成时提示里会写明实际分辨率。'),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: _line),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _brand,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].$1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _Body(_steps[i].$2),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 20, color: _brand),
              SizedBox(width: 8),
              Text(
                '桌面长按图标',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const _Body('长按桌面上的 App 图标，会弹出「备份剪贴板链接」。点它直接读剪贴板里的链接并解析，省掉粘贴这一步。'),
          const SizedBox(height: 14),
          const Row(
            children: [
              Icon(Icons.content_paste_go_outlined, size: 20, color: _brand),
              SizedBox(width: 8),
              Text(
                '剪贴板自动检测',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const _Body('从抖音复制链接后切回本 App，会自动识别并询问是否解析。'
              '注意 Android 10 起系统只允许前台 App 读剪贴板，所以必须先切回 App 才会触发。'),
        ],
      ),
    );
  }
}

class _StorageCard extends StatelessWidget {
  const _StorageCard();

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Body('视频、图片、封面、原声都保存进系统相册，相册名为「抖音视频备份」。'),
          const SizedBox(height: 10),
          const _Body('部分机型相册需要下拉刷新或重启相册 App 才能看到新文件；'
              '文件实际路径在 DCIM 或 Pictures 下的「抖音视频备份」目录。'),
          const SizedBox(height: 10),
          const _Body('卸载 App 不会删除已经保存到相册的文件。'),
        ],
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  const _FaqCard();

  static const _faqs = [
    (
      '解析失败了怎么办',
      '先把同一条链接粘到手机浏览器里打开。如果浏览器也打不开，说明链接已失效，回抖音重新复制一次即可。'
          '如果浏览器能打开但 App 不行，多半是抖音又改版了，点本页底部的「检查更新」看有没有修复版。',
    ),
    (
      '安装新版时提示「应用未安装」',
      '通常是下载不完整，或与已安装版本的签名不一致。重新下载一次；仍不行就先卸载旧版再安装'
          '（卸载只会丢解析历史，不影响相册里已经保存的视频）。',
    ),
    (
      '相册里找不到刚保存的文件',
      '下拉刷新相册，或重启相册 App。也可以直接到文件管理的 DCIM / Pictures 目录下找「抖音视频备份」。',
    ),
    (
      '能下载私密或好友可见的作品吗',
      '不能。App 只能读取公开可见的作品，仅自己可见、好友可见、付费内容都拿不到。',
    ),
    (
      '会上传我的数据吗',
      '解析和下载全部在手机本地完成，视频内容不上传、不留存、不经过任何服务器。'
          '唯一的联网请求是检查新版本时读取一份版本清单，里面没有任何个人信息。',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < _faqs.length; i++)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedAlignment: Alignment.topLeft,
                iconColor: _ink3,
                collapsedIconColor: _ink3,
                title: Text(
                  _faqs[i].$1,
                  style: const TextStyle(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w500,
                    color: _ink,
                  ),
                ),
                children: [_Body(_faqs[i].$2)],
              ),
            ),
        ],
      ),
    );
  }
}

class _RewardCard extends StatefulWidget {
  const _RewardCard();

  @override
  State<_RewardCard> createState() => _RewardCardState();
}

class _RewardCardState extends State<_RewardCard> {
  final DownloadService _downloader = DownloadService();
  bool _saving = false;

  /// 长按赞赏码：先落成相册里的一张真实图片，再引导去微信扫一扫。
  ///
  /// 为什么必须走这条路：赞赏码的二维码内容是 `wxp://` 私有支付协议，
  /// 微信从未对外开放唤起接口；微信支付的官方通道又都要求企业商户号。
  /// 个人开发者能走通的只有「存图 + 引导扫码」这一条。
  Future<void> _saveAndGuide() async {
    if (_saving) return;
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _downloader.saveAssetImage(
        'assets/reward_qr.png',
        'dybackup-reward-qr.png',
      );
    } on DownloadException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFD92D20),
        ),
      );
      return;
    } on Exception {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('保存失败，请检查相册权限后重试'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFD92D20),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '赞赏码已保存到相册',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: _ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _Body('微信不允许其他 App 直接打开扫一扫，需要你在微信里点两下：'),
            SizedBox(height: 10),
            _Body('1  打开微信，点右上角「+」', color: _ink),
            _Body('2  选「扫一扫」，点右下角「相册」', color: _ink),
            _Body('3  选最新那张「赞赏码」', color: _ink),
            SizedBox(height: 8),
            _Body('图片存在相册的「抖音视频备份」文件夹里。', color: _ink3),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('稍后', style: TextStyle(color: _ink3)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('打开微信'),
          ),
        ],
      ),
    );

    if (open != true || !mounted) return;

    final result = await NativeApp.openWeChatScan();
    if (!mounted) return;
    if (result == 'notInstalled') {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('没有检测到微信，请安装后再扫'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFD92D20),
        ),
      );
    }
  }

  @override
  void dispose() {
    _downloader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        children: [
          const _Body(
            '这个 App 完全免费：没有广告、没有次数限制、没有会员。'
            '如果它帮你留存下了你想留的东西，可以打赏请我喝一杯咖啡。',
          ),
          const SizedBox(height: 8),
          const _Body(
            '如有使用功能问题，可打赏时备注微信，可联系开发者进行修改。',
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onLongPress: _saveAndGuide,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/reward_qr.png',
                    width: 194,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      width: 194,
                      height: 194,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _bgSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _line),
                      ),
                      child: const Text(
                        '赞赏码待放置',
                        style: TextStyle(fontSize: 12.5, color: _ink3),
                      ),
                    ),
                  ),
                ),
                if (_saving)
                  Container(
                    width: 194,
                    height: 194,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x8CFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _brand,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _Body(
            '长按二维码可保存到相册，再用微信「扫一扫 → 相册」完成打赏。',
            color: _ink3,
          ),
          const SizedBox(height: 4),
          const _Body('不打赏也完全不影响任何功能。', color: _ink3),
        ],
      ),
    );
  }
}

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  int _taps = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _customUrl = false;

  @override
  void initState() {
    super.initState();
    UpdateService.hasUrlOverride().then((value) {
      if (mounted) setState(() => _customUrl = value);
    });
  }

  /// 连点版本号 5 次进入地址设置。
  ///
  /// 做成隐藏入口是因为真正使用这个 App 的人不需要知道服务器地址；
  /// 而作者在验证阶段需要反复换 IP，每次都重新打包太费时间。
  void _handleVersionTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap) > const Duration(milliseconds: 900)) {
      _taps = 0;
    }
    _lastTap = now;
    _taps++;
    if (_taps >= 5) {
      _taps = 0;
      _editUpdateUrl();
    }
  }

  Future<void> _editUpdateUrl() async {
    final current = await UpdateService.effectiveManifestUrl();
    if (!mounted) return;

    final controller = TextEditingController(text: current);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '更新服务地址',
          style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: _ink),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '填你电脑上 serve.py 的地址，末尾是 latest.json。'
              '换 WiFi 或公网 IP 变了就改这里，不必重新装包。',
              style: TextStyle(fontSize: 12.5, color: _ink3, height: 1.6),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'http://192.168.1.10:8080/latest.json',
                hintStyle: const TextStyle(fontSize: 12.5, color: Color(0xFFA8ADBA)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('reset'),
            child: const Text('恢复默认', style: TextStyle(color: _ink3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消', style: TextStyle(color: _ink3)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brand),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    if (action == 'reset') {
      await UpdateService.setManifestUrlOverride(null);
    } else {
      final value = action.trim();
      if (value.isEmpty) return;
      if (!value.startsWith('http')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('地址需要以 http:// 或 https:// 开头'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFD92D20),
          ),
        );
        return;
      }
      await UpdateService.setManifestUrlOverride(value);
    }

    final custom = await UpdateService.hasUrlOverride();
    if (!mounted) return;
    setState(() => _customUrl = custom);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('更新地址已保存'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF12A150),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<String>(
            future: NativeApp.versionName(),
            builder: (context, snapshot) {
              final name = snapshot.data ?? '';
              final label = name.isEmpty ? '读取中…' : name;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _handleVersionTap,
                child: Row(
                  children: [
                    const Text(
                      '当前版本',
                      style: TextStyle(fontSize: 13.5, color: _ink2),
                    ),
                    const Spacer(),
                    Text(
                      label,
                      style: const TextStyle(fontSize: 13.5, color: _ink3),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: const BorderSide(color: Color(0xFFF6C6CF)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => checkUpdateAndPrompt(context, silent: false),
              child: const Text(
                '检查更新',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const _Body(
            '如因改版解析失效时，修复版本会从这里发布或联系开发者',
            color: _ink3,
          ),
          if (_customUrl) ...[
            const SizedBox(height: 6),
            const _Body('当前使用自定义更新地址。', color: _ink3),
          ],
        ],
      ),
    );
  }
}
