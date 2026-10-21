# 抖音视频备份 · Android App

Flutter 实现的抖音视频备份工具。**解析与下载全部在手机本地完成，不带后台服务、不收集任何数据。**

---

## 功能

| 功能 | 说明 |
| --- | --- |
| 视频备份 | 用 `play_addr.uri` 请求 `/aweme/v1/play/?video_id=…&ratio=1080p`，拿到 1080P 原画地址 |
| 系统分享目标 | 抖音「分享 → 更多/系统分享 → 抖音视频备份」，直接进 App 自动解析；繁忙时排队等空闲 |
| 剪贴板自动检测 | 启动 App 或从抖音切回时自动识别剪贴板里的抖音链接，弹窗确认后直接解析 |
| 自动下载开关 | 开启后，解析成功即自动保存视频到相册，无需再点按钮（设置项本地持久化） |
| 一键读取剪贴板 | 从抖音复制链接后直接进 App 点一下即可，不用手动粘贴 |
| 多清晰度 | 按短边像素降序排列，默认选最清晰档；地址失效自动换 CDN 线路 / 降档 |
| 画质校验 | 下载后读取 MP4 容器真实分辨率并在提示里报告，避免「标称 1080P 实际 720P」 |
| 保存到相册 | 视频/图片直接写入系统相册（自动建「抖音视频备份」相册） |
| 封面 / 原声 | 单独下载作品封面与背景音乐音轨 |
| 图文作品 | 自动识别图文帖，九宫格展示，点图即保存原图 |
| 解析历史 | 最近 10 条记录存于本机，可一键回看 |
| 下载进度 | 实时百分比进度，失败给出可读的中文原因 |

---

## 系统分享目标（比复制粘贴更短的入口）

App 注册了 `ACTION_SEND` + `text/plain`，抖音里「分享 → 更多/系统分享」的列表里会出现
「抖音视频备份」，点一下直接进 App 自动解析，不再需要复制链接、切 App、点确认。

配合「自动下载视频」开关，整条链路是：分享 → 更多 → 抖音视频备份 → 视频已在相册。

实现要点（改这三处）：

| 文件 | 作用 |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | `<intent-filter>` 声明 `ACTION_SEND` + `text/plain` |
| `android/.../MainActivity.kt` | `MethodChannel("douyin/share")`；冷启动缓存 `pendingShare`，热启动 `onNewIntent` 推送 |
| `lib/services/share_receiver.dart` + `home_page.dart` | 冷启动 `getInitialShare` 拉取、热启动 `onShare` 监听；解析/下载中收到的分享排队等空闲 |

> 为什么两条通道都要写：`launchMode="singleTop"` 下，App 在后台时不会重建 Activity，
> 只走 `onNewIntent`；App 没运行时才走 `getIntent`。只写一条就会出现「第一次能进、第二次没反应」。
> `pendingShare` 采用「取走即清空」，否则 `getIntent()` 会返回同一个 Intent，导致重复解析。

### 验证命令（冷启动 / 热启动各测一次）

```bash
# 冷启动：先杀掉 App
adb shell am force-stop com.dybackup.app
adb shell am start -a android.intent.action.SEND -t text/plain \
  --es android.intent.extra.TEXT "复制打开抖音 https://v.douyin.com/xxxxx/ 看看" \
  -n com.dybackup.app/.MainActivity

# 热启动：保持 App 在后台，再执行同一条 am start
```

注意事项：

1. 抖音的分享面板把系统分享入口放在「更多」里，位置由抖音决定，无法调整。
2. 部分国产 ROM（MIUI / EMUI / HarmonyOS）会缓存分享目标列表，刚装完可能不出现，重启手机后刷新。
3. 只接收纯文本；图片/视频的 `EXTRA_STREAM` 分享不会命中本入口，这是刻意的。
4. `v.douyin.com` 的 `assetlinks.json` 不在本项目手里，无法做 App Links 直达，系统分享是唯一零门槛入口。

