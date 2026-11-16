# DeepSeek 官方 Web Demo · UI 规格还原表（Flutter 1:1 复刻用）

> 数据来源：`/root/workspace/ref/chatdemo/` 编译产物（`index.html`、`static/css/main.7361e32c.css`、`static/css/async/4959.1382f613.css`、`static/js/main.9820cd3a.js`）。
> 所有数值均从 CSS 声明中**逐条展开 var() 链**后得出，不是猜测；无对应声明的项标注「推断」或「不存在」。
> 口径说明：实际 CSS 为 **88,771 字节（压缩单行，721 条规则）**、JS 为 474,903 字节，与任务描述中的「4.6MB」不符；本表以实际文件为准。主题变量定义在 `body`（浅色）与 `body[data-ds-dark-theme]`（深色），非 `[data-ds-dark-theme]` 裸选择器。

样式类名后缀对照（便于回查 CSS）：
| 模块 | 类名后缀 | 作用 |
|---|---|---|
| 主框架 | `.frame-_9fdf5` / `.main-_9fdf5` / `.content-_9fdf5` | 页面骨架 |
| 侧栏 | `.sider-ac14ac` / `.newChat-ac14ac` / `.item-ff6fc9` | 侧栏、新建、会话项 |
| 顶栏 | `.header-_5fa77`（桌面） / `.header-cf83dc`（移动） | 顶部标题栏 |
| 消息列 | `.container-_7ccaf` / `.scroll-_7ccaf` / `.column-_7ccaf` | 滚动区 + 内容列 |
| 用户消息 | `.container-_4cfe7` / `.bubble-_4cfe7` | 用户气泡 |
| 助手消息 | `.message-e1faee` / `.ds-markdown` / `.ds-assistant-message-main-content` | 助手正文（无气泡） |
| 思考面板 | `.area-_3d93a` / `.title-_3d93a` / `.content-_3d93a` | 已深度思考折叠区 |
| 输入区 | `.wrapper-ed6f47` / `.textarea-ed6f47` / `.sendButton-ed6f47` / `.toggle-ed6f47` / `.functionRow-ed6f47` | 输入卡片 |
| 欢迎页 | `.container-_1f155` / `.welcome-_1f155` / `.greeting-_1f155` | 空会话页 |
| 代码块 | `.md-code-block` / `.md-code-block-banner` | Markdown 代码块 |

---

## 1. 颜色（全部为展开后的最终值）

### 1.1 基础语义色板（浅色 / 深色）

| 用途 | Token（回查用） | 浅色 | 深色 |
|---|---|---|---|
| 页面底色 | `--dsw-alias-bg-base` | `#FFFFFF` | `#151517` |
| 卡片/弹窗底色（layer-2） | `--dsw-alias-bg-layer-2` | `#FFFFFF` | `#2C2C2E` |
| 浮层底色（layer-3） | `--dsw-alias-bg-layer-3` | `#FFFFFF` | `#353638` |
| 骨架/占位底 | `--dsw-alias-bg-skeleton` | `rgba(0,0,0,.04)` | `rgba(255,255,255,.08)` |
| 正文色 | `--dsw-alias-label-primary` | `#0F1115` | `#F9FAFB` |
| 次要文字 | `--dsw-alias-label-secondary` | `#61666B` | `#CFD3D6` |
| 三级文字 | `--dsw-alias-label-tertiary` | `#81858C` | `#ADB2B8` |
| 说明/占位文字（caption） | `--dsw-alias-label-caption` | `#ADB2B8` | `#81858C` |
| 极淡分隔/时间线 | `--dsw-alias-label-dimmed` | `#E1E5EE` | `#43454A` |
| 反色文字 | `--dsw-alias-label-primary-foreground` / `-inverted` | `#FFFFFF` | `#FFFFFF` |
| 边框 L1（最淡，仅侧栏右框） | `--dsw-alias-border-l1` | `rgba(0,0,0,.04)` | `rgba(255,255,255,.06)` |
| 边框 L2（输入框/常规） | `--dsw-alias-border-l2` | `rgba(0,0,0,.10)` | `rgba(255,255,255,.12)` |
| 边框 L2 暗色薄化 | `--dsw-alias-border-l2-darkmode-thin` | `rgba(0,0,0,.10)` | `rgba(255,255,255,.06)` |
| 边框 L3（加重） | `--dsw-alias-border-l3` | `rgba(0,0,0,.12)` | `rgba(255,255,255,.16)` |
| 反色边框 | `--dsw-alias-border-inverted` | `transparent` | `rgba(255,255,255,.06)` |
| **品牌蓝**（主色） | `--dsw-alias-brand-primary` | **`#3964FE`** | **`#5686FE`** |
| 品牌蓝文字（链接） | `--dsw-alias-brand-text` | `#3964FE` | `#679EFE` |
| 品牌蓝反色（侧栏选中字） | `--dsw-alias-brand-primary-invert` | `#3964FE` | `#FFFFFF` |
| 主按钮填充 | `--dsw-alias-button-primary-fill` | `#3964FE` | `#5686FE` |
| 主按钮 hover | `--dsw-alias-button-primary-hover` | `#5686FE` | `#3964FE` |
| 悬浮按钮填充 | `--dsw-alias-button-elevated-fill` | `#FFFFFF` | `#43454A` |
| 对比按钮填充 | `--dsw-alias-button-contrast-fill` | `#61666B` | `#F9FAFB` |
| 幽灵按钮激活底 | `--dsw-alias-button-ghost-active-fill` | `#EDF3FE` | `#283142` |
| 幽灵按钮激活边 | `--dsw-alias-button-ghost-active-border` | `#B7C8FE` | `#4868B2` |
| 幽灵按钮激活 hover | `--dsw-alias-button-ghost-active-hover` | `#E4EDFD` | `#34415B` |

