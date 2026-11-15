# 交付验证说明

本仓库按「源码进仓库、云端构建」模式开发。开发环境里**没有 Flutter/Dart SDK**，
因此没有在本地执行过 `flutter analyze` / `flutter test` / `flutter build`。
为了尽量降低首次云端构建的失败概率，做了以下检查：

## 已完成的静态检查

| 检查 | 方法 | 结果 |
| --- | --- | --- |
| 全部 Dart 文件的括号 / 字符串 / 注释配对 | 自写词法检查器逐字符扫描（含 `${...}` 插值） | 61 个文件通过 |
| 相对 import 与 `package:deepsleep/...` 是否存在 | 解析 import 路径并检查文件 | 通过 |
| 三方包 import 是否都在 pubspec 声明 | 交叉比对 pubspec 与 import | 通过 |
| `Icons.*` 图标名是否存在于 Flutter 3.35.7 | 对照 Flutter 源码 `icons.dart`（8825 个图标） | 61 个使用全部有效 |
| 枚举成员引用是否有效 | 提取 enum 定义后交叉检查 | 通过 |
| 跨模块 API 调用（controller/service/model） | 逐项对照定义 | 通过 |
| 入口组件签名与 `app.dart` 调用 | 人工比对 | 一致 |

## 未验证（需要 CI 或真机确认）

- 类型级编译：泛型推断、可空性、集合字面量类型等；
- `flutter analyze` 可能报的 error（CI 已配置只拦截 error，不拦截 info/warning）；
- `flutter test` 是否全部通过（纯 Dart 逻辑单测，失败会给出具体断言）；
- Android 构建链（Gradle/AGP/Kotlin 版本、插件编译）；
- 真机 UI 行为（滚动时序、输入法、深色模式、横屏）。

## CI 首次构建建议关注顺序

1. `flutter pub get` —— 依赖解析；
2. `flutter analyze` 报错文件与行号（重点：`chat_view.dart`、`composer.dart`、
   `markdown_view.dart`、`settings_page.dart`、`deepseek_client.dart`）；
3. `flutter test` 断言失败（重点：记忆引擎的预算裁剪 / 压缩边界）；
4. `flutter build apk` 的 Gradle 日志（插件 / minSdk / 命名空间）。

修复时优先改报错点，不要整体重构；单测失败时先确认断言是否与实现语义一致。

## 已知取舍

- 没有引入向量数据库：记忆召回用关键词 + 图扩展 + 时间衰减，手机端数据量下
  足够快且零部署，但语义召回能力弱于 embedding；
- mem0 云端后端为实验特性：只保存配置、按 REST 协议调用，未做过线上联调；
- 字号设置仅保存（根组件未应用 textScaler），留待后续版本；
- 备份导入默认「合并」，不提供覆盖选项（UI 未暴露 replace）。
