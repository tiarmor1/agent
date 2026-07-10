# Claude Code 源码架构深度解析

> 📋 **文档信息** 基于 Claude Code v2\.1\.88 源码（约 51 万行 TypeScript）整理。

> 源码通过 npm 包中泄露的 sourcemap 还原。可以运行的 claude code 源码位于 https://code\.byted\.org/xiangyang\.6/claude\-code\-source

---

# Claude Code 源码架构深度解析

## 一、项目概述与架构

Claude Code 是 Anthropic 官方推出的 AI 编程助手**终端客户端**，深度集成 Shell、文件系统、Git、LSP、MCP 的 CLI/TUI 应用。以 **Agentic Loop** 为核心，让 Claude 模型自主读写文件、执行命令、搜索代码、管理任务。

> \*\***🎯 核心特点**

|能力|说明|
|---|---|
|🖥️ **终端 UI**|基于 React Ink 的 TUI，支持 Vim 模式、搜索高亮|
|🔧 **工具生态**|42 个内建工具 \+ MCP 动态扩展|
|🧠 **多 Agent**|多级子 Agent \+ 多 Agent 团队协作|
|🔐 **权限安全**|精细权限控制，多层安全模型|
|📦 **三层扩展**|Skills \+ Plugins \+ MCP 扩展机制|
|🌐 **多端支持**|CLI / SDK / MCP Server / Chrome 扩展|

> \*\***📊 关键数据**

|指标|数值|
|---|---|
|📄 文件规模|\~1,930 个 TS/TSX 文件，\~513,000 行代码|
|📏 最大文件|`messages.ts`（5,513 行 / 193KB）|
|🔧 工具目录|42 个|
|🪝 Hook 事件|20\+ 种|
|🚩 Feature Flags|30\+ 个|
|🧠 CLAUDE\.md 记忆|4 层优先级|
|⚙️ 配置级联|5 层覆盖|

### 1\.1 高层架构总览

### 1\.2 项目结构

```Plain Text
claude-code-source/src/
├── entrypoints/          # 入口层：CLI、MCP Server、SDK 入口
│   ├── cli.tsx            # CLI 主入口（303 行），快速路径路由
│   ├── mcp.ts             # MCP Server 入口
│   └── sdk/               # SDK 入口
├── main.tsx              # 主程序（4,692 行 / 804KB）
├── QueryEngine.ts        # API 请求引擎（1,308 行）
├── query.ts              # 核心查询循环（1,730 行），Agentic Loop 实现
├── Tool.ts               # 工具基类接口（793 行）
├── tools.ts              # 工具注册表（383 行）
├── commands.ts           # 斜杠命令注册（755 行）
├── tools/                # 42 个工具实现，每个工具一个目录
├── components/           # UI 组件层（113 个文件 + 31 个子目录）
├── hooks/                # React Hooks 层（85 个文件）
├── state/                # 状态管理（Zustand）
├── services/             # 服务层（21 个子目录 + 16 个文件）
├── utils/                # 工具库（298 个文件 + 31 个子目录）
├── constants/            # 常量定义
├── coordinator/          # Coordinator 多 Agent 编排
├── tasks/                # 后台任务类型（9 个任务目录）
├── skills/               # 内建 Skill 系统
├── plugins/              # 插件系统
├── remote/               # 远程会话管理
├── voice/                # 语音相关模块
├── ink/                  # React Ink fork
└── vim/                  # Vim 模式实现

```

---

## 二、入口层 \(Entrypoints\)

### 2\.1 CLI 入口

核心文件是 `src/entrypoints/cli.tsx`（303 行），采用**快速路径（Fast Path）模式**最小化启动时间：

> **💡 设计亮点**：每条路径都是**惰性导入（dynamic import）**，只在匹配时才加载对应模块，确保 `--version` 在毫秒级返回。

### 2\.2 主程序 \(main\.tsx\)

`main.tsx` 是全项目最大的单文件（4,692 行 / 804KB），负责：

1. **Commander\.js CLI 参数解析** — 定义所有命令行参数

2. **初始化流程** — 配置加载、认证、MCP 连接、插件加载

3. **运行模式路由**：

    - **REPL 模式**: 交互式终端（基于 React Ink 渲染 TUI）

    - **Print/SDK 模式**: 管道式非交互输入/输出

    - **MCP Server 模式**: 以 MCP 标准协议暴露 Claude 能力

---

## 三、Agentic Loop — 核心查询引擎

### 3\.1 查询循环 \(query\.ts\)

`src/query.ts`（1,730 行）是 Claude Code 的"大脑"，实现了 Agentic Loop：

> **🔑 核心机制**：Agentic Loop 的本质是一个**工具调用驱动的循环** — 模型持续接收用户输入和工具结果，直到模型认为任务完成、不再调用工具时才终止循环。

### 3\.2 QueryEngine \(QueryEngine\.ts\)

`src/QueryEngine.ts`（1,308 行）封装了与 Claude API 的交互：

- **流式 SSE 响应解析** — 实时接收并处理 Server\-Sent Events

- **重试与限流处理** — 指数退避 \+ 速率限制感知

- **Token 计量与成本追踪** — 精确统计每轮对话消耗

- **Extended Thinking 支持** — 深度推理模式

- **多模型路由** — 1P / Foundry / Bedrock / Vertex 四种后端

---

## 四、工具系统 \(Tools\)

### 4\.1 Tool 基类接口

每个工具遵循统一的 `Tool` 接口（`src/Tool.ts`，793 行），核心方法：

|方法|用途|
|---|---|
|`call()`|工具执行逻辑|
|`checkPermissions()`|权限检查|
|`validateInput()`|输入校验|
|`prompt()`|生成系统提示中该工具的描述|
|`renderToolUseMessage()`|渲染工具使用界面|
|`renderToolResultMessage()`|渲染工具执行结果|
|`isConcurrencySafe()`|是否支持并发|
|`isReadOnly()` / `isDestructive()`|操作类型标记|
|`maxResultSizeChars`|结果大小限制|

