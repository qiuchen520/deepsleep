# DeepSleep 模块契约（开发用）

> 本仓库是「先写源码、云端构建」的模式：本地不需要 Flutter SDK。
> 所有代码必须按本文件约定的接口实现，避免跨模块不一致。

## 目录与职责

```
lib/
├── main.dart                    入口
├── app.dart                     根组件 / 导航 / 主题
├── core/
│   ├── constants.dart           常量、默认值
│   ├── theme/app_theme.dart     设计令牌（DeepSeek 风格配色）
│   ├── utils/                   token 估算、时间、ID
│   └── memory/
│       ├── contracts.dart       记忆引擎接口（MemoryEngine / MemoryStore / LlmClient）
│       ├── local_memory_engine.dart
│       ├── memory_prompts.dart  抽取 / 压缩 / 标题的提示词
│       ├── memory_scoring.dart  检索打分（关键词 + 图扩展 + 时间衰减）
│       ├── memory_graph.dart    实体/关系抽取与图构建
│       └── extraction.dart      抽取结果 JSON 解析与合并决策
├── data/
│   ├── models/                  domain models（纯 Dart）
│   └── db/
│       ├── app_database.dart    sqflite 封装 + 会话/消息/档案 CRUD
│       └── sqlite_memory_store.dart
├── services/
│   ├── contracts.dart           API / 搜索 / 附件 / 导出接口
│   ├── deepseek_client.dart     OpenAI 兼容流式客户端
│   ├── sse_parser.dart          SSE 解析
│   ├── search_service_impl.dart Tavily / Serper
│   ├── attachment_service_impl.dart 文件选择 + 文本/docx 抽取
│   ├── export_service_impl.dart Markdown / JSON 导出
│   └── backup_service_impl.dart 全量备份恢复
├── state/
│   ├── settings_controller.dart
│   ├── conversation_controller.dart  聊天主流程（检索→拼 Prompt→流式→落库→记忆→压缩）
│   └── memory_controller.dart
├── features/
│   ├── chat/                    聊天页与输入区
│   ├── sidebar/                 侧栏 / 会话列表
│   ├── settings/                设置页
│   └── memory/                  记忆中心 / 知识图谱
└── widgets/                     通用组件（Markdown、代码块、图表、思考块…）
test/                            纯 Dart 单测（flutter test 即可运行）
```

## 关键约定

- 包名：`deepsleep`，导入写法 `package:deepsleep/...`。
- 所有 `data/models/*`、`core/memory/*` 必须保持 **纯 Dart**（不 import Flutter），
  以便用 `flutter test` 在无设备环境跑算法单测。
- 只用 `pubspec.yaml` 里声明的依赖，不新增包（特殊情况需先说明）。
- 错误统一用 `ApiException`；UI 只展示 `friendlyMessage`。
- 颜色只能用 `context.colors.xxx` / `AppColors`，不要硬编码主题色（黑白透明除外）。
- 用户可见文案中文为主；代码注释中文。
- 每个文件顶部写一段 `///` 说明该文件职责。
- 不要执行 `flutter pub get` / `flutter analyze`：本机没有 Flutter SDK，构建在 GitHub Actions 完成。

## 记忆流水线（核心）

```
用户发送
  └─ ChatPipeline.send()
       ├─ 1. 若开启联网搜索 → WebSearchService.search() → SearchHit[]
       ├─ 2. MemoryEngine.retrieve(userId, query) → MemoryContext
       ├─ 3. buildSystemPrompt()（基础人设 + 用户档案 + 记忆块 + 会话摘要 + 搜索资料）
       ├─ 4. ChatApi.streamChat() → SSE 增量（reasoning/content/usage）
       ├─ 5. 落库消息；AI 标题
       ├─ 6. MemoryEngine.ingest() → 抽取/合并记忆（异步后台）
       └─ 7. MemoryEngine.compress() → token > 阈值时压缩前半段
```

## 状态层对外 API（UI 依赖）

见 `lib/state/*.dart` 的实际实现；UI 只通过 controller 读写，不直接碰数据库/API。