> ⚠️ 品牌蓝实测为 **`#3964FE`**（深色 `#5686FE`），不是 DeepSeek 主站常见的 `#4D6BFE`；本 demo 蓝色色阶为 50 `#EDF3FE` / 100 `#E4EDFD` / 200 `#D3E2FF` / 300 `#B7C8FE` / 400 `#679EFE` / 450 `#5686FE` / 500 `#3964FE` / 600 `#4868B2` / 800 `#34415B` / 900 `#283142`。

### 1.2 组件专用色

| 用途 | Token | 浅色 | 深色 |
|---|---|---|---|
| 侧栏底色 | `--dsw-specific-sidebar-fill` | `#F9FAFB` | `#1B1B1C` |
| 侧栏会话项 hover | `--dsw-specific-sidebar-nav-item-hover` | `#F1F3F5` | `#2C2C2E` |
| 侧栏会话项选中底 | `--dsw-specific-sidebar-nav-item-active-accent` | `#E4EDFD` | `#353638` |
| **用户气泡底** | `--dsw-specific-bubble` | **`#EDF3FE`** | **`#2C2C2E`** |
| 输入框主底色 | `--dsw-specific-input-major` | `#FFFFFF` | `#2C2C2E` |
| 菜单/浮层底 | `--dsw-specific-menu` | `#FFFFFF` | `#353638` |
| 选择器/主题卡选中底 | `--dsw-specific-selector` | `#F1F3F5` | `#43454A` |
| 登录输入底 | `--dsw-specific-login-input` | `#F9FAFB` | `#1B1B1C` |
| **代码块底** | `--dsw-alias-markdown-code-block` | **`#F9FAFB`** | **`#1B1B1C`** |
| 代码块标题栏底 | `--dsw-alias-markdown-code-block-banner` | `#F9FAFB` | `#2C2C2E` |
| 行内代码底 | `--dsw-alias-markdown-inline-code` | `#EBEEF2` | `#2C2C2E` |
| 引用角标底 | `--dsw-alias-markdown-citation` | `#EBEEF2` | `#353638` |
| 占位符底 | `--dsw-alias-markdown-placeholder` | `#F5F6F7` | `#2C2C2E` |
| 标签/chip 底 | `--dsw-alias-markdown-tag` | `#F1F3F5` | `#2C2C2E` |
| **hover 底色**（通用） | `--dsw-alias-interactive-bg-hover` | **`rgba(38,49,72,.06)`** | **`rgba(255,255,255,.08)`** |
| 按下底色（通用） | `--dsw-alias-interactive-bg-active` | `rgba(38,49,72,.10)` | `rgba(255,255,255,.14)` |
| hover 强调 | `--dsw-alias-interactive-bg-hover-accent` | `rgba(38,49,72,.14)` | `rgba(255,255,255,.24)` |
| hover 危险 | `--dsw-alias-interactive-bg-hover-danger` | `rgba(236,19,19,.05)` | `rgba(242,90,90,.15)` |
| 滚动条 | `--scroll-color` / `--scroll-color-hover` | `rgba(0,0,0,.08)` / `rgba(0,0,0,.15)` | `rgba(255,255,255,.15)` / `rgba(255,255,255,.24)` |
| 错误主色 | `--dsw-alias-state-error-primary` | `#EC1313` | `#F25A5A` |
| Toast 底 | `--dsw-alias-toast-bg` | `#353638` | `#43454A` |
| Tooltip 底 | `--dsw-alias-tooltip-bg` | `#2C2C2E` | `#43454A` |
| 遮罩（模态） | `.overlay-_83af2` | `rgba(0,0,0,.36)` + blur(2px) | `rgba(0,0,0,.60)` + blur(2px) |
| 遮罩（确认弹窗） | `.mask-_4f2ab` | `rgba(255,255,255,.7)` + blur(10px) | `rgba(39,39,48,.7)` + blur(10px) |