> **实测结论（2026-10）**：抖音 App 用的是自家私有分享面板，只展示合作白名单（微信 / QQ 系），
> 第三方 App 无法注册进去。所以对抖音而言，系统分享入口**不会出现**；
> 真正可用的是下面的「解析剪贴板」快捷入口。

### 解析剪贴板快捷入口（对抖音的最短路径）

抖音点「分享」时会自动把链接复制到剪贴板，配合桌面快捷入口即可两步完成：

| 入口 | 使用方式 | 实现 |
| --- | --- | --- |
| 桌面长按快捷方式 | 长按「抖音视频备份」图标 → 点「解析剪贴板」 | `res/xml/shortcuts.xml` + Manifest `<meta-data android:name="android.app.shortcuts">` |

通过自定义 action `com.dybackup.app.PARSE_CLIPBOARD` 拉起 `MainActivity`，
由 `MethodChannel("douyin/share")` 通知 Dart 读取剪贴板并直接解析。若剪贴板为空会重试 3 次
（Android 10+ 只允许前台 App 读剪贴板，冷启动拉起时需要有短暂等待）。

> 曾实现过通知栏快捷磁贴（`TileService`），在国产 ROM 上点击行为不可控，已移除。

验证命令：

```bash
# 桌面快捷方式等价命令
adb shell am start -a com.dybackup.app.PARSE_CLIPBOARD \
  -n com.dybackup.app/.MainActivity
```

---

## 环境要求

- Flutter 3.47+（Dart 3.13+）
- Android SDK（build-tools 36、platform 36）
- JDK 17+（可用 Android Studio 自带的 JBR）

> **本工程必须放在纯 ASCII 路径下**，例如 `D:\dev\douyin-downloader-app`。
> 放在含中文的目录（如「编码空间」）会导致 AGP 在 Dart AOT 阶段把路径写成乱码
> （`编码空间` → `����ռ�`）而编译失败；`android.overridePathCheck=true` 只能消掉警告，
> 无法修复底层的路径编码损坏。

**当前工程位置：`D:\dev\douyin-downloader-app`**

---

## 构建与安装

### 方式一：一键脚本（推荐）

双击 `build_apk.bat`。脚本已内置本机所需的环境变量（见下节），会依次执行
`pub get` → `dart analyze` → `build apk --release`。

### 方式二：命令行

```bash
cd /d/dev/douyin-downloader-app

# 1) Gradle 缓存与临时目录都指向 D 盘
#    C 盘空间不足时，Gradle 在 mergeReleaseNativeLibs 阶段会因磁盘写满而失败
export GRADLE_USER_HOME="D:/dev-cache/gradle-home"
export TMP="D:/dev-cache/tmp"
export TEMP="D:/dev-cache/tmp"

# 2) 若你的 shell 设置了 HTTP_PROXY，必须先排除本机回环地址，
#    否则 flutter test / build 会因 WebSocket 走代理而失败
export NO_PROXY="localhost,127.0.0.1,::1"
export no_proxy="localhost,127.0.0.1,::1"

flutter pub get
flutter test                      # 跑单元测试（25 个用例）
flutter build apk --release       # 产物：build/app/outputs/flutter-apk/app-release.apk
```

### 产物

| 项目 | 值 |
| --- | --- |
| 路径 | `dist/douyin-downloader-v1.0.2.apk` |
| 大小 | 50.2 MB（含 arm64-v8a / armeabi-v7a / x86_64 三架构） |
| 包名 | `com.dybackup.app` |
| 版本 | 1.0.2 (versionCode 3) |
| targetSdk | 36 |

> v1.0.0（纯 HTTP 解析，已失效）与 v1.0.1（首个 WebView 版本）归档在 `dist/`，请使用 1.0.2。

把 APK 传到手机上安装即可（需在系统里允许「安装未知来源应用」）。

