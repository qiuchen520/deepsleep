# 记忆系统设计

> 目标：让 AI 在跨会话、跨周、跨设备（同一后端）的尺度上「记得你」，
> 同时把注入成本控制在可预测的 token 预算内。

## 1. 为什么不是简单拼聊天记录

原版 Demo 每次请求都携带完整历史，两个问题：

1. 上下文线性增长，长对话必然爆 token；
2. 换个会话就完全失忆，历史无法复用。

因此这里把「上下文」拆成三层：

| 层 | 内容 | 生命周期 |
| --- | --- | --- |
| 工作记忆 | 最近若干条消息原文 | 当前会话 |
| 会话摘要 | 前半段对话的滚动摘要 | 当前会话 |
| 长期记忆 | 事实 / 偏好 / 档案 / 事件 / 实体关系图 | 跨会话、跨设备 |

## 2. 数据模型

SQLite 表（`lib/data/db/app_database.dart`）：

- `memories`：记忆条目。`kind`（fact/preference/profile/event/task/relation）、
  `content`、`keywords`、`entities`、`importance`、`confidence`、
  `subject/predicate/object`（用于冲突检测）、`status`（active/superseded/archived）、
  `fingerprint`、`access_count`、`last_access_at`、`pinned`。
- `entities`：实体节点。`name`、`type`、`aliases`、`mention_count`、首末出现时间。
- `relations`：知识图边。`source_name`、`relation`、`target_name`、`weight`。
- `episodes`：逐字留存的对话片段（参考 MemPalace 的「原文抽屉」），
  用于召回失败时的关键词兜底与回溯。
- `conversations.summary`：滚动摘要。
- `conversations.compressed_until_message_id`：摘要覆盖边界。

## 3. 写入流程（对话结束后异步入库）

```
(userMessage, assistantMessage)
        │
        ▼
  LLM 抽取（JSON，严格 schema）
        │
        ▼
  parser 容错解析（单条失败不影响整体）
        │
        ▼
  合并决策
   ├─ fingerprint 相同 / 文本相似度 > 0.86 → 视为重复：更新重要度与时间，不新增
   ├─ subject+predicate 相同但 object 不同 → 旧记忆 superseded，写入 supersededBy
   └─ 其余 → 新增，补 keywords / fingerprint / importance / confidence
        │
        ▼
  实体归一化（大小写 / 空白 / 别名）→ upsert entities
  关系去重（source+relation+target）→ upsert relations
  原始对话片段截断到 ~1500 token → episodes
```

抽取提示词要求模型只输出 JSON，字段包含：

```json
{
  "memories": [
    {
      "kind": "preference",
      "content": "用户偏好使用 Dart 写客户端",
      "keywords": ["dart", "客户端"],
      "entities": ["Dart"],
      "importance": 0.7,
      "confidence": 0.9,
      "subject": "用户",
      "predicate": "偏好",
      "object": "Dart",
      "action": "add"
    }
  ],
  "entities": [{ "name": "Dart", "type": "technology" }],
  "relations": [{ "source": "用户", "relation": "偏好", "target": "Dart" }]
}
```

## 4. 召回流程（发送消息前）

候选集 = active 记忆（上限 500 条）+ 命中的实体邻居记忆。

打分：

```
score = 0.42 * keywordOverlap
      + 0.18 * graphBoost        (通过实体/关系命中的加权)
      + 0.18 * importance
      + 0.22 * freshness
```

- `keywordOverlap`：中文二元组 + 英文词（小写/去停用词）的包含与 Jaccard 混合；
- `freshness`：半衰期 21 天的指数衰减，最低保留 0.15，避免老记忆完全消失；
- `pinned` / `importance ≥ 0.8` 的记忆额外加权；
- 命中后 `access_count += 1`、`last_access_at = now`（越用越牢）。

装填：按分数降序贪心加入，直到达到 `memoryTokenBudget`（默认 600）。
输出格式固定，便于模型引用、也便于 UI 做「引用记忆」展示：

```
【长期记忆】
- (偏好) 用户偏好使用 Dart 写客户端（重要）
- (事实) 用户在做 DeepSleep 项目
```

## 5. 上下文压缩

触发：估算当前消息序列 token（含会话摘要）> `compressThreshold`（默认 4000）。

策略：

1. 永远保留最近 `keepRecent`（默认 6）条消息；
2. 更早的消息 + 已有摘要交给模型，生成新的中文滚动摘要（不超过 ~700 token）；
3. 摘要写回 `conversations.summary`，被覆盖的消息标记 `compressed = true`，
   之后的请求只带摘要 + 最近消息；
4. 记录 `compressedUntilMessageId`，UI 展示「已压缩」标记；
5. 压缩失败不影响对话，只记录错误并在下一轮重试。

这样长对话的 prompt 增长是 **对数级** 而不是线性级。

## 6. 多用户隔离

记忆以 `userId`（= 用户档案 ID）为分区键：

- 每个档案独立记忆、独立人设（`persona` 会拼进 System Prompt）；
- 切换档案后，会话列表、会话、记忆、统计全部隔离；
- 删除档案会级联删除其会话与记忆。

## 7. 可选 mem0 后端

设置里可以切换「记忆后端 = mem0 云平台」，此时：

| 本地实现 | mem0 映射 |
| --- | --- |
| `userId` | `user_id` |
| `ingest()` | `POST /v1/memories/`（messages + user_id） |
| `retrieve()` | `POST /v1/memories/search/`（query + user_id + limit） |
| 记忆中心列表 | `GET /v1/memories/?user_id=` |
| 删除 | `DELETE /v1/memories/{id}/` |

mem0 负责抽取与更新，本地只保留会话与展示缓存；上下文压缩始终在本地完成
（因为压缩属于「当前会话上下文管理」，与长期记忆托管无关）。

## 8. 失败与降级

- 记忆抽取失败：不影响回复，下一轮继续；
- 记忆检索失败：按空记忆处理；
- 压缩失败：保留完整上下文（可能超长，模型侧会报错，UI 会提示）；
- Secret 不可用（部分 ROM 的 KeyStore 异常）：退化为本机明文存储并在设置页提示；
- 无网络：仅本地操作可用，记忆召回降级为空。

## 9. 已知取舍与路线图

- 关键词召回没有向量语义召回强。后续可在 `MemoryStore` 上增加 embedding 字段，
  用 DeepSeek / 远程 embedding 服务补齐，接口已隔离，不影响上层；
- 长期记忆会随时间膨胀，后续加入「遗忘策略」（低分且长期未访问自动归档）；
- 跨设备同步未实现，目前靠备份/恢复 JSON 迁移。