---

## 2. 布局

| 项 | 数值（桌面 ≥1024px） | 数值（≤1023px） | 来源类 |
|---|---|---|---|
| 侧栏宽度 | **261px**（`flex-shrink:0`，`height:100%`） | 移动端抽屉 **300px**，`max-width:calc(100vw - 48px)` | `.sider-ac14ac` / `.mobile-ac14ac` |
| 侧栏内边距 | `6px 12px 0` | 同 | `.sider-ac14ac` |
| 侧栏右边框 | `1px solid rgba(0,0,0,.04)` / 深色 `rgba(255,255,255,.06)` | 同 | `.sider-ac14ac` |
| 聊天内容区最大宽度 | **840px**（`--message-list-max-width:840px`） | **712px** | `:root` + `@media (max-width:1023px)` |
| 内容区左右内边距 | **44px**（`--message-list-padding-horizontal:44px`） | **36px** | 同上 |
| 实际内容列宽 | `calc(840px - 88px)` = **752px**，`max-width:calc(100% - 40px)`，`margin:0 auto`，`padding-bottom:24px` | `calc(712px - 72px)` = **640px** | `.column-_7ccaf` |
| 输入容器宽 | `calc(840px - 64px)` = **776px**，`max-width:calc(100% - 32px)`，`margin:auto auto 0`，sticky bottom | **648px** | `.inputContainer-_5fa77` |
| 顶栏高度 | **60px**（桌面 `.header-_5fa77`：`padding:12px 18px 0`；移动 `.header-cf83dc`：`padding:12px 10px 4px`） | 60px | `.header-_5fa77` / `.header-cf83dc` |
| 欢迎页内容宽 | `max-width:840px`，`padding:0 32px 64px`，垂直居中 | `padding:0 16px env(safe-area-inset-bottom)`，`justify-content:flex-end` | `.welcome-_1f155` |
| 消息列表滚动 | `scrollbar-gutter:stable both-edges`，`overflow-y:auto` | `scrollbar-gutter:auto` | `.container-_7ccaf` |
| 页面根 | `html,body,#root{height:100%;overflow:hidden}` | 移动端 `.frame` 改 `position:fixed` + `--app-viewport-height` | `html,body,#root` |

---

## 3. 消息

### 3.1 用户消息（右侧气泡）

| 项 | 浅色 | 深色 | 来源 |
|---|---|---|---|
| 容器对齐 | `display:flex; flex-direction:column; align-items:flex-end; padding-bottom:16px` | 同 | `.container-_4cfe7` |
| 首条消息上间距 | `padding-top:34px`（`.isFirst`） | 同 | `.container-_4cfe7.isFirst-_4cfe7` |
| 气泡最大宽度 | `calc(100% - 88px)`（列宽 752px 时约 **664px**） | 同 | `.bubble-_4cfe7` |
| 窄屏（<440px）最大宽度 | `calc(100% - 68px)` | 同 | `@media (max-width:439px)` |
| 气泡 padding | **`10px 16px`** | 同 | `.bubble-_4cfe7` |
| 气泡圆角 | **`22px`** | 同 | `.bubble-_4cfe7` |
| 气泡底色 | `#EDF3FE` | `#2C2C2E` | `.bubble-_4cfe7` |
| 气泡文字色 | `#0F1115` | `#F9FAFB` | `.bubble-_4cfe7` |
| 字号/行高 | **`16px / 24px`** | 同 | `.bubble-_4cfe7` |
| 文本换行 | `white-space:pre-wrap; word-break:break-word` | 同 | `.bubble-_4cfe7` |
| 附件行 | `gap:10px; margin-bottom:8px; justify-content:flex-end`；缩略图 `64×64`、圆角 `16px` | 同 | `.files-_4cfe7` |
| 气泡下操作栏 | `height:28px; margin-top:6px; gap:10px`，默认 `opacity:0`，hover/focus 显示 | 同 | `.bottom-_4cfe7` / `.actions-_4cfe7` |