### 4\.2 42 个内建工具分类总览

### 4\.3 工具注册机制

`tools.ts` 是工具注册表，负责：

4. 收集所有基础工具 `getAllBaseTools()`

5. 按照环境变量和 feature flag 条件加载

6. 合并 MCP 工具 `assembleToolPool()`

7. 按权限过滤 `filterToolsByDenyRules()`

8. 工具搜索优化（ToolSearch 延迟加载方案）

---

## 五、UI、状态与命令系统

### 5\.1 TUI 渲染层

基于 **React Ink**（完整 fork \+ 自定义终端渲染），核心组件：

|类别|组件|规模|说明|
|---|---|---|---|
|🎨 UI|`ScrollKeybindingHandler`|149KB|滚动交互与快捷键|
|🎨 UI|`Messages`|147KB|消息列表渲染|
|🎨 UI|`VirtualMessageList`|149KB|虚拟滚动优化|
|🎨 UI|`LogSelector`|200KB|日志选择器|
|🎨 UI|`Spinner`|—|含 ultrathink 彩虹效果 🌈|
|🪝 Hook|`useTypeahead`|213KB|智能补全，项目最大 Hook|
|🪝 Hook|`useReplBridge`|116KB|IDE↔REPL 双向通信桥|
|🪝 Hook|`useVoiceIntegration`|99KB|语音集成|
|🪝 Hook|`useCanUseTool`|40KB|权限检查|

### 5\.2 状态管理

`src/state/` 使用 **Zustand** 作为全局状态管理。

### 5\.3 斜杠命令

`commands.ts`（755 行）注册了斜杠命令：

|分类|命令|
|---|---|
|**会话管理**|`/clear` · `/compact` · `/resume` · `/continue`|
|**模式切换**|`/plan` · `/auto` · `/vim`|
|**配置**|`/config` · `/model` · `/theme` · `/effort`|
|**调试**|`/debug` · `/doctor` · `/stats`|
|**Agent**|`/task` · `/team`|
|**导出**|`/export` · `/transcript`|
|**记忆**|`/memory`|

---

## 六、权限与安全

### 6\.1 权限系统架构

`src/utils/permissions/`（24 个文件 / 9,413 行）实现了多层安全模型：

**三种持久化目标**：

|范围|存储位置|生效范围|
|---|---|---|
|`session`|内存|仅当前会话|
|`user`|`~/.claude/settings.json`|用户全局|
|`project`|`.claude/settings.json`|项目级别|

### 6\.2 Bash 安全分析

`BashTool/` 包含 20 个文件，实现了细粒度的命令安全分析：

> \*\***🛡️ Bash 安全防线**

|文件|职责|
|---|---|
|`commandSemantics.ts`|命令语义分析（只读 vs 写入 vs 危险）|
|`bashSecurity.ts`|安全策略执行|
|`bashPermissions.ts`|权限检查|
|`destructiveCommandWarning.ts`|危险命令告警|
|`sedValidation.ts` / `sedEditParser.ts`|sed 命令解析与验证|
|`pathValidation.ts`|路径安全检查|
|`yoloClassifier.ts`|Auto Mode 下的 AI 分类器决策|

---

## 七、上下文与记忆管理

### 7\.1 记忆系统总览

### 7\.2 AutoCompact — 自动压缩引擎

**核心文件**: `src/services/compact/autoCompact.ts`（352 行）

> **⚠️ 熔断机制**：连续失败 3 次后停止自动压缩。BQ 分析发现全球每天浪费约 **25 万次** API 调用。

- 上下文管理的**第一道防线**，阈值检测自动触发对话压缩

- **触发守卫**: `session_memory`、`compact`、`marble_origami` 不触发自动压缩以避免死锁

### 7\.3 CompactConversation — 压缩核心

**核心文件**: `src/services/compact/compact.ts`（1,706 行 / 60KB）

Post\-Compact 恢复策略：

- 最近 5 个文件（总预算 50K tokens，单文件 5K）

- Skill 恢复预算 25K tokens

### 7\.4 Session Memory — 渐进式记忆提取

**核心文件**: `src/services/SessionMemory/sessionMemory.ts`（495 行）

> **🧠 工作原理**：不替换对话历史，而是维护持续更新的 Markdown 笔记。通过 `runForkedAgent()` 创建隔离子 Agent，仅允许 `FileEditTool` 操作 session memory 文件。

**双阈值触发**：Token \+ 工具调用阈值同时满足，或 Token 满足 \+ 最后 turn 无工具调用。

### 7\.5 CLAUDE\.md 记忆系统

核心实现 `src/utils/claudemd.ts`（1,479 行），四层优先级：

|优先级|层级|说明|
|---|---|---|
|🔴 最高|Managed|企业/组织管理配置|
|🟠 高|User|用户个人配置 `~/.claude/CLAUDE.md`|
|🟡 中|Project|项目根目录 `.claude/CLAUDE.md`|
|🟢 近|Local|当前目录向上逐层遍历，越近优先级越高|

> \*\***✨ 高级特性**

- `@include` 支持 `@./relative`、`@~/home`、`@/absolute` 三种路径（最大递归 5 层防循环）

- Frontmatter `paths:` 字段实现上下文敏感的指令注入

- 自动剥离 HTML 注释 \+ `claudeMdExcludes` 路径排除

---

## 八、运行时基础设施

### 8\.1 Hooks 生命周期系统

核心实现 `src/utils/hooks.ts`（5,023 行 / 159KB），项目第三大文件。

支持 `asyncRewake` 模式 — 后台运行，exit code 2 时通过消息队列唤醒模型。

### 8\.2 会话持久化

核心实现 `src/utils/sessionStorage.ts`（5,106 行 / 180KB），项目第二大文件。

> \*\***💾 存储策略**

- 每条消息序列化为一行 JSON 追加写入 `.jsonl`

