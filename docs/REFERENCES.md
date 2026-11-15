# 参考项目与设计来源

本项目没有复用任何参考项目的源码，仅在**设计思路上**做了借鉴。
参考物来自用户提供的三个压缩包：

1. `RecallOS.zip` —— RecallOS（local-first memory OS for AI agents）
2. `chat-demo-v0.1.1(重要参考).zip` —— DeepSeek 官方 Web Demo（编译产物，纯前端）
3. `下载完整源码 ZIP` —— MemPalace（local-first verbatim memory）

## 1. RecallOS —— 记忆引擎的骨架

借鉴：

- **token 预算内的上下文构建**：`context_builder` 只注入预算内最高分记忆；
- **时间衰减**：新鲜度随时间指数衰减，避免老记忆长期霸占召回；
- **冲突取代（SUPERSEDES）**：新事实覆盖旧事实但保留历史，可追溯；
- **混合检索**：关键词 + 图的组合，而不是单纯向量相似度；
- **多租户隔离**：所有数据以 user_id 分区。

没有照搬：

- RecallOS 用 FastAPI + SQLite FTS5 + FAISS，本项目是纯客户端，
  改用 SQLite 普通表 + Dart 内存打分（手机端数据量小，够用且零部署）；
- 未实现其 MCP Server / SDK / 3D Dashboard。

## 2. MemPalace —— 逐字留存的思路

借鉴：

- **原文不丢**：抽取事实的同时保留原始对话片段（`episodes` 表），
  召回失败时仍能回溯原话；
- **实体/主题分层**：wings / rooms 对应本项目的 entities / relations；
- **可插拔后端**：`MemoryStore` 接口 + SQLite 实现，未来可替换；
- **检索可限定范围**：按实体/类型筛选，而不是全库乱搜。

没有照搬：

- MemPalace 依赖 ChromaDB 与 Python 服务端；本项目为了「装个 APK 就能用」，
  放弃向量库，改用关键词 + 图 + 衰减的轻量方案。

## 3. DeepSeek 官方 Web Demo —— 交互与视觉基准

从编译产物里反推并复刻的特性：

- 左侧分组会话列表（今天 / 昨天 / 7 天内 / 30 天内）；
- 「今天有什么可以帮到你？」欢迎页与建议问题；
- 流式输出 + 深度思考折叠（`已思考（用时 X 秒）`）；
- 联网搜索卡片（搜索到 N 个网页 / 已阅读 N 个网页）；
- 消息操作：复制、重新生成、继续生成、版本切换（< 1/2 >）、编辑重发；
- 错误文案：网络异常 / Key 无效 / 余额不足 / 请求频繁 / 服务器繁忙；
- 视觉：白底 + 品牌蓝 `#4D6BFE` + 冷灰蓝侧栏 + 圆角输入卡；
- API 形态：`OpenAI 兼容 /chat/completions` 流式协议、`deepseek-reasoner` 的
  `reasoning_content`、文件与搜索能力。

它的短板也正是本项目要解决的：**纯前端、无持久记忆、刷新即失忆**。

## 许可证说明

- RecallOS：MIT
- MemPalace：见其仓库 LICENSE
- DeepSeek Web Demo：MIT（Copyright (c) 2026 DeepSeek）

本项目为独立实现，代码以 MIT 发布，未复制上述项目的源码、字体或图标资源。
应用内使用的图标均来自 Flutter Material Icons。