### 3.2 助手消息（无气泡、无头像）

| 项 | 数值 | 来源 |
|---|---|---|
| 头像 | **不存在**（CSS 无 avatar 类；JS 中 avatar 仅出现在 i18n key） | 反查结论 |
| 气泡 | 无，直接排版在内容列左侧 | `.message-e1faee`（仅 `position:relative`） |
| 正文字号/行高 | **`16px / 28px`**，颜色 `#0F1115` / `#F9FAFB` | `.ds-markdown` |
| 段落外边距 | **`margin:16px 0`**；首段 `margin-top:0!important`、末段 `margin-bottom:0!important` | `.ds-markdown .ds-markdown-paragraph` |
| 标题 | h1 `700 24/34`（margin `32px 0 16px`）；h2 `700 22/32`；h3 `700 20/30`；h4 `600 16/28` | `.ds-markdown h1..h6` |
| 列表 | `margin:16px 0; padding-left:18px`，`li+li` 间距 `6px`，marker 色 `#61666B` | `.ds-markdown ul/ol/li` |
| 引用 | `border-left:2px solid #ADB2B8; padding-left:14px; margin-top:16px` | `.ds-markdown blockquote` |
| 分隔线 | `height:1px; background:rgba(0,0,0,.1)` / 深 `rgba(255,255,255,.12)`；`margin:32px 0` | `.ds-markdown hr` |
| 表格 | 表头 `500 15/25`，单元格 `15/25`，`padding:10px 16px`，`border-bottom:1px solid`（th 用 l3，td 用 l2） | `.ds-markdown table` |
| 正文底部内边距 | `padding-bottom:6px` | `.message-e1faee .ds-assistant-message-main-content` |
| 底部操作栏 | `padding-top:12px; padding-bottom:10px; gap:10px; left:-6px`；图标按钮 28px（`.xs`） | `.bottom-e1faee` / `.button-_7c3cd.xs` |
| 联网来源汇总按钮 | `margin-top:16px; padding:4px 10px 4px 4px; border-radius:100px; border:1px solid` l2；字体 `14/24` | `.summary-e1faee` |

### 3.3 消息之间垂直间距（推断汇总）

| 位置 | 数值 |
|---|---|
| 用户气泡 → 下一条助手正文 | **16px**（用户容器 `padding-bottom:16px`） |
| 助手正文 → 工具/操作栏 | `6px`（正文 `padding-bottom`）+ 操作栏 `padding-top:12px` |
| 助手操作栏 → 下一条用户消息 | 约 **10px**（操作栏 `padding-bottom:10px`）；操作栏不渲染时约 6px（推断） |
| 列表首条消息上边距 | **34px** |
| 列表底部内边距 | **24px** |

### 3.4 深度思考折叠面板（补充）

| 项 | 数值 | 来源 |
|---|---|---|
| 面板下间距 | `margin-bottom:10px` | `.area-_3d93a` |
| 标题行高 | `height:34px`，字色 `#61666B`（hover `#0F1115`），`margin-bottom:2px` | `.title-_3d93a` |
| 思考正文 | 全宽，`padding:5px 0 5px 22px`；左侧竖线 `1px`，色 `#E1E5EE` / 深 `#43454A`，`left:7.5px` | `.content-_3d93a` / `:after` |
| 思考文本字号 | `14px / 24px`（`.ds-think-content .ds-markdown`），色 `#61666B` / `#CFD3D6` | `.ds-think-content` |
| 步骤行 | 高 `34px`，字号 14/24；hover 胶囊底 `rgba(38,49,72,.06)`，圆角 100px，`width:calc(100% + 20px)` | `.row-_3d93a` |
| chip | 高 `20px`，`padding:0 5px`，圆角 `6px`，底 `#F1F3F5`，字号 `13/20` | `.chip-_3d93a` |

### 3.5 代码块与行内代码