- `enqueueWrite()` 入队 \+ `drainWriteQueue()` 每 100ms 批量刷新（上限 100MB）

- 元数据在 compaction 和退出时追加到文件末尾

- `readLiteMetadata()` 仅读尾部 64KB，快速恢复会话元信息

- 子 Agent 独立存储在 `subagents/agent-id.jsonl`

- `compact-boundary` 标记实现增量恢复

- 50MB 以上直接 bail out 防 OOM

### 8\.3 消息系统

`src/utils/messages.ts`（5,513 行 / 193KB），全项目**最大文件**。

五种消息类型：

|类型|说明|
|---|---|
|`UserMessage`|用户输入|
|`AssistantMessage`|AI 响应 \+ usage|
|`AttachmentMessage`|附件 \+ Hook 结果|
|`SystemMessage`|系统事件|
|`ProgressMessage`|纯 UI 进度（不持久化）|

### 8\.4 配置系统

五层级联覆盖：**Enterprise → Organization → User → Project → Session**

- `permissionRuleParser.ts` 解析 `Bash(npm test)` 格式（工具名 \+ 参数 glob）

- 旧版工具名自动映射新名称

- 支持远程配置拉取 \+ 多设备同步 \+ `ConfigChange` Hook 变更通知

---

---

## 十、辅助系统

## 九、Agent 系统 — 多 Agent 智能体架构（深度解析）

这是整个架构中**最复杂、最精巧**的子系统，实现了从单个子 Agent 到多 Agent 团队协作的完整谱系。核心设计围绕三个目标：**Prompt Cache 复用**、**上下文隔离**、**权限安全**。

### 9\.1 AgentTool 目录结构

```Plain Text
src/tools/AgentTool/
├── AgentTool.tsx             (157.6 KB)  主入口 + runAgent 逻辑
├── runAgent.ts               (2.1 KB)    运行时构建
├── forkSubagent.ts           (6.1 KB)    Fork 子消息构建
├── forkedAgent.ts            底层执行器（Prompt Cache 复用核心）
├── agentMemory.ts            (5.4 KB)    持久记忆系统
├── agentMemorySnapshot.ts    记忆快照（团队共享）
├── agentColorManager.ts      Agent 终端颜色
├── agentDisplay.ts           UI 展示辅助
├── agentToolUtils.ts         工具过滤/解析
├── loadAgentsDir.ts          (39 KB)     Agent 定义解析
├── resumeAgent.ts            后台 Agent 恢复
├── prompt.ts                 (9.2 KB)    Agent 选择 UI
├── constants.ts              工具名、one-shot 列表
├── builtInAgents.ts          内建 Agent 注册
└── built-in/
    ├── generalPurposeAgent.ts
    ├── exploreAgent.ts        (3.4 KB)
    ├── planAgent.ts           (3.2 KB)
    ├── verificationAgent.ts
    ├── claudeCodeGuideAgent.ts
    └── statuslineSetup.ts

```

### 9\.2 Agent 定义与类型体系

Agent 定义由三种来源组成：

|来源|路径|可修改|
|---|---|---|
|**Built\-in**|`src/tools/AgentTool/built-in/`|❌|
|**Custom**|`.claude/agents/*.md`|✅|
|**Plugin**|`plugins/*/agents/*.md`|✅|

**自定义 Agent Markdown 文件格式**

```YAML
---
name: MyAgent
description: What this agent does, when to use it
model: inherit
tools:
  - Read
  - Bash
  - Glob
disallowedTools:
  - Agent
memory: project
isolation: worktree
maxTurns: 50
effort: 3
permissionMode: bubble
skills:
  - /commit
  - /verify
color: cyan
background: true
initialPrompt: |
  /reload-plugins
  Then, do X
hooks:
  SessionStart:
    - type: webfetch
      url: https://...
---

# System Prompt Markdown

This is the agent's full system prompt...

```

**Frontmatter 完整字段参考**

|字段|类型|说明|
|---|---|---|
|`name`|string|Agent 类型名（必填）|
|`description`|string|何时使用此 Agent（必填）|
|`tools`|string\[\]|工具白名单，`['*']` 表示全部|
|`disallowedTools`|string\[\]|工具黑名单|
|`model`|string|模型覆盖，`inherit` = 继承父级|
|`permissionMode`|enum|`default` / `plan` / `auto` / `bypass` / `bubble`|
|`maxTurns`|number|最大 agentic turn 数|
|`isolation`|enum|`worktree`（Git 隔离）/ `remote`（远程环境）|
|`memory`|enum|`user` / `project` / `local`|
|`skills`|string\[\]|预加载的 Skill|
|`mcpServers`|array|Agent 专属 MCP 服务器|
|`hooks`|object|会话级 Hook 配置|
|`color`|string|终端显示颜色|
|`background`|boolean|始终作为后台任务运行|
|`initialPrompt`|string|首轮前置 Prompt|
|`effort`|enum|推理深度级别|
|`omitClaudeMd`|boolean|省略 CLAUDE\.md（节省 Token）|
|`criticalSystemReminder_EXPERIMENTAL`|string|每轮重新注入的提醒|

### 9\.3 六个内建 Agent 详解

|Agent|工具集|模型|省略项|核心行为|
|---|---|---|---|---|
|`GeneralPurpose`|`['*']` 全量|动态选择|无|通用默认，完成后返回简洁报告|
|`Explore`|Glob/Grep/Read/Bash\(只读\)|外部用 Haiku，内部 inherit|CLAUDE\.md \+ gitStatus|只读搜索，省 5\-15 Gtok/周|
|`Plan`|同 Explore|inherit|CLAUDE\.md \+ gitStatus|只读规划，输出必须含"关键文件"段|
|`ClaudeCodeGuide`|WebFetch/WebSearch/Read/Glob/Grep|inherit|—|使用指南查询|
|`Verification`|Feature Flag 门控|inherit|—|对抗性验证检查|
|`StatuslineSetup`|Read/Edit|inherit|—|状态栏配置专用|

