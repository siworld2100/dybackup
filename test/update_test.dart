import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dybackup/services/update_service.dart';
import 'package:dybackup/widgets/update_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 测试专用密钥。仓库里只有这个假值，真实密钥通过 `--dart-define` 在打包时注入。
const kTestKey = 'unit-test-key-not-secret';

const kTestManifestUrl = 'http://127.0.0.1:8080/latest.json';

/// 清单地址与密钥都改为构建期注入后，测试必须显式给出地址，否则会被判定「未配置」。
void setMockPrefs() {
  SharedPreferences.setMockInitialValues({'update.manifestUrl': kTestManifestUrl});
}

/// 与服务端 `make_manifest.py` 完全一致的签名算法。
String signPayload(String text, {String? key}) {
  return Hmac(sha256, utf8.encode(key ?? kTestKey))
      .convert(utf8.encode(text))
      .toString();
}

Map<String, dynamic> samplePayload({
  int versionCode = 99,
  String? sha256Value,
}) {
  return {
    'versionCode': versionCode,
    'versionName': '1.2.1',
    'url': 'http://127.0.0.1:8080/dybackup.apk',
    'sha256': sha256Value ?? 'a' * 64,
    'size': 1024,
    'notes': '修复解析',
    'force': false,
  };
}

/// 构造一份「payload 是字符串 + sig」的合法信封。
http.Response buildResponse(
  Map<String, dynamic> payload, {
  String? signature,
}) {
  final text = jsonEncode(payload);
  return http.Response(
    jsonEncode({'payload': text, 'sig': signature ?? signPayload(text)}),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

UpdateService serviceWith(http.Response response) {
  return UpdateService(
    client: MockClient((_) async => response),
    manifestKey: kTestKey,
  );
}

void main() {
  // 读版本号要走平台通道，必须先初始化 binding
  TestWidgetsFlutterBinding.ensureInitialized();

  // 清单地址会先读本地覆盖项，没初始化会拿不到 SharedPreferences
  setUp(() => setMockPrefs());

  group('跨语言签名一致性', () {
    // 基准值由 tools/server/make_manifest.py 同款算法（Python json.dumps +
    // ensure_ascii=False + separators==(',',':') + hmac-sha256，密钥 kTestKey）算出。
    // 这条断言的意义：一旦 Python 与 Dart 的序列化/编码出现分歧，
    // 真机上表现为「所有更新都被判定签名失败」，而本地开发看不出来。
    const pythonPayload =
        '{"versionCode":99,"versionName":"1.2.1",'
        '"url":"http://127.0.0.1:8080/dybackup.apk",'
        '"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",'
        '"size":1024,"notes":"修复解析","force":false}';
    const pythonSignature =
        '5881f31dc9b7d68903befa101916fb86e1577ce0a684279d7716cd84eb96f67d';

    test('Dart 算出的 HMAC 与 Python 一致', () {
      expect(signPayload(pythonPayload), pythonSignature);
    });

    test('该基准清单能通过完整校验', () async {
      final service = serviceWith(
        http.Response(
          jsonEncode({'payload': pythonPayload, 'sig': pythonSignature}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      final info = await service.checkForUpdate();
      expect(info, isNotNull);
      expect(info!.versionCode, 99);
      expect(info.notes, '修复解析');
    });
  });

  group('清单验签', () {
    test('签名正确时解析出版本信息', () async {
      final service = serviceWith(buildResponse(samplePayload()));
      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.versionCode, 99);
      expect(info.versionName, '1.2.1');
      expect(info.notes, '修复解析');
      expect(info.force, isFalse);
    });

    test('签名错误时拒绝更新', () async {
      final service = serviceWith(
        buildResponse(samplePayload(), signature: 'b' * 64),
      );
      expect(await service.checkForUpdate(silent: true), isNull);
      expect(
        () => service.checkForUpdate(silent: false),
        throwsA(isA<UpdateException>()),
      );
    });

    test('用错密钥签的清单不被接受', () async {
      final text = jsonEncode(samplePayload());
      final service = serviceWith(
        buildResponse(samplePayload(), signature: signPayload(text, key: '别的密钥')),
      );
      expect(await service.checkForUpdate(silent: true), isNull);
    });

    test('清单内容被替换后签名不再匹配', () async {
      // 先按原始内容签名，再把内容换成更高的版本号 —— 典型的中间人篡改
      final signedText = jsonEncode(samplePayload());
      final tampered = jsonEncode(samplePayload(versionCode: 1000));
      final service = serviceWith(
        http.Response(
          jsonEncode({'payload': tampered, 'sig': signPayload(signedText)}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(await service.checkForUpdate(silent: true), isNull);
    });

    test('缺少签名信封时拒绝', () async {
      final service = serviceWith(
        http.Response(
          jsonEncode(samplePayload()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      expect(await service.checkForUpdate(silent: true), isNull);
    });

    test('HTTP 非 200 时静默失败', () async {
      final service = serviceWith(http.Response('not found', 404));
      expect(await service.checkForUpdate(silent: true), isNull);
    });
  });

  group('提示节流', () {
    test('同一版本在窗口内不再自动提示，换版本号重新提示', () async {
      setMockPrefs();
      final service = UpdateService();

      expect(await service.shouldPrompt(15), isTrue);
      await service.markPrompted(15);

      expect(await service.shouldPrompt(15), isFalse);
      // 发了更高版本就必须重新提示，否则用户永远收不到修复
      expect(await service.shouldPrompt(16), isTrue);
    });

    // 回归测试：曾经在弹窗之前就写入「已提示」，
    // 导致用户按一次取消后，手动检查连续 24 小时毫无反应。
    testWidgets('取消过之后再手动检查，仍然弹出提示', (tester) async {
      setMockPrefs();
      final service = UpdateService(
        client: MockClient(
          (_) async => buildResponse(samplePayload(versionCode: 15)),
        ),
        manifestKey: kTestKey,
      );
      // 模拟「刚刚提示过该版本」
      await service.markPrompted(15);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => checkUpdateAndPrompt(
                    ctx,
                    silent: false,
                    service: service,
                  ),
                  child: const Text('检查'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('检查'));
        // 更新检查要等平台通道（读 versionCode）与 MockClient 的真实异步回调，
        // fake-async 环境下 pumpAndSettle 等不到它们，必须用 runAsync。
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);
    });

    testWidgets('启动静默检查仍在节流窗口内保持安静', (tester) async {
      setMockPrefs();
      final service = UpdateService(
        client: MockClient(
          (_) async => buildResponse(samplePayload(versionCode: 15)),
        ),
        manifestKey: kTestKey,
      );
      await service.markPrompted(15);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => checkUpdateAndPrompt(ctx, service: service),
                  child: const Text('启动检查'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.text('启动检查'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      expect(find.text('发现新版本'), findsNothing);
    });
  });

  group('清单字段校验', () {
    test('versionCode 非法时抛错', () {
      expect(
        () => UpdateInfo.fromJson(samplePayload()..['versionCode'] = 0),
        throwsA(isA<UpdateException>()),
      );
    });

    test('下载地址不是 http 开头时抛错', () {
      expect(
        () => UpdateInfo.fromJson(samplePayload()..['url'] = 'ftp://x/y.apk'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('sha256 长度不对时抛错', () {
      expect(
        () => UpdateInfo.fromJson(samplePayload(sha256Value: 'abc')),
        throwsA(isA<UpdateException>()),
      );
    });

    test('体积换算成 MB', () {
      final info = UpdateInfo.fromJson(samplePayload()..['size'] = 17800000);
      expect(info.sizeText, '17.0 MB');
    });
  });
}
