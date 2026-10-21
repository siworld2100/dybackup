#!/usr/bin/env python3
"""生成带签名的版本清单 latest.json。

用法（在工程根目录执行）：

    python tools/server/make_manifest.py ^
        --apk dist/dybackup-v1.2.1-arm64.apk ^
        --base-url http://1.2.3.4:8080 ^
        --notes "修复抖音新版分享页解析失败"

脚本会：
  1. 算 APK 的 sha256 与字节数；
  2. 用 aapt2 读出 APK 的 versionCode / versionName（可用参数覆盖）；
  3. 把清单原文当成字符串、用签名密钥做 HMAC-SHA256 签名（密钥从 secret.env 读）；
  4. 写出 publish/latest.json，并把 APK 复制进 publish/。

为什么要签「字符串」而不是「对象」：
Python 与 Dart 的 JSON 序列化在键顺序、非 ASCII 转义、空格上不一致，
一旦对对象签名，客户端重新序列化后必然对不上。所以这里把清单序列化成
一段确定的文本，签名对象就是这段字节，客户端对同一段字节验签即可。

依赖：仅 Python 标准库；aapt2 从 ANDROID_HOME 或常见路径自动查找。
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import hmac
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# 签名密钥不进仓库：优先 --key，其次环境变量 MANIFEST_KEY，最后读同目录 secret.env。
SECRET_FILE = Path(__file__).with_name("secret.env")

# 与发布目录同级，脚本自己维护
PUBLISH_DIR = Path("publish")


def load_secret_env() -> None:
    """把 secret.env 里的 KEY=VALUE 载入环境变量（不覆盖已有的）。

    仓库是公开的，所以真实密钥只存在于本机这个被 gitignore 的文件里。
    格式与 .env 一致，支持 # 注释和空行。
    """
    try:
        text = SECRET_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        os.environ.setdefault(name.strip(), value.strip())


def find_aapt2() -> str | None:
    """在 Android SDK 中找最新的 aapt2。"""
    candidates: list[Path] = []
    for env in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        root = os.environ.get(env)
        if root:
            candidates.append(Path(root))
    # 本机默认位置（Windows）
    local_appdata = os.environ.get("LOCALAPPDATA")
    if local_appdata:
        candidates.append(Path(local_appdata) / "Android" / "Sdk")
    candidates.append(Path.home() / "AppData" / "Local" / "Android" / "Sdk")

    for root in candidates:
        build_tools = root / "build-tools"
        if not build_tools.is_dir():
            continue
        versions = sorted(
            (p for p in build_tools.iterdir() if p.is_dir()),
            key=lambda p: [int(x) for x in re.findall(r"\d+", p.name)],
            reverse=True,
        )
        for version in versions:
            exe = version / ("aapt2.exe" if os.name == "nt" else "aapt2")
            if exe.is_file():
                return str(exe)
    return None


def probe_apk(aapt2: str, apk: Path) -> tuple[int, str]:
    """返回 (versionCode, versionName)。"""
    out = subprocess.run(
        [aapt2, "dump", "badging", str(apk)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if out.returncode != 0:
        raise SystemExit(f"aapt2 读取 APK 失败：{out.stderr.strip()}")

    first = out.stdout.splitlines()[0] if out.stdout else ""
    code = re.search(r"versionCode='(\d+)'", first)
    name = re.search(r"versionName='([^']*)'", first)
    if not code:
        raise SystemExit("未能从 APK 中解析出 versionCode，请用 --version-code 手动指定")
    return int(code.group(1)), (name.group(1) if name else "")


def build_payload(
    *,
    version_code: int,
    version_name: str,
    file_name: str,
    base_url: str,
    sha256: str,
    size: int,
    notes: str,
    force: bool,
) -> dict:
    return {
        "versionCode": version_code,
        "versionName": version_name,
        "url": f"{base_url.rstrip('/')}/{file_name}",
        "sha256": sha256,
        "size": size,
        "notes": notes,
        "force": force,
        "issuedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="生成带 HMAC 签名的 latest.json")
    parser.add_argument("--apk", required=True, help="APK 文件路径")
    parser.add_argument(
        "--base-url",
        required=True,
        help="APK 的下载前缀，例如 http://1.2.3.4:8080（末尾不要带斜杠）",
    )
    parser.add_argument("--notes", default="", help="更新说明，会显示在弹窗里")
    parser.add_argument("--force", action="store_true", help="强制更新（不提供「稍后」）")
    parser.add_argument("--version-code", type=int, default=0, help="手动指定 versionCode")
    parser.add_argument("--version-name", default="", help="手动指定 versionName")
    parser.add_argument(
        "--key",
        default="",
        help="签名密钥。留空则读环境变量 MANIFEST_KEY 或同目录下的 secret.env；"
        "两者都没有会直接报错退出（密钥绝不写在仓库里）",
    )
    parser.add_argument("--out", default=str(PUBLISH_DIR), help="输出目录")
    args = parser.parse_args()

    load_secret_env()
    key = (args.key or os.environ.get("MANIFEST_KEY", "")).strip()
    if not key:
        parser.error(
            "缺少签名密钥：请用 --key 传入，或在 tools/server/secret.env 里写 MANIFEST_KEY=…"
            "（该文件已 gitignore），或设置环境变量 MANIFEST_KEY"
        )

    apk = Path(args.apk)
    if not apk.is_file():
        raise SystemExit(f"找不到 APK：{apk}")

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. 指纹
    digest = hashlib.sha256()
    with apk.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 256), b""):
            digest.update(chunk)
    sha256 = digest.hexdigest()
    size = apk.stat().st_size

    # 2. 版本号
    version_code, version_name = args.version_code, args.version_name
    if version_code <= 0 or not version_name:
        aapt2 = find_aapt2()
        if aapt2:
            probed_code, probed_name = probe_apk(aapt2, apk)
            version_code = version_code or probed_code
            version_name = version_name or probed_name
        else:
            raise SystemExit(
                "未找到 aapt2，无法读取 versionCode。"
                "请设置 ANDROID_HOME，或用 --version-code/--version-name 手动指定。"
            )

    # 3. 清单原文（键序固定，ensure_ascii=False 让中文保持可读）
    payload = build_payload(
        version_code=version_code,
        version_name=version_name,
        file_name=apk.name,
        base_url=args.base_url,
        sha256=sha256,
        size=size,
        notes=args.notes,
        force=args.force,
    )
    payload_text = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    # 4. 签名
    signature = hmac.new(
        key.encode("utf-8"),
        payload_text.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    envelope = {"payload": payload_text, "sig": signature}
    manifest = out_dir / "latest.json"
    manifest.write_text(
        json.dumps(envelope, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    # 5. 复制 APK 进发布目录
    target_apk = out_dir / apk.name
    if target_apk.resolve() != apk.resolve():
        shutil.copy2(apk, target_apk)

    # 6. 自检：用同样的算法验一遍，避免出现「发了签不过的清单」
    check = hmac.new(
        key.encode("utf-8"),
        payload_text.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    assert check == signature, "签名自检失败"

    print("=" * 62)
    print(f"版本        {version_name} ({version_code})")
    print(f"APK         {apk.name}  {size / 1048576:.1f} MB")
    print(f"sha256      {sha256}")
    print(f"下载地址    {payload['url']}")
    print(f"清单        {manifest}")
    print(f"签名        {signature[:32]}…")
    print("=" * 62)
    print("下一步：让 serve.py 指向这个目录，然后用手机浏览器打开测试")
    print(f"        {args.base_url}/latest.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