**One\-Shot Agent 优化**：Explore 和 Plan 被标记为 one\-shot，运行一次即返回，不支持 SendMessage 继续。每次省略 \~135 字符的 agentId/SendMessage 尾部注入，按每周约 3400 万次 Explore 调用计算，节省可观 Token。

**Explore Agent 核心 Prompt**（摘要）：

```Plain Text
You are a file search specialist...
=== CRITICAL: READ-ONLY MODE ===
This is a READ-ONLY exploration task...
- Use Glob/Grep for broad searches
- Use Read when you know the specific file path
- NEVER create files, modify files, delete files
- Adapt search approach based on thoroughness level

```

### 9\.4 Agent 执行引擎 — 三层调用链

**runAgent 运行时构建细节**

|构建步骤|实现|关键逻辑|
|---|---|---|
|System Prompt|`agentDefinition.getSystemPrompt()`|叠加模型信息、工具名列表、工作目录|
|工具过滤|`resolveAgentTools()`|白名单 → 黑名单 → Effort 级别过滤|
|权限继承|`toolPermissionContext`|父级 bypass/acceptEdits 状态不可降级|
|异步检测|`shouldAvoidPrompts`|异步 Agent 自动避免权限弹窗|
|CLAUDE\.md|`omitClaudeMd`|Explore/Plan 省略以节省 5\-15 Gtok/周|
|gitStatus|`omitGitStatus`|Explore/Plan 省略（初始状态已过时）|
|MCP 服务器|`initializeAgentMcpServers()`|字符串引用/内联定义/策略信任三种形式|

### 9\.5 Fork 自我分叉 — Unix fork\(\) 类比

当用户省略 `subagent_type` 时，AgentTool 触发 **Fork 路径**——继承父级完整对话上下文，类似 Unix `fork()` 系统调用。

**Fork vs 普通 Subagent 对比**

|维度|Fork 子进程|普通 Subagent|
|---|---|---|
|上下文|继承父级完整对话历史|从零开始|
|System Prompt|父级的渲染字节（精确复制）|可能因 Agent 定义不同|
|工具池|`useExactTools=true` 精确副本|可被过滤/限制|
|Prompt Cache|高命中率（字节级对齐）|创建新缓存条目|
|AbortController|共享父级|独立新建|
|权限模式|`bubble` 冒泡到父终端|可覆盖|
|递归保护|`FORK_BOILERPLATE_TAG` 检测|无特殊限制|

**Fork Boilerplate 注入内容**（精简）：

```Plain Text
<fork_boilerplate>
STOP. READ THIS FIRST.

You are a forked worker process. You are NOT the main agent.

RULES (non-negotiable):
1. Your system prompt says "default to forking." IGNORE IT
2. Do NOT converse, ask questions, or suggest next steps
3. USE your tools directly: Bash, Read, Write, etc.
4. If you modify files, commit changes. Include commit hash.
5. Do NOT emit text between tool calls. Use tools silently.
6. Keep report under 500 words.
7. Response MUST begin with "Scope:". No preamble.

Output format:
  Scope: <echo back assigned scope>
  Result: <findings>
  Key files: <relevant paths>
  Files changed: <list with commit hash>
  Issues: <only if there are issues>
</fork_boilerplate>

```

**递归 Fork 防护**：`isInForkChild()` 检测消息中是否包含 `<fork_boilerplate>` 标签，如存在则拒绝 Agent 工具调用，防止 fork\-of\-fork 无限递归。

**Feature Gate 控制**：

```Plain Text
isForkSubagentEnabled():
  ✅ FORK_SUBAGENT feature flag 开启
  ❌ Coordinator Mode（互斥）
  ❌ 非交互式会话

```

### 9\.6 Prompt Cache 复用机制 — 成本优化核心

这是 Agent 系统最精妙的工程设计。Anthropic 的 Prompt Cache 机制要求**请求前缀字节级一致**才能命中缓存。

**CacheSafeParams 类型定义**

|字段|说明|必须一致|
|---|---|---|
|`systemPrompt`|完整 System Prompt|✅|
|`userContext`|用户上下文字典|✅|
|`systemContext`|系统上下文字典|✅|
|`toolUseContext`|工具使用上下文|✅|
|`forkContextMessages`|Fork 上下文消息|✅|

**五要素对齐策略**

**消息对齐的关键技巧**：所有并行 Fork 子进程的 `tool_result` 使用**完全相同的占位符文本**：

```Plain Text
"Fork started — processing in background"

```

这确保多个并行 Fork 的消息前缀**字节级一致**，只有最末尾的 directive 文本不同，最大化 Cache 命中率。

**Token 计费与缓存效果**

|Token 类型|说明|相对价格|
|---|---|---|
|`input_tokens`|新输入|1x|
|`cache_creation_input_tokens`|首次写入缓存|1\.25x|
|`cache_read_input_tokens`|缓存命中|**0\.1x**|
|`output_tokens`|输出|1x|

缓存命中率计算：`hitRate = cache_read / (input + creation + read)`

### 9\.7 Agent 间通信 — SendMessage 工具

**消息路由机制**

**结构化控制消息**

|消息类型|方向|用途|
|---|---|---|
|`shutdown_request`|Lead → Teammate|请求关闭|
|`shutdown_response`|Teammate → Lead|关闭确认/拒绝|
|`plan_approval_response`|Lead → Teammate|计划审批，可继承权限模式|

### 9\.8 Coordinator 模式 — 最高级编排

通过 `CLAUDE_CODE_COORDINATOR_MODE=1` 启用，是 Agent 系统的最高级编排模式。

**Task\-Notification XML 格式**

```XML
<task-notification>
  <task-id>{agentId}</task-id>
  <status>completed|failed|killed</status>
  <summary>{状态摘要}</summary>
  <result>{Agent 最终文本响应}</result>
  <usage>
    <total_tokens>N</total_tokens>
    <tool_uses>N</tool_uses>
    <duration_ms>N</duration_ms>
  </usage>
</task-notification>

```

