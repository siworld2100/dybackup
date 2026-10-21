import 'package:dybackup/main.dart';
import 'package:dybackup/services/update_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 启动检查更新会留下未完成的定时器并触发真实网络请求，测试里必须关掉
  setUp(() => UpdateConfig.autoCheckOnStartup = false);
  tearDown(() => UpdateConfig.autoCheckOnStartup = true);

  testWidgets('首页渲染出标题、输入框与解析按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DouyinDownloaderApp());
    await tester.pump();

    expect(find.text('抖音视频备份'), findsOneWidget);
    expect(find.text('分享链接'), findsOneWidget);
    expect(find.text('开始解析'), findsOneWidget);
    expect(find.text('读取剪贴板'), findsOneWidget);
  });

  testWidgets('输入为空时点击解析给出提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DouyinDownloaderApp());
    await tester.pump();

    await tester.tap(find.text('开始解析'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('请先粘贴抖音分享链接'), findsOneWidget);
  });
}
