<div align="center">

# DeepSleep · 记忆对话

**一个拥有长期记忆知识网的原生 AI 聊天客户端**

参考 DeepSeek 官方 Web Demo 的交互与视觉（极简白底 + 品牌蓝），用 Flutter 重写为原生 App，
并补上它缺少的那一块：**跨会话、跨设备的长期记忆**。

[![build](https://github.com/deepsleep-app/deepsleep/actions/workflows/build.yml/badge.svg)](https://github.com/deepsleep-app/deepsleep/actions/workflows/build.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-lightgrey.svg)]()
[![flutter](https://img.shields.io/badge/Flutter-3.35%2B-02569B.svg)](https://flutter.dev)

</div>

---

## 这是什么

原版 Demo 是纯前端：刷新页面就失忆，换个会话也不认识你。

DeepSleep 在保留原有交互（流式输出、深度思考、联网搜索、文件对话、多会话管理、
消息版本、Markdown/代码块）的基础上，做了一套 **本地优先的记忆知识网**：

- 每次发消息前，按当前用户 ID 召回相关长期记忆，自动拼进 System Prompt；
- 每次回答结束后，把这一轮对话交给记忆引擎抽取事实 / 偏好 / 实体 / 关系，合并进知识网；
- 上下文超过 **4000 tokens** 时，自动把前半段总结成摘要，保持长对话不中断；
- 记忆可以在「记忆中心」里查看、搜索、编辑、置顶、删除，并以知识图谱形式可视化；
- 可选接入 **mem0 云平台**（实验特性），把记忆托管到你自己的 mem0 账号。

> 打包不需要本地环境：仓库只放 Dart 源码，GitHub Actions 自动生成 `android/`
> 并产出 APK。fork 之后点一下 Actions 就能拿到安装包。

---

## 功能一览

### 对话（对齐原 Demo）

| 功能 | 说明 |
| --- | --- |
| 流式输出 | SSE 增量渲染，可随时停止 |
| 深度思考 | `deepseek-reasoner` 的 `reasoning_content` 折叠展示，显示思考耗时 |
| 联网搜索 | 默认使用 **DeepSeek 内置搜索**（官方同款 web_search 工具，无需第三方 Key），也可切换 Tavily / Serper |
| 文件对话 | 文本 / Markdown / 代码 / JSON / CSV / DOCX 本地解析注入 |
| 多会话 | 按 今天 / 昨天 / 7 天内 / 30 天内 / 更早 分组，支持搜索、置顶、重命名、删除 |
| 消息版本 | 重新生成保留历史版本，可 `< 1/2 >` 来回切换 |
| 编辑重发 | 改写任意一条用户消息，从该处重新续写 |
| 继续生成 | 输出被截断或主动停止后可继续 |
| Markdown | 表格、引用、列表、链接；代码块带语言标签、复制、轻量高亮 |
| 图表 | ` ```chart ` 代码块用 JSON 描述，原生绘制柱状 / 折线 / 饼图 |
| 多用户档案 | 每个档案独立记忆、独立人设（System Prompt） |
| 主题 | 浅色 / 深色 / 跟随系统 |

### 记忆（本项目核心）

| 功能 | 说明 |
| --- | --- |
| 自动记忆抽取 | 每轮对话后异步抽取结构化记忆（事实 / 偏好 / 档案 / 事件 / 任务 / 关系） |
| 混合召回 | 关键词 × 图扩展 × 重要度 × 时间衰减 打分，按 token 预算装填 |
| 知识图谱 | 实体与关系自动归并、可视化浏览 |
| 冲突取代 | 同一主谓的新旧事实自动 `superseded`，不会互相打架 |
| 上下文压缩 | 超过阈值自动摘要前半段，摘要参与后续每轮请求 |
| 记忆引用 | 每条回答显示「引用 N 条记忆」，点开可看具体注入了什么 |
| 记忆管理 | 搜索、筛选、编辑、置顶、删除、清空，支持切换用户 |
| 可选 mem0 | 在设置里切换到 mem0 云平台（自带 API Key） |

### 数据

- 会话 / 消息 / 记忆全部存本机 SQLite，不上传任何服务器；
- 单会话导出 Markdown / JSON，一键分享；
- 全量备份 / 恢复（JSON），密钥不写入备份。

---

## 记忆是怎么工作的

```
用户发送消息
   │
   ├─[1] 联网搜索（可选）──────────────► 搜索结果
   │
   ├─[2] 记忆召回
   │      query = 本轮消息 + 最近用户消息
   │      candidates = active 记忆 + 实体图邻居
   │      score = 0.42·关键词 + 0.18·图扩展 + 0.18·重要度 + 0.22·新鲜度
   │      按 token 预算贪心装填 → MemoryContext
   │
   ├─[3] System Prompt = 人设 + 用户档案 + 长期记忆 + 会话摘要 + 搜索资料 + 附加要求
   │
   ├─[4] 流式请求 deepseek-chat / deepseek-reasoner
   │
   ├─[5] 落库 + AI 生成标题
   │
   ├─[6] 记忆回写（异步）
   │      LLM 抽取 JSON → 解析 → 去重 → 冲突取代 → 写入记忆/实体/关系/原始片段
   │
   └─[7] 上下文压缩
          估算 token > 阈值(默认 4000) → 保留最近 6 条，前半段总结成摘要
```

详细设计见 [docs/MEMORY.md](docs/MEMORY.md)。

---

## 快速开始

### 方式一：云端构建（推荐，无本地环境）

1. Fork 本仓库到你的 GitHub 账号；
2. 打开 **Actions → build → Run workflow**；
3. 等 5~10 分钟，在本次运行的 **Artifacts** 里下载 `deepsleep-apk`；
4. 手机安装 `app-arm64-v8a-release.apk`（绝大多数手机）或 `app-armeabi-v7a-release.apk`。

打 tag（如 `git tag v1.0.0 && git push --tags`）会自动创建 GitHub Release 并附上 APK。

### 方式二：本地构建

需要 Flutter 3.35+ / JDK 17 / Android SDK：

```bash
python3 tool/setup_android.py   # 生成 android/ 平台工程（仓库不提交）
flutter pub get
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

### 首次启动

1. 进「设置 → API」填入 [DeepSeek API Key](https://platform.deepseek.com/api_keys)（`sk-...`）；
2. 点「验证」确认可用；
3. 回到对话页开始聊天，记忆默认开启。

> App 不内置任何 Key，也不代理请求，所有请求直接从你的手机发往 `api.deepseek.com`。

---

## 配置项

| 配置 | 默认 | 说明 |
| --- | --- | --- |
| Base URL | `https://api.deepseek.com` | 兼容 OpenAI 协议的服务地址 |
| 对话模型 | `deepseek-chat` | 快、稳、便宜 |
| 推理模型 | `deepseek-reasoner` | 深度思考模式使用 |
| 上下文压缩阈值 | `4000` | 超过即压缩前半段 |
| 记忆注入预算 | `600` | 每轮注入 System Prompt 的记忆 token 上限 |
| 联网搜索 | **DeepSeek 内置搜索** | 使用官方 `/anthropic/v1/messages` 的 `deepseek_web_search` 工具；也可切换 Tavily / Serper |
| 记忆后端 | 本地知识网 | 可选 mem0 云平台（实验） |

密钥保存在 Android Keystore（`flutter_secure_storage`），不进入备份文件。

---

## 目录结构

```
lib/
├── core/                 常量 / 主题 / 工具 / Prompt 组装
│   ├── memory/           记忆引擎（纯 Dart，可单测）
│   └── utils/            token 估算、时间、ID
├── data/
│   ├── models/           领域模型
│   └── db/               SQLite 持久层 + 备份
├── services/             DeepSeek SSE / 搜索 / 附件 / 导出
├── state/                控制器（聊天主流程、设置、记忆）
├── features/             聊天 / 侧栏 / 设置 / 记忆中心
└── widgets/              Markdown、代码块、图表
test/                    纯 Dart 单元测试
tool/setup_android.py    CI 用平台脚手架生成脚本
.github/workflows/       APK 构建与 Release
```

更细的模块约定见 [docs/CONTRACTS.md](docs/CONTRACTS.md)、[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 参考项目

本项目的记忆设计参考了三个开源实现（仅借鉴设计，代码为本项目原创）：

- **RecallOS** —— token 预算内的混合召回、时间衰减、`SUPERSEDES` 冲突取代；
- **MemPalace** —— 逐字留存原始片段、实体/主题分层（wings / rooms → 实体 / 关系）；
- **DeepSeek 官方 Web Demo**（`chat-demo-v0.1.1`）—— 交互流程、状态组织与视觉风格；
  它也是「纯前端失忆」问题的来源，因此本项目把记忆放到了本地。

详见 [docs/REFERENCES.md](docs/REFERENCES.md)。

---

## 免责声明

- 本项目是第三方开源客户端，与 DeepSeek 官方无隶属关系，请遵守其 API 服务条款；
- AI 生成内容仅供参考，请自行甄别；
- 记忆由模型自动抽取，可能出错，重要信息请以「记忆中心」里的内容为准并手动修正。

## License

[MIT](LICENSE)