**Coordinator 核心规则**

- **并行是超能力**：只读任务自由并行，写入任务同文件串行

- **永不委派理解**：Coordinator 必须理解 Worker 结果后再指导下一步

- **Scratchpad 共享**：`tengu_scratch` 启用时，Worker 可读写临时目录共享知识

- **Worker 工具集**：排除 TeamCreate/TeamDelete/SendMessage/SyntheticOutput（内部工具）

### 9\.9 Teammate 系统 — 团队协作

**两种 Teammate 实现**

|维度|Tmux Teammate|In\-Process Teammate|
|---|---|---|
|进程模型|独立 CLI 进程|同进程 AsyncLocalStorage 隔离|
|通信|文件系统 Mailbox|共享内存 \+ 消息队列|
|环境变量|`CLAUDE_CODE_AGENT_ID` 等|AsyncLocalStorage Context|
|用户可见性|独立 Tmux 面板|同一终端内管理|
|适用场景|人类可观察的并行工作|高效后台并行|

**角色分工**

- **Team Lead**：拥有协调权，可审批计划、发送关闭请求、继承权限模式

- **Teammate**：工作 Agent，执行具体任务，通过 Mailbox 接收指令

- **空闲检测**：`waitForTeammatesToBecomeIdle()` 等待所有队友空闲后再做全局决策

**Tmux 环境变量**

```Plain Text
CLAUDE_CODE_AGENT_ID=<agentId>
CLAUDE_CODE_AGENT_NAME=<agentName>
CLAUDE_CODE_TEAM_NAME=<teamName>
CLAUDE_CODE_AGENT_COLOR=<color>
CLAUDE_CODE_PLAN_MODE_REQUIRED=<boolean>

```

### 9\.10 后台任务管理 — 9 种任务类型

|任务类型|说明|关键特性|
|---|---|---|
|`LocalAgentTask`|本地子 Agent|消息队列 \+ 驱逐策略|
|`InProcessTeammateTask`|进程内队友|AsyncLocalStorage 隔离|
|`LocalShellTask`|本地 Shell 命令|输出捕获|
|`LocalWorkflowTask`|工作流任务|多步骤编排|
|`LocalMainSessionTask`|主会话任务|跨会话恢复|
|`RemoteAgentTask`|远程 Agent|跨机器执行|
|`MonitorMcpTask`|MCP 监控|服务器健康检查|
|`DreamTask`|后台推理|长时间无人值守|

**任务驱逐策略**

```Plain Text
完成后等待：PANEL_GRACE_MS = 30 分钟
UI 持有中：  evictAfter = undefined（永不驱逐）
取消选中后：evictAfter = now + 30 分钟

```

**消息队列机制**

- `queuePendingMessage()` — 运行中的 Agent 收到消息时入队

- `drainPendingMessages()` — 在工具轮次边界批量排空

- Agent 停止后收到消息 → 自动从磁盘 transcript 恢复

### 9\.11 Agent 持久记忆

三种记忆范围：

|范围|存储路径|共享方式|适用场景|
|---|---|---|---|
|`user`|`~/.claude/agent-memory/{agent}/`|跨项目|通用偏好与学习|
|`project`|`{cwd}/.claude/agent-memory/{agent}/`|Git 版本控制|团队共享的项目知识|
|`local`|`{cwd}/.claude/agent-memory-local/{agent}/`|不入版本控制|本机特定配置|

每个 Agent 的记忆入口文件为 `MEMORY.md`。启用记忆后，系统自动注入 FileWrite/Edit/Read 工具，允许 Agent 自主更新记忆内容。

**记忆快照（project 范围）**：支持 `checkAgentMemorySnapshot()` 检测新版本，可选操作：`initialize`（首次复制）、`prompt-update`（提示用户更新）、`none`（已最新）。

### 9\.12 Worktree 隔离 — Git 工作树

**隔离流程**

**命名规范与安全**

|规则|值|
|---|---|
|Slug 最大长度|64 字符|
|允许字符|字母数字、`.`、`_`、`-`、`/`|
|分支命名|`worktree-{slug}`（`/` 替换为 `+`）|
|禁止|`.` / `..` 路径段（防遍历）|

**临时 Worktree 清理**：自动识别临时模式（`agent-a{7hex}`、`wf_{8hex}-{3hex}-{idx}` 等），只清理未提交变更的临时 worktree，用户命名的永不自动删除。

**Sparse Checkout 支持**：通过 `settings.worktree.sparsePaths` 配置，只检出必要目录，加速大仓库的 worktree 创建。

### 9\.13 Agent 系统总架构

### 10\.1 Thinking 与 Effort

**Thinking**（`thinking.ts`，163 行）：

|模式|说明|
|---|---|
|`adaptive`|自适应推理深度|
|`enabled`|固定预算推理|
|`disabled`|关闭推理|

> **🌈 Ultrathink**：关键词自动提升推理深度，UI 展示彩虹色动画效果。

**Effort**（`effort.ts`，330 行）：`low`（快速）→ `medium`（标准）→ `high`（全面）→ `max`（最深度，仅 Opus 4\.6）

优先级：`env CLAUDE_CODE_EFFORT_LEVEL → appState → model default`。`max` 发送到非 Opus 4\.6 时自动降级 `high`。

### 10\.2 Voice 语音系统

`src/services/voice.ts`（526 行），三级回退录音。统一参数 16000 Hz / 1 通道 / 16\-bit PCM。

### 10\.3 IDE 集成

> **🔗 三大集成能力**

### 10\.4 其他核心系统

|系统|文件|说明|
|---|---|---|
|**Tool Search**|`toolSearch.ts`（756 行）|MCP 工具延迟加载，按 token 占比自动启用|
|**Fast Mode**|`fastMode.ts`（532 行）|快速模式，同模型更快输出|
|**Worktree**|`worktree.ts`（1,520 行）|Git 工作树隔离，slug 限 50 字符，symlink 代替复制|
|**Feature Flags**|`feature()` 函数|构建时 DCE，30\+ Flag 控制功能梯度|

