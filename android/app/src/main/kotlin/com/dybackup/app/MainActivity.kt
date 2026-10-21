package com.dybackup.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 宿主 Activity。
 *
 * 额外职责：
 *   1. 接收系统分享（ACTION_SEND + text/plain）；
 *   2. 接收「解析剪贴板」快捷入口（桌面长按图标）；
 *   3. 为在线更新提供版本号读取与 APK 安装拉起。
 *
 * 分享入口两条通道必须都覆盖，否则会出现「第一次能进、第二次没反应」：
 *   冷启动：App 没运行，走 configureFlutterEngine，Dart 侧主动拉取；
 *   热启动：App 在后台，系统不会新建实例（singleTop），走 onNewIntent 主动推送。
 *
 * 待处理数据采用「取走即清空」，因为 getIntent() 会一直返回同一个 Intent，
 * 重复读取会导致同一条链接被反复解析。
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null
    private var appChannel: MethodChannel? = null
    private var pendingShare: String? = null
    private var pendingParseClipboard = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        result.success(pendingShare)
                        pendingShare = null
                    }
                    "getInitialParse" -> {
                        result.success(pendingParseClipboard)
                        pendingParseClipboard = false
                    }
                    else -> result.notImplemented()
                }
            }
        }

        appChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APP_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersionCode" -> result.success(currentVersionCode())
                    "getVersionName" -> result.success(currentVersionName())
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(null)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrEmpty()) {
                            result.success("failed")
                        } else {
                            result.success(installApk(path))
                        }
                    }
                    "openWeChatScan" -> result.success(openWeChatScan())
                    else -> result.notImplemented()
                }
            }
        }

        // 冷启动：此时 Flutter 还没跑起来，先把入口意图暂存
        pendingShare = intent?.shareText()
        pendingParseClipboard = intent?.isParseClipboardRequest() == true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val ch = channel

        if (intent.isParseClipboardRequest()) {
            if (ch == null) {
                pendingParseClipboard = true
            } else {
                ch.invokeMethod("onParseClipboard", null)
            }
            return
        }

        val text = intent.shareText() ?: return
        if (ch == null) {
            pendingShare = text
        } else {
            ch.invokeMethod("onShare", text)
        }
    }

    // ---------------------------------------------------------- 在线更新

    private fun currentVersionCode(): Int {
        return try {
            val info = packageManager.getPackageInfo(packageName, 0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode.toInt()
            } else {
                @Suppress("DEPRECATION")
                info.versionCode
            }
        } catch (e: Exception) {
            0
        }
    }

    private fun currentVersionName(): String {
        return try {
            packageManager.getPackageInfo(packageName, 0).versionName ?: ""
        } catch (e: Exception) {
            ""
        }
    }

    // ---------------------------------------------------------- 微信

    /**
     * 打开微信（只到首页）。
     *
     * 走过的弯路，记在这里避免以后再试：
     * - `weixin://dl/scan`：微信仍然注册着这个 scheme，startActivity 不会抛异常，
     *   但微信接到外部调用后直接渲染「对不起，当前页面无法访问」错误页。
     *   比不跳转更糟——用户会以为 App 坏了。try-catch 也捕不到。
     * - 显式 ComponentName 拉起 BaseScanUI：微信侧 exported=false，会被 SecurityException 拦。
     * - 微信公众号/小程序 URL Scheme：需要企业主体，个人开发者没有。
     *
     * 结论：微信扫一扫不存在第三方唤起方式。这里只用系统标准的 launcher intent
     * 打开微信首页，把「点右上角 → 扫一扫 → 相册」交给用户，绝不传任何私有 scheme。
     */
    private fun openWeChatScan(): String {
        if (!isPackageInstalled(WECHAT_PACKAGE)) return "notInstalled"
        return try {
            val intent = packageManager.getLaunchIntentForPackage(WECHAT_PACKAGE)
                ?: return "notInstalled"
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            "wechat"
        } catch (e: Exception) {
            "notInstalled"
        }
    }

    private fun isPackageInstalled(pkg: String): Boolean {
        return try {
            packageManager.getPackageInfo(pkg, 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun canInstallPackages(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            // 个别 ROM 没有这个设置页，忽略即可，用户可自行到设置里找
        }
    }

    private fun installApk(path: String): String {
        return try {
            val file = File(path)
            if (!file.exists() || file.length() == 0L) {
                "failed"
            } else {
                val uri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    file,
                )
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                startActivity(intent)
                "ok"
            }
        } catch (e: Exception) {
            "failed"
        }
    }

    // ---------------------------------------------------------- 分享

    // 只认 ACTION_SEND + text/plain 这类文本分享，取 EXTRA_TEXT。
    private fun Intent.shareText(): String? {
        if (action != Intent.ACTION_SEND) return null
        if (type?.startsWith("text/") != true) return null
        val text = getStringExtra(Intent.EXTRA_TEXT)?.trim().orEmpty()
        return text.ifEmpty { null }
    }

    private fun Intent.isParseClipboardRequest(): Boolean = action == ACTION_PARSE_CLIPBOARD

    companion object {
        private const val CHANNEL = "douyin/share"
        private const val APP_CHANNEL = "douyin/app"
        private const val WECHAT_PACKAGE = "com.tencent.mm"

        /** 桌面快捷方式使用的自定义 action。 */
        const val ACTION_PARSE_CLIPBOARD = "com.dybackup.app.PARSE_CLIPBOARD"
    }
}