> **签名说明**：当前 release 包使用 Flutter 默认的 debug keystore 签名，仅适合自装自用。
> 若要分发给他人或上架应用商店，需在 `android/app/build.gradle.kts` 中配置正式 keystore，
> 否则不同签名的版本无法覆盖安装，也无法上架。

调试运行：`flutter run`（需连接真机或启动模拟器）。

若需减小分发体积，可按架构拆包：
`flutter build apk --release --split-per-abi`（每个架构约 17 MB）。

### 常见坑

**编译报 `磁盘空间不足` / `Execution failed for task ':app:mergeReleaseNativeLibs'`**
C 盘被占满。Gradle 的 transform 产物写在 `GRADLE_USER_HOME/caches` 下，
把它指到空间充裕的盘（本机为 `D:`）即可。

**编译报 `this and base files have different roots`**
Kotlin 增量编译用 `relativeTo()` 计算相对路径，当 Flutter 插件的 `.kt` 源码
（位于 `C:\Users\<用户>\AppData\Local\Pub\Cache`）与工程不在同一个盘符时会抛异常。
本工程已在 `android/gradle.properties` 中设置 `kotlin.incremental=false` 规避。

**`Your project path contains non-ASCII characters`**
工程放在含中文的路径下。把工程移到纯 ASCII 路径，光加
`android.overridePathCheck=true` 不够——它只跳过检查，后续 Dart AOT 仍会因路径乱码失败。

**`Invalid WebSocket upgrade request` / 分析服务器退出 255**
shell 里设了 `HTTP_PROXY` 但没设 `NO_PROXY`，flutter 连接本机 `127.0.0.1` 的测试进程被走了代理。按上面加上 `NO_PROXY` 即可。

**`flutter analyze` 崩溃但 `dart analyze` 正常**
分析服务器进程的启动问题，与代码无关。改用 `dart analyze .`，检查效果一致。

**相册里看不到保存的文件**
Android 13+ 需授予相册访问权限；首次保存时系统会弹窗，选「允许」。若曾拒绝，需到「系统设置 → 应用 → 抖音视频备份 → 权限」里手动打开。

---

## 正式签名（release keystore）

`android/app/build.gradle.kts` 会读取 `android/key.properties` 配置 release 签名；
该文件不存在时自动回退 debug 签名（方便他人 clone 后直接编译，但产物不能上架）。

| 项 | 值 |
| --- | --- |
| keystore 文件 | 放在工程目录之外，例如 `D:\keys\your-release.jks`（**不要放进仓库**） |
| 别名 alias | 自己设置，不写入本文件 |
| 算法 / 有效期 | RSA 2048 / 10000 天 |
| 证书 CN | `CN=DY Video Download, O=DYVideo, L=Chongqing, ST=Chongqing, C=CN` |
| SHA-256 | `0f637298f49b1a19167e294c8ae74be6ebc1ce8da3db59a97e3468a5898ee170` |

> 上面两行（证书 CN 与 SHA-256）属于公开信息：它们写在每个 APK 的签名块里，
> 任何人 `apksigner verify --print-certs` 都能读到。它们的作用是证明「同一个开发者发的包」，
> 无法反推出私钥。**真正需要保密的是 keystore 文件与两个密码。**

`android/key.properties` 与 `*.jks` 已加入 `.gitignore`，**不要提交**。

> **必须备份两处**：keystore 文件 + 密码。丢失后无法再发布可覆盖旧版的升级包，
> 只能更换包名重新开始。建议一份放网盘保险箱、一份放本地离线介质。

校验产物签名（`apksigner` 在 Android SDK 的 `build-tools/<版本>/` 下）：

```bash
export JAVA_HOME="$LOCALAPPDATA/Programs/Android Studio/jbr"
"$LOCALAPPDATA/Android/Sdk/build-tools/36.0.0/apksigner.bat" \
  verify --print-certs dist/dybackup-v1.2.7.apk
```