---

## 十一、架构总结

|维度|实现|
|---|---|
|**分层清晰**|入口 → 主程序 → Query 引擎 → 工具系统 → 服务层，各层职责明确|
|**性能优先**|快速路径、惰性导入、流式执行、并发工具、压缩策略|
|**安全纵深**|多层权限模型、路径验证、命令语义分析、Hook 信任检查|
|**高度可扩展**|Tools \+ Skills \+ Plugins \+ MCP \+ Hooks **五层扩展机制**|
|**渐进式复杂度**|Feature Flag 控制功能梯度，内外版本差异化构建|
|**持久化能力**|JSONL 会话存储、CLAUDE\.md 记忆系统、元数据尾部重写|
|**IDE 深度集成**|Teleport 传送门、补全缓存、REPL 桥接、选区感知|

> **📌 整个项目代码量超过 51 万行 TypeScript（1,930 个文件），是目前公开可见的最复杂的 AI Agent 客户端实现之一。**

---

## 附录 A：精华 Prompt 解析

> **📖 以下是从 Claude Code 源码中提取的关键 Prompt 片段，展示了 Anthropic 工程团队在 Prompt Engineering 方面的最佳实践。**

### A\.1 系统核心身份 Prompt

**来源**: `src/constants/prompts.ts` → `getSimpleIntroSection()`

```Plain Text
You are an interactive agent that helps users with software
engineering tasks. Use the instructions below and the tools
available to you to assist the user.

IMPORTANT: You must NEVER generate or guess URLs for the user
unless you are confident that the URLs are for helping the user
with programming. You may use URLs provided by the user in their
messages or local files.

```

> **💡 解读**：简洁明确的角色定义 \+ 安全护栏（禁止猜测 URL）。不过度描述能力，而是让工具系统自然展示。

### A\.2 代码风格黄金准则

**来源**: `src/constants/prompts.ts` → `codeStyleSubitems`

```Plain Text
• Don't add features, refactor code, or make "improvements" beyond
  what was asked.
• Don't add error handling, fallbacks, or validation for scenarios
  that can't happen.
• Don't create helpers, utilities, or abstractions for one-time
  operations. Three similar lines of code is better than a premature
  abstraction.
• Default to writing no comments. Only add one when the WHY is
  non-obvious.

```

> **💡 解读**：完美体现 YAGNI \+ KISS 原则。**"三行相似代码好过一个过早抽象"** 堪称编程箴言。

### A\.3 谨慎行动 Prompt（爆炸半径分析）

**来源**: `src/constants/prompts.ts` → `getActionsSection()`

```Plain Text
Carefully consider the reversibility and blast radius of actions.
The cost of pausing to confirm is low, while the cost of an unwanted
action (lost work, unintended messages sent, deleted branches) can
be very high.

When you encounter an obstacle, do not use destructive actions as a
shortcut to simply make it go away. Follow both the spirit and letter
of these instructions — measure twice, cut once.

```

> **💡 解读**：用"爆炸半径"分类操作风险。结合"暂停确认成本低 vs 错误操作成本高"的不对称风险分析。**"量两次，切一次"**。

### A\.4 Agent 委派 Prompt

**来源**: `src/tools/AgentTool/prompt.ts`

```Plain Text
Brief the agent like a smart colleague who just walked into the room
— it hasn't seen this conversation, doesn't know what you've tried,
doesn't understand why this task matters.

Never delegate understanding. Don't write "based on your findings,
fix the bug" or "based on the research, implement it."

```

> **💡 解读**：**"像对刚走进房间的聪明同事那样简报"** 精准定义了 Agent 间通信标准。**"永远不要委派理解"** 是哲学级洞察。

### A\.5 输出效率 Prompt

**来源**: `src/constants/prompts.ts` → `getOutputEfficiencySection()`

```Plain Text
When sending user-facing text, you're writing for a person, not
logging to a console.

Avoid semantic backtracking: structure each sentence so a person can
read it linearly, building up meaning without having to re-parse
what came before.

```

> **💡 解读**：**"为人而写，不是写控制台日志"**。对"语义回溯"的禁止尤其精妙——每句话线性阅读、逐步构建含义。

### A\.6 BashTool Git 安全协议

**来源**: `src/tools/BashTool/prompt.ts`

```Plain Text
Git Safety Protocol:
- NEVER update the git config
- NEVER run destructive git commands unless explicitly requested
- NEVER skip hooks (--no-verify, --no-gpg-sign)
- CRITICAL: Always create NEW commits rather than amending, unless
  explicitly requested. When a pre-commit hook fails, the commit
  did NOT happen — so --amend would modify the PREVIOUS commit,
  which may result in destroying work.

```

> **💡 解读**：对 `--amend` 的陷阱分析 — hook 失败后 amend 会修改上一个 commit — 工程经验级别的安全细节。

### A\.7 自主工作模式 Prompt

**来源**: `src/constants/prompts.ts` → `getProactiveSection()`

```Plain Text
A good colleague faced with ambiguity doesn't just stop — they
investigate, reduce risk, and build understanding.

## Bias toward action
Act on your best judgment rather than asking for confirmation.

## Terminal focus
- Unfocused: The user is away. Lean heavily into autonomous action.
- Focused: The user is watching. Be more collaborative.

```

> **💡 解读**：通过 `terminalFocus` 判断用户是否在屏幕前，动态调整自主程度 — 不在时大胆行动，在时协作沟通。

### A\.8 诚实报告准则

**来源**: `src/constants/prompts.ts` → `getSimpleDoingTasksSection()`

```Plain Text
Report outcomes faithfully: if tests fail, say so with the relevant
output; if you did not run a verification step, say that rather than
implying it succeeded.

Never claim "all tests pass" when output shows failures.
The goal is an accurate report, not a defensive one.

```

