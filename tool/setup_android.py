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
SCAFFOLD = ROOT / "ci_scaffold"
ANDROID = ROOT / "android"
PROJECT_NAME = "deepsleep"
ORG = "com.deepsleep"
APP_LABEL = "DeepSleep"
# flutter_tts 4.x 的 Android 实现要求 minSdk >= 24。
MIN_SDK = 24


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


def _insert_before_application(text: str, snippet: str) -> str:
    """把一段 XML 插到 <application> 之前（保持在 <manifest> 内部）。"""
    match = re.search(r"^([ \t]*)<application\b", text, re.MULTILINE)
    if not match:
        sys.exit("AndroidManifest.xml 缺少 <application> 标签")
    insert_at = match.start()
    return text[:insert_at] + snippet + text[insert_at:]


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

    # 语音输入：speech_to_text 需要麦克风权限（放在 <application> 之前）。
    if "android.permission.RECORD_AUDIO" not in text:
        text = _insert_before_application(
            text,
            "\n    <!-- 语音输入（speech_to_text 录音识别） -->\n"
            '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n',
        )

    # Android 11+ 包可见性：不声明 queries 时语音识别与 TTS 引擎可能不可见。
    # - RecognitionService 供 speech_to_text 查找系统识别服务；
    # - TTS_SERVICE 供 flutter_tts 查找系统语音合成引擎。
    voice_intents = ""
    if "android.speech.RecognitionService" not in text:
        voice_intents += (
            "        <intent>\n"
            '            <action android:name="android.speech.RecognitionService"/>\n'
            "        </intent>\n"
        )
    if "android.intent.action.TTS_SERVICE" not in text:
        voice_intents += (
            "        <intent>\n"
            '            <action android:name="android.intent.action.TTS_SERVICE"/>\n'
            "        </intent>\n"
        )
    if voice_intents:
        if "<queries" in text:
            # Flutter 模板自带的 <queries>（PROCESS_TEXT）里合并 intent，不重复加块。
            match = re.search(r"[ \t]*</queries>", text)
            if not match:
                sys.exit("AndroidManifest.xml 中的 <queries> 未闭合")
            text = text[: match.start()] + voice_intents + text[match.start() :]
        else:
            text = _insert_before_application(
                text,
                "\n    <!-- Android 11+ 包可见性：语音识别服务与 TTS 引擎 -->\n"
                "    <queries>\n"
                f"{voice_intents}"
                "    </queries>\n",
            )

    text = re.sub(r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', text)
    manifest.write_text(text, encoding="utf-8")
    print(
        "patched AndroidManifest.xml "
        "(INTERNET + RECORD_AUDIO permissions, queries, label)"
    )


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
        # 有些模板直接写数字：统一成 MIN_SDK
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