| 项 | 浅色 | 深色 | 来源 |
|---|---|---|---|
| 代码块底 | `#F9FAFB` | `#1B1B1C` | `.md-code-block` |
| 代码块圆角 | **`12px`** | 同 | `.md-code-block` |
| 代码块外边距 | `margin:16px 0`（非最后一项再补 `margin-bottom:11px`） | 同 | `.md-code-block` |
| 标题栏 | 底 `#F9FAFB`（深 `#2C2C2E`），字体 `13px/20px`，左右上圆角 12px | 同 | `.md-code-block-banner` |
| 代码内容 | 字体 `13px/22px` 等宽；`padding:16px`；`white-space:pre-wrap; word-break:break-all` | 同 | `.md-code-block>pre` |
| 行内代码 | `font-size:.875em!important`（≈14px），`14px/22px` 等宽，底 `#EBEEF2`（深 `#2C2C2E`），圆角 `6px`，`padding:0 5px` | 同 | `.ds-markdown code` |

---

## 4. 欢迎页（空会话）

| 项 | 数值 | 来源 |
|---|---|---|
| 容器 | 绝对铺满，内容列 `max-width:840px`，`padding:0 32px 64px`，水平/垂直居中 | `.welcome-_1f155` |
| 标题文案 | 「今天有什么可以帮到你？」（`welcomeMessageChat250808`） | JS i18n |
| 标题字号/行高 | **`24px / 32px`**，`font-weight:600`，色 `#0F1115` / `#F9FAFB`，居中 | `.greeting-_1f155` |
| 标题下间距 | **`21px`** | `.greeting-_1f155` |
| 窄屏（≤439px）标题 | `20px / 28px`，`font-weight:500` | `@media (max-width:439px)` |
| 建议项 / 推荐问题卡片 | **不存在**：欢迎页 DOM 仅 `greeting + 输入区 + (移动端)免责声明`，CSS/JS 无 suggest/prompt/card 相关类 | JSX 反查 |
| 移动端布局 | `justify-content:flex-end`，标题 `margin:auto 0`，`padding:0 16px env(safe-area-inset-bottom)` | `@media not all and (min-width:768px)` |

---

## 5. 输入区

| 项 | 数值 | 来源 |
|---|---|---|
| 容器宽 | `calc(840px - 64px)` = 776px（≤1023px：648px），`max-width:calc(100% - 32px)`，底部 sticky | `.inputContainer-_5fa77` |
| 容器背景 | `linear-gradient(to bottom, transparent 0%, transparent 30%, #FFF 30%, #FFF 100%)`（深色末段为 `#151517`），用于渐隐消息 | `.inputContainer-_5fa77` |
| 卡片圆角 | **`24px`** | `.wrapper-ed6f47` |
| 卡片背景 | `#FFFFFF` / 深 `#2C2C2E` | `.wrapper-ed6f47` |
| 卡片边框 | `1px solid rgba(0,0,0,.10)` / 深 `rgba(255,255,255,.06)` | `.wrapper-ed6f47` |
| 卡片阴影（欢迎页 home） | `0 4px 12px rgba(0,0,0,.02), 0 2px 2px rgba(72,104,178,.01), 0 30px 60px rgba(72,104,178,.03)`；深色 **无阴影** | `.home-ed6f47` |
| 卡片阴影（会话中） | `0 4px 10px rgba(0,0,0,.02), 0 2px 4px rgba(0,0,0,.04)` | `.session-ed6f47` |
| 输入框最小高度 | `calc(24px*2 + 12px)` = **60px**（两行）；<440px 时 `calc(24*1.25+12)` = **42px** | `.textarea-ed6f47` |
| 输入框内边距 | `12px 12px 0 16px` | `.textarea-ed6f47` |
| 输入字号/行高 | **`16px / 24px`**，光标色 `#3964FE` | `.textarea-ed6f47` |
| 占位符色 | `#ADB2B8` / 深 `#81858C` | `::placeholder` |
| 最大高度 | 桌面 `max-height:336px`（mirror）；移动端卡片 `max-height:calc(100dvh - 120px)` | `.mirror-ed6f47` |
| 功能行 | `padding:12px`，`margin-top:4px`，`gap:8px` | `.functionRow-ed6f47` |
| 发送按钮 | **`34×34` 圆形**（`border-radius:50%`），底 `#3964FE`/`#5686FE`，hover `#5686FE`/`#3964FE`，`margin-left:6px`；禁用 `opacity:.4` | `.sendButton-ed6f47` |
| 开关（深度思考/联网） | 高 **34px**，圆角 `18px`，`padding:0 12px`，字号 `13px/20px`、500；选中底 `#EDF3FE`/`#283142`、字 `#3964FE`、边 `#B7C8FE`/`#4868B2` | `.toggle-ed6f47` |
| 附件缩略图 | `64×64`，圆角 `16px`，边框 `1px` l2，底 `rgba(0,0,0,.04)`；附件行 `padding:12px 12px 0; gap:10px` | `.attachment-ed6f47` / `.attachments-ed6f47` |
| 卡片总高度（默认两行，推断） | ≈ **124px** = 输入 60 + 功能行(4+24+34) + 边框 2 | 由上述值相加 |
| 底部免责声明 | 字号 **`11px / 16px`**，色 `#81858C` / `#ADB2B8`，`padding:6px 0`，居中；文案「内容由 AI 生成，请仔细甄别」（`contentCaveat`） | `.caveat-_5fa77` |
| 免责声明显示范围 | 会话页桌面/移动都显示；欢迎页仅 <768px 渲染（`.caveat-_1f155` 样式只在移动媒体查询内定义，值同上） | JSX 条件渲染 + `.caveat-_1f155` |

