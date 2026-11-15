# 架构说明

## 分层

```
┌─────────────────────────────────────────────┐
│ features/  UI（聊天、侧栏、设置、记忆中心）    │
│   只依赖 state/ 的控制器与 models             │
├─────────────────────────────────────────────┤
│ state/  控制器（ChangeNotifier）              │
│   SettingsController / ConversationController │
│   MemoryController                            │
├─────────────────────────────────────────────┤
│ services/  网络与文件                          │
│   ChatPipeline / DeepSeekClient / 搜索 / 附件  │
├─────────────────────────────────────────────┤
│ core/memory/  记忆引擎（纯 Dart，可单测）      │
├─────────────────────────────────────────────┤
│ data/  models + SQLite                        │
└─────────────────────────────────────────────┘
```

依赖方向单向向下，UI 不直接触碰数据库与 HTTP。

## 组合根

`lib/state/app_services.dart` 的 `AppServices.init()` 负责：

1. 打开 SQLite（`AppDatabase`）；
2. 读取 SharedPreferences + SecureStorage（`SettingsController`）；
3. 创建 `DeepSeekClient`（同时实现 `ChatApi` 与 `LlmClient`）；
4. 创建 `SqliteMemoryStore` + `LocalMemoryEngine`；
5. 创建搜索路由、附件、导出、备份服务；
6. 创建并加载 `ConversationController`、`MemoryController`。

通过 `AppScope`（InheritedWidget）注入整棵树。

## 一次发送的调用链

```
ChatView（输入框）
  └─ ConversationController.sendMessage()
       ├─ 落库 user 消息 + assistant 占位（streaming）
       ├─ ChatPipeline.prepare()
       │    ├─ WebSearchService.search()
       │    ├─ MemoryEngine.retrieve()
       │    └─ buildSystemPrompt()
       ├─ ChatPipeline.stream() → SSEClient 增量事件
       │    └─ 节流 notifyListeners()（120ms）刷新 UI
       ├─ _finishTurn()
       │    ├─ 智能标题
       │    ├─ 上下文压缩（若超阈值）
       │    └─ 记忆回写（异步）
       └─ 刷新记忆中心徽标
```

## 持久化 schema

见 `lib/data/db/app_database.dart`。所有表都采用「索引列 + JSON payload」：

- 便于模型演进（新增字段不需要 migration）；
- 索引列保证列表/搜索性能；
- 备份时 payload 展开为 JSON 对象，可读性更好。

## 并发与生命周期

- 流式请求由 `StreamSubscription` 管理，`stop()` 主动 cancel；
- 流式期间每 120ms 节流刷新 UI，避免高频 setState；
- `dispose()` 取消定时器与订阅，防止内存泄漏；
- App 退出时 `AppServices.dispose()` 关闭数据库。

## 错误处理

- 网络层统一抛 `ApiException`，带 `ApiErrorKind`；
- UI 只展示 `friendlyMessage`（网络异常 / Key 无效 / 余额不足 / 限流 / 服务器繁忙）；
- 记忆与压缩失败降级，不阻塞主流程。

## 扩展点

| 想改什么 | 改哪里 |
| --- | --- |
| 换模型 / 协议 | `services/deepseek_client.dart`（实现 `ChatApi`） |
| 换记忆后端 | 实现 `MemoryEngine`，在 `AppServices.init()` 里替换 |
| 加搜索服务商 | 实现 `WebSearchService`，在 `SearchRouter` 注册 |
| 换向量检索 | 在 `MemoryStore` 与 `memory_scoring.dart` 增加 embedding 分数 |
| 改 UI 主题 | `core/theme/app_theme.dart` |
