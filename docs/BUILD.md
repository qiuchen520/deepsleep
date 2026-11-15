# 构建指南

本项目采用「**源码进仓库，平台工程云端生成**」的方式：

- 不提交 `android/`、`ios/`（避免 Gradle Wrapper 二进制、SDK 版本漂移）；
- CI 里用 `tool/setup_android.py` 调 `flutter create` 生成平台脚手架，
  再注入 INTERNET 权限、应用名、minSdk；
- 因此**本地没有 Flutter 也能提交代码**，构建交给 GitHub Actions。

## 一、GitHub Actions 构建（推荐）

### 手动触发

1. Fork / 上传仓库到 GitHub；
2. 打开 `Actions` → `build` → `Run workflow`；
3. 约 5~10 分钟后，本次运行页面底部 `Artifacts` 下载 `deepsleep-apk`；
4. 解压得到：
   - `app-arm64-v8a-release.apk` —— 近几年的手机（推荐）
   - `app-armeabi-v7a-release.apk` —— 老设备
   - `app-x86_64-release.apk` —— 模拟器

### 打 tag 自动发布

```bash
git tag v1.0.0
git push origin v1.0.0
```

`release` job 会把 APK 附到 GitHub Release 上。

### 工作流做了什么

```yaml
flutter-version: "3.35.7"      # 固定版本，避免上游更新导致构建漂移
python3 tool/setup_android.py  # 生成 android/ 并打补丁
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test                   # 纯 Dart 单测
flutter build apk --release --split-per-abi
```

## 二、本地构建

要求：Flutter 3.35+、JDK 17、Android SDK（含 build-tools）。

```bash
git clone https://github.com/<you>/deepsleep.git
cd deepsleep
python3 tool/setup_android.py
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

产物在 `build/app/outputs/flutter-apk/`。

### 只调 UI 时

```bash
flutter run            # 需要连接手机或模拟器
```

## 三、正式签名（可选）

默认 release 使用 debug 签名，能安装但不适合上架。
要正式签名：生成 keystore 后，在 CI 中通过 Secrets 注入
`KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`，
并在 `android/app/build.gradle.kts` 里配置 `signingConfigs.release`。

## 四、常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| `flutter create` 报项目名非法 | 确认 `--project-name=deepsleep`，不要含短横线 |
| Gradle 下载超时 | 重跑一次；或在 CI 里配置国内 Gradle 镜像 |
| `minSdkVersion` 冲突 | 脚本已统一设为 23；如插件要求更高，改 `tool/setup_android.py` 的 `MIN_SDK` |
| 缺少 INTERNET 权限 | 脚本会自动注入；若手动生成 android/，请检查 manifest |
| `flutter analyze` 报 info/warning 导致失败 | CI 已用 `--no-fatal-infos --no-fatal-warnings`，只拦截 error |
| 想升级 Flutter | 修改 `.github/workflows/build.yml` 里的 `flutter-version`，重新跑 CI |

## 五、版本与发布

- 版本号在 `pubspec.yaml` 的 `version: 1.0.0+1`（`+1` 是 build number）；
- 发版前更新 `CHANGELOG.md`，打 tag（如 `v1.1.0`）触发 Release。