---

## 6. 字体

### 6.1 字体栈（原样）

- 正文 / UI：
  `system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen, Ubuntu, Cantarell, "Open Sans", "Helvetica Neue", sans-serif`
  （`--dsw-font-family`；`font-variant-ligatures:no-contextual`）
- 代码：
  `Menlo, Monaco, Consolas, "Cascadia Mono", "Ubuntu Mono", "DejaVu Sans Mono", "Liberation Mono", "JetBrains Mono", "Fira Code", Cousine, "Roboto Mono", "Courier New", Courier, sans-serif, system-ui`
  （`--ds-font-family-code`）
- 全局：`body{font-family:var(--dsw-font-family); font-size:14px; color:#0F1115; background:#FFFFFF; -webkit-font-smoothing:antialiased}`

### 6.2 字号 / 行高（展开后）

| Token | 值 | 典型用途 |
|---|---|---|
| `--dsw-font-markdown-base` | `16px/28px` | 助手正文 |
| `--dsw-font-markdown-base-strong` | `600 16px/28px` | 正文加粗/h5、h6 |
| `--dsw-font-markdown-h1` | `700 24px/34px` | 正文 h1 |
| `--dsw-font-markdown-h2` | `700 22px/32px` | h2 |
| `--dsw-font-markdown-h3` | `700 20px/30px` | h3 |
| `--dsw-font-markdown-h4` | `600 16px/28px` | h4 |
| `--dsw-font-markdown-small` | `14px/24px` | 思考内容、汇总按钮 |
| `--dsw-font-markdown-small-strong` | `600 14px/24px` | 思考标题、表头 |
| `--dsw-font-markdown-table` | `15px/25px` | 表格正文 |
| `--dsw-font-markdown-table-head` | `500 15px/25px` | 表格表头 |
| `--dsw-font-markdown-code` | `14px/22px`（等宽） | 行内代码 |
| `--dsw-font-markdown-code-block` | `13px/22px`（等宽） | 代码块 |
| `--dsw-font-xs-13` | `13px/20px` | 开关、chip、代码块标题 |
| `--dsw-font-s-strong-14` | `500 14px/22px` | 顶栏标题 |
| `--ds-font-size-m` | `14px` | 正文基准（body） |

### 6.3 字号速查（全局出现的固定 px）

| 字号 | 行高 | 出现位置 |
|---|---|---|
| 11px | 16px | 免责声明、附件失败原因 |
| 12px | 18px | 侧栏分组标题（桌面） |
| 13px | 20px | 开关、chip、代码块标题栏 |
| 13px | 22px | 代码块内容 |
| 14px | 22px | 侧栏会话项/新建按钮/设置项/弹窗正文 |
| 14px | 24px | 思考正文、汇总按钮 |
| 15px | 25px | 表格 |
| 16px | 24px | 用户气泡、输入框（桌面代码块 pre 内 13px） |
| 16px | 28px | 助手正文 |
| 20px | 22px | 侧栏 App 名（API 使用 demo） |
| 20px | 28px | 窄屏欢迎标题、确认弹窗标题 |
| 24px | 32px | 欢迎页标题 |
| 24px | 34px | markdown h1 |

---

## 7. 侧栏

