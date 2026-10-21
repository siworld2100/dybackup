#!/usr/bin/env python3
"""零依赖的静态发布服务器，专门用来发 App 升级包。

为什么不用 `python -m http.server`：
标准库那个不支持 Range 请求。Android 的下载器和系统安装器都会用
`Range: bytes=0-` 做分段/断点，遇到不支持的服务器会退化成整包重下，
大文件下体验很差，个别 ROM 还会因为拿不到 Content-Length 而失败。

用法（在工程根目录执行）：

    python tools/server/serve.py --port 8080

参数：
    --root    要发布的目录，默认 publish/
    --port    端口，默认 8080（家宽 80/443 通常被运营商封锁，别用）
    --host    监听地址，默认 0.0.0.0（必须，否则手机连不上）

只读、只接受 GET/HEAD，不提供上传，不执行任何脚本。
"""

from __future__ import annotations

import argparse
import datetime
import mimetypes
import os
import socket
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse

CHUNK = 64 * 1024


class PublishHandler(BaseHTTPRequestHandler):
    server_version = "dybackup-publish/1.0"
    root: Path = Path("publish")

    # -------------------------------------------------- 日志

    def log_message(self, fmt: str, *args) -> None:
        stamp = datetime.datetime.now().strftime("%H:%M:%S")
        sys.stdout.write(f"[{stamp}] {self.client_address[0]:<15} {fmt % args}\n")
        sys.stdout.flush()

    # -------------------------------------------------- 路由

    def do_GET(self) -> None:  # noqa: N802
        self._serve(with_body=True)

    def do_HEAD(self) -> None:  # noqa: N802
        self._serve(with_body=False)

    def _serve(self, *, with_body: bool) -> None:
        path = urlparse(self.path).path
        rel = unquote(path).lstrip("/")

        if rel in ("", "/"):
            self._send_index()
            return

        target = (self.root / rel).resolve()
        root = self.root.resolve()
        # 防目录穿越：解析后必须仍在发布目录内
        if not str(target).startswith(str(root) + os.sep) or not target.is_file():
            self._send_error(404, "not found")
            return

        size = target.stat().st_size
        content_type = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
        start, end = 0, size - 1
        status = 200

        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            spec = rng[len("bytes="):].split(",")[0].strip()
            first, _, last = spec.partition("-")
            try:
                if first:
                    start = int(first)
                    end = int(last) if last else size - 1
                elif last:
                    # bytes=-500 表示「最后 500 字节」
                    start = max(0, size - int(last))
                    end = size - 1
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
                status = 206
            except ValueError:
                start, end, status = 0, size - 1, 200

        length = end - start + 1
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        # 清单必须每次拿最新的，安装包可以缓存一点（但改名发布更保险）
        if target.suffix == ".json":
            self.send_header("Cache-Control", "no-store, must-revalidate")
        else:
            self.send_header("Cache-Control", "public, max-age=600")
        self.end_headers()

        if not with_body:
            return

        remaining = length
        with target.open("rb") as fh:
            fh.seek(start)
            while remaining > 0:
                chunk = fh.read(min(CHUNK, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    # 手机端中断下载，正常现象，不必刷错误日志
                    return
                remaining -= len(chunk)

    def _send_index(self) -> None:
        try:
            items = sorted(p.name for p in self.root.iterdir() if p.is_file())
        except OSError:
            self._send_error(500, "publish dir missing")
            return

        rows = "".join(
            f'<li><a href="/{name}">{name}</a> '
            f'<span>{(self.root / name).stat().st_size / 1024:.0f} KB</span></li>'
            for name in items
        )
        html = (
            "<!doctype html><meta charset='utf-8'>"
            "<title>dybackup publish</title>"
            "<style>body{font:14px/1.7 system-ui;margin:40px;color:#161823}"
            "li{margin:6px 0}span{color:#858b99;margin-left:8px}"
            "a{color:#fe2c55;text-decoration:none}</style>"
            "<h3>升级发布目录</h3><ul>" + rows + "</ul>"
            "<p>手机能打开这一页，说明端口和防火墙已经通了。</p>"
        )
        body = html.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_error(self, code: int, message: str) -> None:
        body = f"{code} {message}".encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def local_ip() -> str:
    """取本机在局域网中的地址（不会真的发包）。"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("223.5.5.5", 80))
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def public_ip() -> str:
    """尽力取公网 IP，失败不影响启动。"""
    import urllib.request

    for url in ("https://api.ipify.org", "https://ifconfig.me/ip"):
        try:
            with urllib.request.urlopen(url, timeout=4) as resp:
                return resp.read().decode().strip()
        except Exception:
            continue
    return ""


def main() -> int:
    parser = argparse.ArgumentParser(description="App 升级包发布服务器")
    parser.add_argument("--root", default="publish", help="发布目录")
    parser.add_argument("--port", type=int, default=8080, help="监听端口")
    parser.add_argument("--host", default="0.0.0.0", help="监听地址")
    args = parser.parse_args()

    root = Path(args.root)
    if not root.is_dir():
        raise SystemExit(
            f"发布目录不存在：{root}\n先跑一次 make_manifest.py 生成 latest.json 和 APK。"
        )

    PublishHandler.root = root
    mimetypes.add_type("application/vnd.android.package-archive", ".apk")

    lan = local_ip()
    wan = public_ip()

    print("=" * 62)
    print("升级服务已启动（只读，仅 GET/HEAD）")
    print(f"发布目录   {root.resolve()}")
    print(f"本机访问   http://127.0.0.1:{args.port}/latest.json")
    print(f"局域网     http://{lan}:{args.port}/latest.json")
    if wan:
        print(f"公网       http://{wan}:{args.port}/latest.json")
    else:
        print("公网       未取到（不影响局域网测试）")
    print("-" * 62)
    print("手机验证顺序：")
    print(f"  1. 先连同一个 WiFi，浏览器打开 http://{lan}:{args.port}/")
    print("  2. 能打开列表页 = 服务与防火墙通了")
    print("  3. 再换 4G/5G 打开公网地址 = 路由器端口映射通了")
    print("按 Ctrl+C 停止")
    print("=" * 62)

    httpd = ThreadingHTTPServer((args.host, args.port), PublishHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")
    finally:
        httpd.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