换成正式签名后，之前用 debug 签名安装的旧版本**必须卸载重装**，无法覆盖升级。

---

## 在线更新（v1.2.1 起）

抖音改接口、修好之后，用户不必重新找安装包：App 启动时会静默检查一次版本清单，
有新版本就提示下载并拉起系统安装器。

| 环节 | 实现 |
| --- | --- |
| 版本清单 | `latest.json`，含 versionCode / 下载地址 / sha256 / 更新说明 |
| 完整性 | 清单原文做 HMAC-SHA256 签名，下载完再核对 APK 的 sha256 |
| 检查时机 | 启动后延迟 3 秒静默检查；「使用说明」页也有手动入口 |
| 提醒节流 | 同一版本 24 小时内只提示一次；强制更新可跳过节流 |
| 安装 | FileProvider + `ACTION_VIEW`，需 `REQUEST_INSTALL_PACKAGES` 权限 |

服务端只有一个静态目录，**没有数据库、没有账号体系**：

```
publish/
  latest.json
  dybackup-v1.2.7.apk
```

发版三步（详见 `tools/server/README.md`）：

```bat
flutter build apk --release
python tools\server\make_manifest.py --apk build\app\outputs\flutter-apk\app-release.apk ^
    --base-url http://你的公网IP:8080 --notes "修复解析"
python tools\server\serve.py --port 8080
```

### 地址与密钥怎么配

**不在代码里改。** 两者都从 `tools/server/secret.env` 注入（该文件被 gitignore）：

```ini
MANIFEST_KEY=你的随机密钥
MANIFEST_URL=http://你的地址:8080/latest.json
```

- `build_apk.bat` 读它 → 拼成 `--dart-define=...` 打进 App；
- `make_manifest.py` 读它的 `MANIFEST_KEY` → 用它给清单签名。

第一次使用先复制模板：`copy tools\server\secret.env.example tools\server\secret.env`。

**没有 secret.env 也能构建**，只是 App 的在线更新会被禁用（解析、下载不受影响）。
手动构建时也可以直接传参：

```bash
flutter build apk --release \
  --dart-define=MANIFEST_URL=http://你的地址:8080/latest.json \
  --dart-define=MANIFEST_KEY=你的密钥
```

> **签名密钥是对称的**：它挡得住半路劫持改地址（低成本中间人），挡不住愿意逆向
> 安装包的职业攻击者。验证阶段够用；正式商业化前应换成非对称验签（私钥只在电脑上）。

> **更新弹窗的体验边界**：Android 侧载 App 无法静默安装，每次都要用户点一次系统确认，
> 部分国产 ROM（华为纯净模式、小米安全检测）还会再拦一道。因此升级成功率不是 100%，
> 「使用说明」页保留了手动下载兜底。

---

## 目录结构

```
lib/
├── main.dart                      App 入口与主题
├── models/
│   └── video_info.dart            作品数据模型（含 JSON 序列化）
├── services/
│   ├── douyin_parser.dart         解析核心：链接提取 / 字段解析 / 原HTTP方案
│   ├── download_service.dart      带防盗链请求头的下载 + 保存到相册
│   └── history_service.dart       历史记录（SharedPreferences）
└── pages/
    ├── home_page.dart             主界面
    └── parse_sheet.dart           WebView 解析面板（四层提取兜底）

test/
├── parser_test.dart               解析逻辑单元测试
└── app_test.dart                  界面冒烟测试

build_apk.bat                      一键构建脚本（含本机环境变量）
dist/                              归档的 APK 产物
```

---

## 解析原理

### 2026-10 抖音改版（重要）

原先「短链 302 取 ID → 请求 iesdouyin 分享页 SSR → 提取 `window._ROUTER_DATA`」的方案已失效：

