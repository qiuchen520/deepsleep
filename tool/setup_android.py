#!/usr/bin/env python3
"""在没有 Flutter 环境的仓库里生成 android/ 平台脚手架。

用途：仓库只提交 Dart 源码，不提交 android/（避免 Gradle 二进制文件与
版本漂移）。GitHub Actions 里先运行本脚本生成平台工程，再执行
`flutter build apk`。

本地也可以用它：只要装了 Flutter SDK，执行
    python3 tool/setup_android.py
即可得到可构建的 android/ 目录。
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAFFOLD = ROOT / ".scaffold"
ANDROID = ROOT / "android"
PROJECT_NAME = "deepsleep"
ORG = "com.deepsleep"
APP_LABEL = "DeepSleep"
MIN_SDK = 23


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd))
    subprocess.check_call(cmd, cwd=ROOT)


def generate_scaffold() -> None:
    if SCAFFOLD.exists():
        shutil.rmtree(SCAFFOLD)
    run(
        [
            "flutter",
            "create",
            "--platforms=android",
            f"--project-name={PROJECT_NAME}",
            f"--org={ORG}",
            "--overwrite",
            str(SCAFFOLD),
        ]
    )


def copy_android() -> None:
    src = SCAFFOLD / "android"
    if not src.exists():
        sys.exit("flutter create 没有生成 android/ 目录，请检查 Flutter 版本")
    if ANDROID.exists():
        shutil.rmtree(ANDROID)
    shutil.copytree(src, ANDROID)
    print(f"copied {src} -> {ANDROID}")


def patch_manifest() -> None:
    manifest = ANDROID / "app/src/main/AndroidManifest.xml"
    if not manifest.exists():
        sys.exit(f"找不到 {manifest}")
    text = manifest.read_text(encoding="utf-8")

    if "android.permission.INTERNET" not in text:
        # 权限必须写在 <manifest> 标签内部
        match = re.search(r"<manifest[^>]*>", text)
        if not match:
            sys.exit("AndroidManifest.xml 缺少 <manifest> 根标签")
        insert_at = match.end()
        permission = (
            "\n    <!-- 联网访问 DeepSeek API 与搜索服务 -->\n"
            '    <uses-permission android:name="android.permission.INTERNET"/>'
        )
        text = text[:insert_at] + permission + text[insert_at:]
    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', text)
    manifest.write_text(text, encoding="utf-8")
    print("patched AndroidManifest.xml (INTERNET permission + label)")


def patch_gradle() -> None:
    candidates = [
        ANDROID / "app/build.gradle.kts",
        ANDROID / "app/build.gradle",
    ]
    for path in candidates:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        # 显式抬高 minSdk：flutter_secure_storage / file_picker / share_plus 需要。
        text = re.sub(
            r"minSdk\s*=\s*flutter\.minSdkVersion",
            f"minSdk = {MIN_SDK}",
            text,
        )
        text = re.sub(
            r"minSdkVersion\s+flutter\.minSdkVersion",
            f"minSdkVersion {MIN_SDK}",
            text,
        )
        # 有些模板直接写数字：统一成 23
        text = re.sub(
            r"minSdk\s*=\s*\d+",
            f"minSdk = {MIN_SDK}",
            text,
        )
        text = re.sub(
            r"minSdkVersion\s+\d+",
            f"minSdkVersion {MIN_SDK}",
            text,
        )
        path.write_text(text, encoding="utf-8")
        print(f"patched {path.name} (minSdk = {MIN_SDK})")

    properties = ANDROID / "gradle.properties"
    if properties.exists():
        text = properties.read_text(encoding="utf-8")
        if "android.useAndroidX" not in text:
            text += "\nandroid.useAndroidX=true\n"
        properties.write_text(text, encoding="utf-8")


def patch_signing() -> None:
    """Flutter 模板 release 默认用 debug 签名，云端产物可直接安装。"""
    for path in [ANDROID / "app/build.gradle.kts", ANDROID / "app/build.gradle"]:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        if "signingConfig = signingConfigs.getByName(\"debug\")" in text:
            print("release signing already uses debug keystore")
        path.write_text(text, encoding="utf-8")


def main() -> None:
    generate_scaffold()
    copy_android()
    patch_manifest()
    patch_gradle()
    patch_signing()
    print("android/ 脚手架就绪")


if __name__ == "__main__":
    main()