| 项 | 数值 | 来源 |
|---|---|---|
| 侧栏 | 宽 **261px**，底 `#F9FAFB`/`#1B1B1C`，右边框 1px l1，`padding:6px 12px 0` | `.sider-ac14ac` |
| 顶部区 | 高 **48px**，`margin-bottom:16px`，`padding:15px 0 10px 4px`，`gap:8px` | `.top-ac14ac` |
| App 名 | 字号 **`20px / 22px`**，600，色 `#3964FE`/`#5686FE`，`padding-left:4px` | `.appName-ac14ac` |
| 新建对话按钮 | 高 **40px**，宽 100%，圆角 **`100px`**，`padding:0 16px`，字号 `14px`/500，底 `#FFFFFF`/`#43454A`，文字 `#0F1115`/`#F9FAFB`，图标右距 6px | `.newChat-ac14ac` |
| 新建按钮阴影 | `0 -2px 2px rgba(72,104,178,.04), 0 2px 2px rgba(106,111,117,.09), 0 1px 2px rgba(72,104,178,.08)`；hover 换成 `0 4px 4px …/0 -3px 4px …/0 6px 6px rgba(106,111,117,.1)`；深色 `border:none; box-shadow:inset 0 1px 1px rgba(255,255,255,.1),0 2px 4px rgba(106,111,117,.08)` | `.newChat-ac14ac` |
| 列表区 | `margin-top:24px`；`.list` 高 100%，`margin:0 -2px; padding:0 2px`，滚动条 `rgba(0,0,0,.08)` | `.listWrap-ac14ac` / `.list-ac14ac` |
| 分组 | `.section` 上间距 **16px**，`padding-top:4px`（首组 0） | `.section-ac14ac` |
| 分组标题 | **`12px / 18px`**、500、色 `#81858C`/`#ADB2B8`，`padding:2px 10px`，底同侧栏色，sticky `top:0` | `.sectionHeader-ac14ac` |
| 分组标题（移动端） | `14px / 22px`，`padding:4px 10px 3px` | `.mobile-ac14ac .sectionHeader-ac14ac` |
| 会话项 | 高 **40px**，圆角 **`12px`**，`padding:9px 6px 9px 10px`，字号 `14px`，行高 `22px`，文字 `#0F1115`/`#F9FAFB` | `.item-ff6fc9` |
| 会话项 hover | 底 `#F1F3F5` / `#2C2C2E` | `.item-ff6fc9:not(.active):hover` |
| 会话项选中 | 底 `#E4EDFD` / `#353638`，文字 `#3964FE` / `#FFFFFF` | `.item-ff6fc9.active-ff6fc9` |
| 会话项标题 | `line-height:18px`，单行省略，右侧操作按钮 `margin-left:4px` | `.title-ff6fc9` / `.action-ff6fc9` |
| 会话项（移动端） | 高 **44px**，圆角 **`16px`**，`padding:11px 6px 11px 12px`，字号 16px | 媒体查询内覆盖 |
| 重命名输入框 | 高 40px，圆角 12px，边框 `1px solid #3964FE`，`padding:0 10px`，字号 14px | `.renameInput-ff6fc9` |
| 底部入口区 | 高 **64px**；设置项圆角 12px，`padding:6px 2px 6px 6px`，图标 32×32，标签 `14px`、左边距 4px；hover 底 `#F1F3F5`/`#2C2C2E` | `.bottom-ac14ac` / `.settings-ac14ac` |
| 折叠态悬浮条 | `.collapsedGroup` 高 40px，圆角 100px，边框 l2，底 `#FFFFFF`/`#353638`，`padding:0 2px`，阴影 `0 4px 12px rgba(0,0,0,.04)`；`margin:12px 0 0 16px` | `.collapsedGroup-ac14ac` |
| 桌面折叠后标题偏移 | `.withCollapsedSider` `margin-left:113px` | `.withCollapsedSider-_5fa77` |

---

## 8. 深色主题（汇总）

深色由 `body[data-ds-dark-theme]` 触发（另有 `body.dark` 仅供代码高亮 token 使用，`body.dark{color-scheme:dark}`）。