| 环节 | 现在的表现 |
| --- | --- |
| 短链 `v.douyin.com/xxx` | 302 直接跳到 `www.douyin.com` 首页，**丢失作品 ID**（换 UA / 带 Cookie / 带 Referer / 真实浏览器均无效） |
| 分享页 `iesdouyin.com/share/video/{id}/` | 页面能打开，但 `_ROUTER_DATA.loaderData` 里**已无 `videoInfoRes`**，只剩页面元信息 |
| 纯 HTTP 请求分享页 | 返回 2.4KB 的 `argus-csp-token` 反爬挑战页（`__ac_nonce` + acrawler JSVM） |

### 当前方案：内嵌 WebView

真实浏览器引擎能执行反爬挑战脚本、种下 Cookie，因此解析交给 `webview_flutter` 完成：

```
分享文案 ──提取 URL──▶ 内嵌 WebView 加载短链
                            │ 挑战脚本自动执行、种 Cookie、跳转
                            ▼
                    每 1 秒检测一次当前页面，按以下顺序尝试提取：
                    ① window._ROUTER_DATA（若结构恢复可用则直接命中）
                    ② 整页 HTML 离线提取（覆盖数据挂到别的全局变量）
                    ③ DOM 里的 <video> src / og:video（页面已渲染播放器时）
                    ④ 已拿到 ID 但不在分享页 → 主动跳 iesdouyin 分享页再走 ①②③
                            │
                            ▼
                    playwm → play = 直接播放地址
```

解析面板以底部弹层展示，过程可见、可随时取消，全部在本机完成。

> **实测结论（2026-10-19）**：真机 Android WebView 可以正常通过抖音风控并成功下载视频。
> 注意：同样的流程在 PC 端的无头 Chromium（即使抹掉 `navigator.webdriver`）会失败，
> 抖音对无头桌面浏览器与真机 WebView 的风控判定不同，**可行性必须以真机为准**。

> 若四层都没有命中，说明抖音进一步收紧了网页端：可先判定链接是否有效
> （把链接粘到手机浏览器，若也看不到视频则链接已失效）。
> 彻底失效时只能改走后端方案（活跃维护的开源解析项目 / 第三方解析 API / 逆向签名）。

### 保留的纯 HTTP 实现

`lib/services/douyin_parser.dart` 里的 `DouyinParser` 仍是原 HTTP 方案，
作为解析核心的字段处理层继续使用（`buildVideoInfo` / `extractRouterData` 等），
单测也覆盖了这部分逻辑。移植到 Dart 时的两处关键实现细节：

**一、JSON 截取改为手写括号配对扫描**
Python 用 `json.JSONDecoder().raw_decode()` 能从任意位置精确截出 JSON；Dart 没有对应能力。若用正则匹配 `{...}`，一旦字符串字面量里出现 `}` 就会提前截断。因此 `_scanBalancedJson()` 逐字符扫描，并正确处理字符串状态与反斜杠转义。测试里专门覆盖了这个场景。

**二、手动跟随重定向**
Dart 的 `http` 包无法读取跳转后的最终 URL，因此关闭自动跳转（`followRedirects = false`），自己跟 302 链并读取 `Location`，才能取出 `aweme_id`。

---

## 已知限制

- **仅支持 Android**。iOS 需另做侧载方案（免费证书 7 天过期）。
- **没有内置播放器**。视频需下载后在系统相册里播放。
- **直链有时效**。抖音视频地址带签名，解析后放置过久会失效，重新解析一次即可。
- **原声存到 App 外部目录**。系统相册不接受音频，因此原声保存在 App 专属目录下。
- **未做系统分享目标**。目前需在 App 内粘贴链接；注册为分享目标后可实现「抖音 → 分享 → 直达下载」。

---

## 免责声明

本工具仅用于个人学习研究与合理使用（下载公开可访问的内容）。

请遵守您所在地区的法律法规以及抖音的服务条款，尊重创作者与版权所有者的权益。**请勿用于商业用途、侵权用途，或批量下载、再分发受版权保护的内容。** 使用本工具产生的一切后果由使用者自行承担。
