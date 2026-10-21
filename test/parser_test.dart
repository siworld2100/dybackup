import 'dart:convert';

import 'package:dybackup/services/douyin_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrl 分享文案取链接', () {
    test('从整段分享文案中提取链接', () {
      const text =
          '7.62 fBc:/ 复制打开抖音，看看【某人的作品】 https://v.douyin.com/i5gQ1DVa/ 02/25';
      expect(extractUrl(text), 'https://v.douyin.com/i5gQ1DVa/');
    });

    test('纯链接原样返回', () {
      const url = 'https://www.douyin.com/video/7410058646459075840';
      expect(extractUrl(url), url);
    });

    test('去掉链接结尾的中文标点', () {
      expect(
        extractUrl('看这个 https://v.douyin.com/abc123/。'),
        'https://v.douyin.com/abc123/',
      );
    });

    test('不带协议头的域名自动补 https', () {
      expect(extractUrl('v.douyin.com/abc/'), 'https://v.douyin.com/abc/');
    });

    test('空内容抛错', () {
      expect(() => extractUrl('   '), throwsA(isA<DouyinException>()));
    });

    test('没有链接时抛错', () {
      expect(() => extractUrl('你好，这里没有链接'), throwsA(isA<DouyinException>()));
    });
  });

  group('awemeIdFromUrl 作品 ID 提取', () {
    test('从 /video/ 路径提取', () {
      expect(
        awemeIdFromUrl('https://www.douyin.com/video/7410058646459075840?x=1'),
        '7410058646459075840',
      );
    });

    test('从 modal_id 参数提取', () {
      expect(
        awemeIdFromUrl(
          'https://www.douyin.com/jingxuan?modal_id=7611845735025364265',
        ),
        '7611845735025364265',
      );
    });

    test('短链本身取不到 ID', () {
      expect(awemeIdFromUrl('https://v.douyin.com/abc/'), isNull);
    });
  });

  group('normalizePlayUrl 播放地址归一化', () {
    test('playwm 路径替换为 play', () {
      expect(
        normalizePlayUrl('https://x/aweme/v1/playwm/?video_id=v1'),
        'https://x/aweme/v1/play/?video_id=v1',
      );
    });

    test('已是普通播放地址时保持不变', () {
      const url = 'https://v3-web.douyinvod.com/abc/play/?a=1';
      expect(normalizePlayUrl(url), url);
    });

    test('空字符串安全', () {
      expect(normalizePlayUrl(''), '');
    });
  });

  group('extractRouterData 页面状态提取', () {
    test('提取基础结构', () {
      final html =
          '<html><script>window._ROUTER_DATA = '
          '${jsonEncode({
            'loaderData': {
              'video_(id)/page': {
                'videoInfoRes': {
                  'item_list': [
                    {'desc': '标题'},
                  ],
                },
              },
            },
          })}'
          ';</script></html>';

      final state = extractRouterData(html);
      expect(state, isNotNull);
      expect(state!['loaderData'], isA<Map>());
    });

    test('JSON 字符串内含花括号时不会被提前截断', () {
      // 这是手写括号扫描器相对正则取值的关键优势：
      // desc 里出现 } 和 { 不应该破坏解析
      final trickyDesc = '标题里有 } 和 { 还有 \\" 转义引号';
      final html =
          '<script>window._ROUTER_DATA = '
          '${jsonEncode({
            'loaderData': {
              'video_(id)/page': {
                'videoInfoRes': {
                  'item_list': [
                    {'desc': trickyDesc},
                  ],
                },
              },
            },
          })}'
          ';</script>';

      final state = extractRouterData(html);
      expect(state, isNotNull);
      final item =
          ((state!['loaderData'] as Map)['video_(id)/page'] as Map)['videoInfoRes']
              as Map;
      expect((item['item_list'] as List).first['desc'], trickyDesc);
    });

    test('兼容 window.__INITIAL_STATE__', () {
      final html =
          '<script>window.__INITIAL_STATE__ = ${jsonEncode({'loaderData': <String, dynamic>{}})};</script>';
      expect(extractRouterData(html), isNotNull);
    });

    test('页面里没有状态数据时返回 null', () {
      expect(extractRouterData('<html><body>hello</body></html>'), isNull);
    });
  });

  group('buildVideoInfo 字段解析', () {
    final rawItem = <String, dynamic>{
      'desc': '测试视频标题 #话题',
      'create_time': 1728000000,
      'author': {
        'nickname': '测试作者',
        'unique_id': 'test123',
        'avatar_larger': {
          'url_list': ['https://p3.douyinpic.com/a.jpg'],
        },
      },
      'statistics': {
        'digg_count': 1234567,
        'comment_count': 6789,
        'collect_count': 900,
        'share_count': 12,
      },
      'video': {
        'duration': 15300,
        'cover': {
          'url_list': ['https://p3.douyinpic.com/c.jpg'],
        },
        'play_addr': {
          'url_list': [
            'https://www.douyin.com/aweme/v1/playwm/?video_id=v0300&ratio=720p',
          ],
          'width': 720,
          'height': 1280,
          'data_size': 5242880,
        },
        'bit_rate': [
          {
            'gear_name': 'normal_1080_0',
            'play_addr': {
              'url_list': ['https://v3-web.douyinvod.com/x/playwm/?a=1'],
              'width': 1080,
              'height': 1920,
              'data_size': 10485760,
            },
          },
          {
            'gear_name': 'adapt_540_1',
            'play_addr': {
              'url_list': ['https://v3-web.douyinvod.com/y/play/?b=2'],
              'width': 540,
              'height': 960,
              'data_size': 2097152,
            },
          },
        ],
      },
      'music': {
        'title': '背景音乐',
        'author': '歌手',
        'play_url': {
          'url_list': ['https://sf.douyinstatic.com/m.mp3'],
        },
      },
    };

    test('基础字段', () {
      final info = buildVideoInfo(rawItem, '7410058646459075840');
      expect(info.type, 'video');
      expect(info.isImages, isFalse);
      expect(info.title, '测试视频标题 #话题');
      expect(info.author.nickname, '测试作者');
      expect(info.author.uniqueId, 'test123');
      expect(info.stats.digg, 1234567);
      expect(info.createTime, startsWith('2024-'));
      expect(info.durationText, '0:15');
    });

    test('清晰度地址全部可直连且去重', () {
      final info = buildVideoInfo(rawItem, '1');
      expect(info.qualities.length, 3);
      expect(info.qualities.every((q) => !q.url.contains('playwm')), isTrue);
      expect(info.qualities.where((q) => q.isDefault).length, 1);
      expect(info.playUrl.contains('playwm'), isFalse);
    });

    test('默认下载最清晰档：按短边像素降序，第一档为默认', () {
      final info = buildVideoInfo(rawItem, '1');
      expect(info.qualities.map((q) => q.label).toList(), [
        '1080P',
        '720P',
        '540P',
      ]);
      expect(info.qualities.first.isDefault, isTrue);
      expect(info.qualities.first.pixels, 1080);
      expect(info.qualities.first.size, 10485760);
      // playUrl 跟随最清晰档
      expect(info.playUrl, info.qualities.first.url);
    });

    test('只有 720P 分享地址时，用 uri 构造 1080P 档', () {
      final item = <String, dynamic>{
        'desc': '低清分享页',
        'video': {
          'play_addr': {
            'uri': 'v0300fg10000abcdef',
            'url_list': [
              'https://www.douyin.com/aweme/v1/playwm/?video_id=v0300fg10000abcdef&ratio=720p',
            ],
            'width': 720,
            'height': 1280,
            'data_size': 13369344,
          },
        },
      };

      final info = buildVideoInfo(item, '2');
      expect(info.qualities.first.label, '1080P');
      expect(info.qualities.first.pixels, 1080);
      expect(info.qualities.first.isDefault, isTrue);
      expect(info.qualities.first.url, contains('/aweme/v1/play/'));
      expect(info.qualities.first.url, contains('ratio=1080p'));
      expect(info.qualities.first.url, isNot(contains('playwm')));
      expect(info.qualities.first.mirrors, isNotEmpty);
      // 720P 档仍保留，供用户手动选低画质省流量
      expect(info.qualities.map((q) => q.label), contains('720P'));
    });

    test('图文作品取其原图', () {
      final imageItem = Map<String, dynamic>.from(rawItem)
        ..remove('video')
        ..['images'] = [
          {
            'url_list': [
              'https://p3.douyinpic.com/s.jpg',
              'https://p3.douyinpic.com/big.jpg',
            ],
          },
        ];

      final info = buildVideoInfo(imageItem, '123');
      expect(info.type, 'images');
      expect(info.isImages, isTrue);
      expect(info.images, ['https://p3.douyinpic.com/big.jpg']);
    });

    test('缺少 desc 时用 aweme_id 兜底', () {
      final item = Map<String, dynamic>.from(rawItem)..remove('desc');
      final info = buildVideoInfo(item, '99999');
      expect(info.title, '抖音作品 99999');
      expect(info.safeTitle, '抖音作品 99999');
    });

    test('没有 play_addr 时用 uri 拼接兜底地址', () {
      final item = jsonDecode(jsonEncode(rawItem)) as Map<String, dynamic>;
      (item['video'] as Map)['play_addr'] = {
        'uri': 'v0300abc',
        'url_list': <String>[],
      };
      (item['video'] as Map).remove('bit_rate');

      final info = buildVideoInfo(item, '1');
      expect(info.qualities.length, 1);
      expect(info.playUrl, contains('video_id=v0300abc'));
    });

    test('safeTitle 去掉文件系统非法字符', () {
      final item = Map<String, dynamic>.from(rawItem)
        ..['desc'] = '标题/含:非法*字符?';
      expect(buildVideoInfo(item, '1').safeTitle, '标题_含_非法_字符_');
    });
  });

  group('成品 JSON 往返', () {
    test('toJson / fromJson 保持一致', () {
      final original = buildVideoInfo(<String, dynamic>{
        'desc': '往返测试',
        'author': {'nickname': '作者'},
        'statistics': {'digg_count': 5},
        'video': {
          'play_addr': {
            'url_list': ['https://x/playwm/?v=1'],
          },
        },
      }, '888');

      final restored = jsonDecode(jsonEncode(original.toJson()));
      expect(restored['aweme_id'], '888');
      expect(restored['title'], '往返测试');
      expect(restored['video']['qualities'][0]['url'], contains('/play/?'));
    });
  });
}