| 项 | 深色值 |
|---|---|
| 页面底色 | `#151517` |
| 侧栏底色 | `#1B1B1C` |
| 卡片/弹窗底 | `#2C2C2E`（layer-2）/ `#353638`（layer-3） |
| 输入卡底 | `#2C2C2E`，边框 `rgba(255,255,255,.06)`，欢迎页输入卡无阴影 |
| 用户气泡底 | `#2C2C2E`；文字 `#F9FAFB` |
| 代码块底 | `#1B1B1C`；标题栏 `#2C2C2E`；行内代码 `#2C2C2E` |
| 正文 | `#F9FAFB` |
| 次要文字 | `#CFD3D6` |
| 三级文字 | `#ADB2B8`；caption `#81858C` |
| 边框 l1/l2/l3 | `rgba(255,255,255,.06)` / `.12` / `.16` |
| 品牌蓝 | `#5686FE`（链接文字 `#679EFE`，hover 反转为 `#3964FE`） |
| 用户气泡/输入框 | 见上 |
| hover 底 | `rgba(255,255,255,.08)`；按下 `rgba(255,255,255,.14)` |
| 侧栏项 hover / 选中 | `#2C2C2E` / `#353638` |
| 滚动条 | `rgba(255,255,255,.15)` / `.24` |
| 新建按钮 | `border:none`，`box-shadow:inset 0 1px 1px rgba(255,255,255,.1),0 2px 4px rgba(106,111,117,.08)`，底 `#43454A` |
| 遮罩 | 弹窗 `rgba(0,0,0,.60)`（`--overlay-opacity:.6`）；确认页 `rgba(39,39,48,.7)` |
| 侧栏选中文字 | 品牌蓝反色 = `#FFFFFF` |

---

## 9. 响应式断点（媒体查询清单）

| 断点 | 生效内容 |
|---|---|
| **`@media (max-width:1023px)`** | `--message-list-max-width:712px`、`--message-list-padding-horizontal:36px`（即 712/36 替换 840/44） |
| **`@media not all and (min-width:768px)`**（<768px，移动布局） | 侧栏改抽屉（宽 300px，`max-width:calc(100vw - 48px)`）；`.container-_7ccaf` 改 `overflow:hidden` 且 `.scroll` 负责滚动；`inputContainer` 改 `position:relative` + `padding-bottom:env(safe-area-inset-bottom)`；`.welcome` 改 `justify-content:flex-end`、`padding:0 16px`；顶栏切到 `.header-cf83dc`；`.frame` 改 `position:fixed` + `--app-viewport-height`；附件行/功能行 `flex-shrink:0`；弹窗底部圆角 24px 24px 0 0、高 `calc(100% - 64px)`；会话项 44px/圆角 16px；分组标题 14/22；设置项 `padding:9px 10px` |
| **`@media not all and (min-width:440px)`** / **`@media (max-width:439px)`**（<440px） | 用户气泡 `max-width:calc(100% - 68px)`；输入框最小高度 `calc(24*1.25+12)`=42px；欢迎标题 `20px/28px`、500；欢迎页 `padding:0 16px` |
| `@media (hover:hover)` | 所有 hover 样式（按钮/会话项/操作栏）仅在支持 hover 的设备生效；`@media (hover:none)` 下会话项操作按钮常显 |
| `@media (prefers-reduced-motion:reduce)` | 关闭动画（加载条、呼吸光晕、思考 shimmer） |
| `@container (width<=63px)` | 附件缩略图小尺寸时隐藏失败原因文字 |

**控件高度阶梯**：`--ds-control-height-xs:28px / s:32px / m:36px / l:40px / xl:44px`；图标圆钮尺寸 `xs 28 / m 34 / xl 44`，普通按钮 `radius:4096px`、`min-width:72px`、`padding:0 14px`、字号 `14/22`。

---

## 10. 不确定 / 缺失项（不编造）

1. **建议问题卡片**：本 demo 欢迎页没有该 UI（JSX 只有 greeting + 输入区），规格中标注「不存在」。若要对齐 DeepSeek 主站，需要另找素材。
2. **头像**：消息列表无头像组件，用户/助手均无头像。
3. **消息列表首条助手消息的上间距**：CSS 未单独声明，按「用户容器 `padding-bottom:16px`」推断。
4. **输入卡总高度** 124px 为分项相加的推断值，CSS 未直接给出。
5. **代码高亮 token 颜色**：浅色主题（`body.light`）用的是 One Light 系（如注释 `#A0A1A7`、关键字 `#A626A4`、字符串 `#50A14F`、函数 `#4078F2`…），深色主题用自研色板（注释 `#8DA1B9`、关键字 `#E9AE7E`、字符串 `#91D076`、数字 `#E6D37A`、函数 `#C699E3`…）——本文只列了主色，如需逐 token 表可再展开。
6. **字号 13/14/15/16 中 15px** 只用于 Markdown 表格，正文类 UI 未使用 15px。
