#!/usr/bin/env python3
"""给生成的 android/ 工程注入固定签名配置。

仓库本身不提交 keystore；CI 从 GitHub Secrets 解出 keystore 后，把路径与
密码通过环境变量传给本脚本：

    KEYSTORE_FILE       keystore 文件路径（相对 android/app）
    KEYSTORE_PASSWORD   store 密码
    KEY_ALIAS           别名
    KEY_PASSWORD        key 密码

本地打包时也可以先 export 这几个变量再运行。
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "android"

KOTLIN_SIGNING = """    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("KEYSTORE_FILE") ?: "deepsleep-release.p12")
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            keyAlias = System.getenv("KEY_ALIAS") ?: "deepsleep"
            keyPassword = System.getenv("KEY_PASSWORD") ?: ""
            storeType = "PKCS12"
        }
    }

"""

GROOVY_SIGNING = """    signingConfigs {
        release {
            storeFile file(System.getenv("KEYSTORE_FILE") ?: "deepsleep-release.p12")
            storePassword System.getenv("KEYSTORE_PASSWORD")
            keyAlias System.getenv("KEY_ALIAS")
            keyPassword System.getenv("KEY_PASSWORD")
            storeType "PKCS12"
        }
    }

"""


def main() -> int:
    if not (ANDROID / "app").exists():
        sys.exit("找不到 android/app，请先运行 tool/setup_android.py")
    if not os.environ.get("KEYSTORE_PASSWORD"):
        print("未提供签名密码，沿用 debug 签名（仅用于本地调试）")
        return 0

    for path in [ANDROID / "app/build.gradle.kts", ANDROID / "app/build.gradle"]:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        is_kotlin = path.suffix == ".kts"
        signing = KOTLIN_SIGNING if is_kotlin else GROOVY_SIGNING

        if 'create("release")' not in text and "signingConfigs {" not in text:
            # 插到 buildTypes 之前（android { ... } 内部）。
            match = re.search(r"^    buildTypes\s*\{", text, re.M)
            if not match:
                sys.exit(f"{path} 里找不到 buildTypes，无法注入签名配置")
            text = text[: match.start()] + signing + text[match.start():]

        if is_kotlin:
            text = text.replace(
                'signingConfig = signingConfigs.getByName("debug")',
                'signingConfig = signingConfigs.getByName("release")',
            )
        else:
            text = text.replace(
                "signingConfig signingConfigs.debug",
                "signingConfig signingConfigs.release",
            )
        path.write_text(text, encoding="utf-8")
        print(f"已注入固定签名配置: {path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