> **💡 解读**：解决 AI 两个顽疾 — 过度乐观和过度防御。**"目标是准确报告，不是防御性报告"**。

### A\.9 CLAUDE\.md 记忆注入 Prompt

**来源**: `src/utils/claudemd.ts`

```Plain Text
Codebase and user instructions are shown below. Be sure to adhere
to these instructions. IMPORTANT: These instructions OVERRIDE any
default behavior and you MUST follow them exactly as written.

```

> **💡 解读**：仅 29 个单词但效果极强。"OVERRIDE any default behavior" \+ "MUST follow them exactly" 确保用户自定义指令的优先级高于系统内建行为。

### A\.10 权限拒绝后的行为引导

**来源**: `src/utils/messages.ts` → `DENIAL_WORKAROUND_GUIDANCE`

```Plain Text
IMPORTANT: You *may* attempt to accomplish this action using other
tools that might naturally be used to accomplish this goal.
But you *should not* attempt to work around this denial in malicious
ways.

If you believe this capability is essential to complete the user's
request, STOP and explain to the user what you were trying to do
and why you need this permission.

```

> **💡 解读**：AI 安全典范 — 既不让模型完全放弃，也不给恶意钻空子的空间。最后 **"STOP and explain"** 把决策权交回用户。

### A\.11 Coordinator 并行超能力

**来源**: `src/coordinator/coordinatorMode.ts`

```Plain Text
Parallelism is your superpower. Workers are async. Launch independent
workers concurrently whenever possible — don't serialize work that
can run simultaneously.

When workers report research findings, you must understand them
before directing follow-up work. Never write "based on your findings"
or "based on the research."

```

> **💡 解读**：清晰的并发原则（读并行、写串行）\+ "永不委派理解"的强化。**协调者不能做传话筒。**

### A\.12 记忆纠正暗示

**来源**: `src/utils/messages.ts` → `MEMORY_CORRECTION_HINT`

```Plain Text
Note: The user's next message may contain a correction or preference.
Pay close attention — if they explain what went wrong or how they'd
prefer you to work, consider saving that to memory for future sessions.

```

> **💡 解读**：当用户拒绝操作后注入此暗示，使 AI 从"被拒绝"的体验中学习，将用户偏好存入 Memory — 实现**端到端自适应学习闭环**。

---

## 附录 B：依赖生态与技术栈分析

### B\.1 依赖全景

项目共有 **68 个生产依赖 \+ 8 个开发依赖 = 76 个依赖包**。

**依赖来源分布**

|类别|包数量|占比|核心包|
|---|---|---|---|
|Anthropic 自有|6|8\.8%|`@anthropic-ai/sdk`、`bedrock-sdk`、`vertex-sdk`、`foundry-sdk`、`mcpb`、`sandbox-runtime`|
|OpenTelemetry|6|8\.8%|`@opentelemetry/api`、`sdk-trace-base`、`exporter-trace-otlp-http` 等|
|React 生态|3|4\.4%|`react` v19\.1\.0、`react-reconciler` v0\.33\.0、`ink` \(自研 fork\)|
|VS Code 协议|2|2\.9%|`vscode-jsonrpc`、`vscode-languageserver-protocol`|
|安全相关|2|2\.9%|`xss` v1\.0\.15、`zod` v3\.25\.42|
|其他工具库|49|72\.1%|`lodash-es`、`chalk`、`marked`、`highlight.js`、`lru-cache` 等|

**多模型后端支持**

---

## 附录 C：性能优化深度分析

### C\.1 启动性能优化

Claude Code 对启动时间极度敏感，采用了多层优化策略：

**启动阶段 Checkpoint**

|阶段|Checkpoint 名称|优化手段|
|---|---|---|
|1\. 入口|`cli_entry`|快速路径短路（`--version` 毫秒级返回）|
|2\. 导入|`main_tsx_imports_loaded`|惰性 `dynamic import`，只加载必要模块|
|3\. 初始化|`init_function_start`|MDM 子进程 \+ Keychain 预取**并行执行**|
|4\. 就绪|`init_function_end`|Feature Flag 控制死代码消除|
|5\. 运行|`main_after_run`|采样上报（内部 100%，外部 0\.5%）|

**关键优化：并行预取**

```Plain Text
传统串行方式（~200ms）:
  MDM Read (plutil) ──────> Keychain OAuth ──────> Keychain API Key ──────> 就绪

优化后并行方式（~65ms）:
  MDM Read (plutil)    ─┐
  Keychain OAuth       ─┤──> 就绪
  Keychain API Key     ─┘

```

**性能度量基础设施**：`startupProfiler.ts`（195 行）在每个 checkpoint 记录 RSS/Heap 内存快照，通过 `CLAUDE_CODE_PROFILE_STARTUP=1` 输出详细报告。

### C\.2 缓存策略体系

`src/utils/memoize.ts`（270 行）实现了三种缓存模式：

|缓存模式|函数|特点|适用场景|
|---|---|---|---|
|**TTL 缓存**|`memoizeWithTTL()`|后台刷新，立即返回旧值|配置、远程数据|
|**TTL 异步**|`memoizeWithTTLAsync()`|并发去重，防 cold\-miss 风暴|API 调用、Token 刷新|
|**LRU 缓存**|`memoizeWithLRU()`|固定容量淘汰|文件状态、路径解析|

> 曾使用 lodash\.memoize 导致内存暴涨 300MB\+，切换到 LRU 后解决。

### C\.3 流式处理与异步生成器

项目大量使用 `AsyncGenerator` 模式（568 处），核心用于：

- **API 响应流式解析** — SSE 事件逐块处理，不等完整响应

- **重试心跳机制** — `HEARTBEAT_INTERVAL_MS = 30s` 防止宿主判定会话超时

- **工具结果流式返回** — Agent 同步模式下 `yield` 消息给父级

---

## 附录 D：错误处理与容错机制

### D\.1 错误类型层级

项目定义了 **20\+ 自定义错误类**，按领域分类：

|领域|错误类|说明|
|---|---|---|
|**重试**|`CannotRetryError`|包装原始错误 \+ 重试上下文|
|**降级**|`FallbackTriggeredError`|模型降级追踪|
|**任务**|`StopTaskError`|任务中断信号|
|**网络**|`BridgeFatalError`、`BridgeHeadlessPermanentError`|远程桥接故障|
|**安全**|`DomainBlockedError`、`EgressBlockedError`|出口流量拦截|
|**文件**|`MaxFileReadTokenExceededError`、`PathTraversalError`|文件读取保护|
|**媒体**|`ImageSizeError`|图片尺寸超限|

### D\.2 重试策略详解

`withRetry.ts`（823 行）实现了生产级重试引擎：

**退避公式**：`delay = BASE_DELAY_MS * 2^(attempt-1) + random(0, 0.25 * baseDelay)`

**持久重试模式**：无人值守场景下，最大退避 5 分钟，总超时 6 小时，期间每 30 秒发送心跳防止宿主杀进程。

---

## 附录 E：Prompt Cache 优化分析

### E\.1 缓存命中机制

Prompt Cache 是 Claude Code 最重要的成本优化手段。`promptCacheBreakDetection.ts`（260\+ 行）追踪所有可能导致缓存失效的因素：

|缓存失效因素|检测方式|影响|
|---|---|---|
|System Prompt 变化|Hash 比对|完全失效|
|工具定义变化|每个工具 Schema Hash|完全失效|
|模型切换|模型 ID 比对|完全失效|
|Fast Mode 切换|状态比对|完全失效|
|Effort 级别变化|值比对|完全失效|
|Cache Control 变化|scope/TTL Hash|部分失效|
|Beta Headers 变化|Header Hash|完全失效|

### E\.2 Fork Agent 缓存复用

子 Agent 的缓存复用是核心设计目标：

```Plain Text
父 Agent 请求前缀:
  [System Prompt] + [Tool Definitions] + [History Messages]
       ↓ 字节级一致
子 Agent 请求前缀:
  [继承 renderedSystemPrompt] + [useExactTools 精确复制] + [继承 thinkingConfig]
       ↓
  🎯 命中 Prompt Cache → 节省 80%+ 输入 Token 费用

```

**Token 计量体系**（`tokens.ts`）区分四类 Token：

|Token 类型|说明|计费|
|---|---|---|
|`input_tokens`|新输入 Token|全价|
|`cache_creation_input_tokens`|首次缓存创建|1\.25x|
|`cache_read_input_tokens`|缓存命中读取|0\.1x|
|`output_tokens`|模型输出|全价|

---

## 附录 F：设计模式与工程实践

### F\.1 核心设计模式

### F\.2 代码规模统计

|指标|数值|
|---|---|
|`.ts` 文件数|1,389|
|`.tsx` 文件数|552|
|总文件数|1,941|
|`.ts` 代码行数|380,428|
|`.tsx` 代码行数|132,975|
|**总代码行数**|**513,403**|

**Top 6 最大文件**

|排名|文件|行数|职责|
|---|---|---|---|
|1|`cli/print.ts`|5,595|CLI 输出格式化|
|2|`utils/messages.ts`|5,513|消息规范化/转换|
|3|`utils/sessionStorage.ts`|5,106|会话持久化|
|4|`utils/hooks.ts`|5,023|React Hooks 库|
|5|`screens/REPL.tsx`|5,006|主 REPL 交互界面|
|6|`main.tsx`|4,692|入口 \+ CLI 配置|

### F\.3 安全纵深分析

**安全相关组件**

|组件|文件|说明|
|---|---|---|
|XSS 过滤|`xss` 库 v1\.0\.15|MCP IDP 登录输入清洗|
|Schema 校验|`zod` v3\.25\.42|所有外部输入严格校验|
|JWT 验证|`bridge/jwtUtils.ts`|Bridge 通信身份验证|
|mTLS|`utils/mtls.ts`|双向证书认证|
|安全存储|`utils/secureStorage/`|macOS Keychain 集成|
|sed 注入防护|`BashTool/sedValidation.ts`|正则转义验证|

### F\.4 可观测性体系

项目集成了完整的 **OpenTelemetry** 可观测性基础设施：

|维度|实现|说明|
|---|---|---|
|**Tracing**|`@opentelemetry/sdk-trace-base`|分布式追踪|
|**Exporter**|`@opentelemetry/exporter-trace-otlp-http`|OTLP HTTP 导出|
|**Resource**|`@opentelemetry/resources`|资源标识|
|**Analytics**|`@growthbook/growthbook`|Feature Flag \+ A/B 实验|
|**Startup**|`startupProfiler.ts`|启动性能采样（内部 100%，外部 0\.5%）|
|**Cost**|`cost-tracker.ts`|Token 用量 \+ API 成本追踪|

### F\.5 测试策略

> 源码中**未包含测试目录**，测试在 Anthropic 内部 CI 基础设施中运行。但项目内建了一个有趣的替代方案：`verificationAgent.ts` — 一个**对抗性验证 Agent**，可以自主检查代码修改的正确性，相当于 AI 驱动的集成测试。

---

## 附录 G：扩展机制全景

### G\.1 五层扩展架构

|扩展层|定义方式|能力边界|适用场景|
|---|---|---|---|
|**Tools**|TypeScript 代码|完全控制，文件/Shell/网络|核心功能扩展|
|**Skills**|Markdown \+ Frontmatter|Prompt 注入 \+ 工具编排|工作流模板（/commit、/review）|
|**Plugins**|npm 包 \+ manifest|自定义 Agent \+ Skill \+ 配置|团队/社区共享|
|**MCP**|JSON\-RPC 协议|工具/资源/Prompt 动态注册|外部系统集成（飞书、Slack）|
|**Hooks**|Shell 脚本|事件拦截/修改/阻止|企业合规、自动化流水线|

