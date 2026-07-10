# Claude Code 源码全解析（书籍版）

> 本文档对 Claude Code 泄露源码（\~1,900 文件，512,000\+ 行 TypeScript）进行逐模块代码级分析，目标是让读者可以直接接手开发。

## 第一章：项目概览与架构哲学

### 1\.1 项目背景

Claude Code 是 Anthropic 的官方终端 AI 编程助手，2026\-03\-31 因 npm registry `.map` 文件泄露源码。技术栈：TypeScript \+ Bun 运行时 \+ React/Ink 终端 UI。

**核心特点**：

- 不是简单的 ChatGPT 封装，而是一个完整的 **AI 软件工程师环境**

- 支持文件编辑、Shell 执行、代码搜索、Git 工作流的完整闭环

- 具有企业级的权限管控、多云支持、多智能体编排能力

### 1\.2 整体分层架构

**整体分层架构（从上至下，共 5 层）**

**① 入口层（main\.tsx）**

- Commander\.js CLI 解析

- bridge/ Remote Control（多会话远程控制）

- server/ Direct Connect（直连客户端协议）

**② 核心引擎层**

- `QueryEngine.ts`：对话状态机，全项目最大文件约 46K 行

- `query.ts → queryLoop`：while\(true\) 流式主循环

- `processUserInput`：用户输入预处理管道

**③ 工具/命令层（约 90 个模块）**

- `tools/`：40\+ 工具，包含 Bash / File / Web / Agent / MCP 等

- `commands/`：50\+ 斜杠命令，如 /commit /review /mcp

- `skills/`：Markdown 工作流插件

- `plugins/`：插件生态（Marketplace / Session / Built\-in）

**④ 服务层（130\+ 文件）**

- `services/api/claude.ts`：流式 API 调用核心

- `services/mcp/`：MCP 协议客户端

- `services/compact/`：三策略上下文压缩

- `services/extractMemories/`：记忆自动提取

- `services/lsp/`：Language Server Protocol 集成

- `services/oauth/`：OAuth 2\.0 PKCE 流程

- `services/analytics/`：GrowthBook 特性开关

**⑤ 状态与上下文层**

- `state/AppState`：全局状态，DeepImmutable Store

- `context.ts`：git 状态 \+ CLAUDE\.md 上下文组装

- `memdir/` \+ `SessionMemory`：持久记忆体系

### 1\.3 启动时序与性能优化

**关键设计**：在 ES 模块 `import` 链开始之前，先以副作用方式启动 IO\-bound 操作，利用 Node\.js 事件循环并行化。

```Plain Text
main.tsx 顶部（import 之前）:
  startMdmRawRead()       ← MDM 企业策略读取（macOS）
  startKeychainPrefetch() ← macOS Keychain 读取
  profileCheckpoint('main_tsx_entry')

模块加载期间:
  GrowthBook 异步初始化
  Bootstrap API 预连接

init() 阶段:
  enableConfigs()         ← 读取 GlobalConfig，Zod 验证
  applySafeConfigEnvVars()
  setupGracefulShutdown()
  ← 遥测注册延迟到 initializeTelemetryAfterTrust()

setup(cwd) 阶段:
  setCwd(cwd)             ← 所有代码的基准目录，必须最先设置
  captureHooksConfigSnapshot()  ← 必须在 setCwd 之后
  initializeFileChangedWatcher()
  ← 后台并行: sessionMemory / plugins / API prefetch / analytics

React/Ink 渲染启动

OTel/gRPC:
  首次需要时懒加载（约 400KB OTel + 约 700KB gRPC）

```

---

## 第二章：核心引擎——QueryEngine 与 queryLoop

### 2\.1 QueryEngine — 对话状态机

**文件**：`src/QueryEngine.ts`（约 46K 行，全项目最大文件）

**设计哲学**：一个 `QueryEngine` 实例 = 一个完整的对话会话。它持有所有跨 turn 的状态，并将每个用户 turn 包装为 `async function` 异步生成器（`submitMessage`）。

**类结构**：

```TypeScript
class QueryEngine {
  config: QueryEngineConfig; // 不可变配置
  mutableMessages: Message[]; // 跨 turn 持久化的对话历史
  abortController: AbortController;
  permissionDenials: SDKPermissionDenial[]; // SDK 汇报用
  totalUsage: NonNullableUsage; // 累计 token 用量
  readFileState: FileStateCache; // 文件读取缓存（用于判断 stale）
  discoveredSkillNames: Set<string>; // 本 turn Skill 发现（每 turn 清空）
  loadedNestedMemoryPaths: Set<string>; // 已加载嵌套记忆路径
}

```

**QueryEngineConfig 关键字段**：

|字段|说明|
|---|---|
|`cwd`|工作目录|
|`tools` / `commands`|可用工具和命令|
|`mcpClients`|MCP 服务连接|
|`canUseTool`|权限回调函数|
|`thinkingConfig`|`{type: 'adaptive'}` / `{type: 'enabled', budgetTokens}` / `{type: 'disabled'}`|
|`maxTurns` / `maxBudgetUsd` / `taskBudget`|多维终止条件|
|`jsonSchema`|结构化输出约束（`SyntheticOutputTool`）|
|`snipReplay`|HISTORY\_SNIP 回调（可替换整个 `mutableMessages`）|
|`agents`|可用的 Agent 定义（for AgentTool）|

**submitMessage\(\) 精确执行步骤**：

1. `discoveredSkillNames.clear()` — 清空本 turn 技能发现记录

2. 包装 `wrappedCanUseTool` — 在原 `canUseTool` 基础上追加拒绝记录到 `permissionDenials`

3. 决定 `initialThinkingConfig`：传入 `thinkingConfig` 优先；否则 `shouldEnableThinkingByDefault()` → `{type: 'adaptive'}` 或 `{type: 'disabled'}`

4. `fetchSystemPromptParts` — 组装 system prompt（git 状态 \+ CLAUDE\.md \+ 用户自定义）

5. 构建首次 `processUserInputContext`（含 `setMessages` 回调，允许斜杠命令修改历史）

6. `processUserInput()` — 解析斜杠命令、展开 `@` 引用、执行 UserPromptSubmit hooks

7. 构建第二次 `processUserInputContext`（no\-op `setMessages`，仅用于 query）

8. 更新 `toolPermissionContext.alwaysAllowRules.command`（从 `allowedTools` 覆写）

9. `for await (const message of query({...}))` — 进入主循环

10. 消息分发：按 `message.type` 处理：

- `assistant` / `user` / `progress`：push 到 `mutableMessages`，yield 给 SDK

- `stream_event`：仅在 `includePartialMessages` 时 yield

- `compact_boundary`：splice 旧消息（GC），yield SDK `compact_boundary` 事件

- `system/api_error`：yield SDK `api_retry` 事件

- `system/snip_replay`：可选替换整个 `mutableMessages`

11. USD 预算检查：每条消息后检查 `getTotalCost() >= maxBudgetUsd`

12. Final result：`error_max_budget_usd` / `success` / `error_during_execution`

### 2\.2 queryLoop — 流式主循环

**文件**：`src/query.ts`

**调用链**：`QueryEngine.submitMessage` → `query()` → `yield* queryLoop()` → `while(true)`

**单次迭代的 10 个步骤**（每次迭代 = 一个 assistant turn）：

```Plain Text
Step 1: applyToolResultBudget(messages)
        — 限制工具结果的 token 体积

Step 2: snipCompactIfNeeded(...)
        — HISTORY_SNIP feature：按规则丢弃旧消息段，yield compact_boundary

Step 3: microcompact(...)
        — 轻量级：将连续短 tool_result 合并为摘要消息

Step 4: autocompact(messagesForQuery, ...)
        — 阈值检测：tokenCount(messages) > contextWindow - 13000 - reservedOutput
        — 若触发：yield postCompactMessages，替换 messagesForQuery

Step 5: yield { type: 'stream_request_start' }
        — 通知上层即将发起 API 请求

Step 6: for await (msg of deps.callModel({messages, system, thinking, tools, ...}))
        — 流式调用 Anthropic API（详见第三章）
        — StreamingToolExecutor 在流式中提前执行工具

Step 7: runTools / streamingToolExecutor.getRemainingResults()
        — 执行所有 tool_use blocks（串行/并行，受权限控制）
        — 收集 toolResults

Step 8: handleStopHooks()
        — Stop/TaskComplete/TeammateIdle hooks
        — 可产生 shouldPreventContinuation

Step 9: TOKEN_BUDGET 检查
        — checkTokenBudget() → 若需要，continue with 一条 nudge meta 消息

Step 10: state = { messages: [...messagesForQuery, ...assistantMessages, ...toolResults], ... }
         — 进入下一轮

```

**State 对象**（每轮携带）：

```TypeScript
type State = {
  messages: Message[]
  toolUseContext: ToolUseContext
  autoCompactTracking: AutoCompactTracking
  turnCount: number
  maxOutputTokensRecoveryCount: number  // max_output_tokens 恢复计数（上限3）
  hasAttemptedReactiveCompact: boolean
  pendingToolUseSummary: unknown
  stopHookActive: boolean | undefined
  transition: { reason: 'next_turn' | 'token_budget_continuation' | string }
}

```

**七种错误恢复机制**：

|错误类型|恢复策略|
|---|---|
|模型 streaming fallback|Tombstone partial messages → 切换 `fallbackModel` → `stripSignatureBlocks`|
|`max_output_tokens`|Withhold 流中消息 → 一次性升级 64k → ≤3 次 meta user 消息 → 错误|
|Context overflow \(PTL\)|`contextCollapse.recoverFromOverflow` → `reactiveCompact.tryReactiveCompact` → 表面错误|
|`FallbackTriggeredError`|`continue`，使用 `fallbackModel`|
|Abort 中途|drain streaming executor → synthetic tool\_results → optional interruption 消息|
|Yank missing tool result|`yieldMissingToolResultBlocks` → synthetic error tool\_result|
|外层 `catch`|synthetic assistant API error → return `model_error`|

**Thinking（Extended Thinking）四大规则**（代码注释称为 "wizard rules"）：

13. 含 thinking/redacted\_thinking block 的消息必须在 `max_thinking_length > 0` 的 query 中发送

14. thinking block 不能是消息的最后一个 block

15. thinking blocks 必须在整个 assistant trajectory 中保留（含后续 tool\_result \+ 下一个 assistant）

16. 模型 fallback 时必须 `stripSignatureBlocks`（保护性 thinking 签名是模型绑定的，换模型会 400）

**五层 Token Budget 体系**：

|层次|文件|机制|
|---|---|---|
|工具结果大小|`query.ts`|`applyToolResultBudget`|
|对话 token 预算|`query/tokenBudget.ts`|`createBudgetTracker + checkTokenBudget → nudge`|
|自动压缩阈值|`services/compact/autoCompact.ts`|`contextWindow - 13000 - min(maxOutput, 20000)`|
|Task 预算|`query.ts`|`taskBudget.total + remaining`（跨压缩累计递减）|
|USD 预算|`QueryEngine.ts`|`maxBudgetUsd >= getTotalCost()`|

## 第三章：Anthropic API 调用层（claude\.ts）

### 3\.1 主要函数签名

**文件**：`src/services/api/claude.ts`

**公开接口**：`queryModelWithStreaming` / `queryModelWithoutStreaming`，内部均委托给私有的 `queryModel` async generator。

**Options 类型（核心请求参数）**：

```TypeScript
type Options = {
  model: string;
  getToolPermissionContext: () => Promise<ToolPermissionContext>;
  isNonInteractiveSession: boolean;
  fastMode?: boolean; // 快速模式（低延迟，额外费用）
  effortValue?: EffortValue; // 推理努力程度
  taskBudget?: { total: number; remaining?: number };
  maxOutputTokensOverride?: number;
  fallbackModel?: string;
  onStreamingFallback?: () => void;
  querySource: QuerySource; // 'repl' | 'sdk' | 'compact' | ...
  agents: AgentDefinition[];
  mcpTools: Tools;
  hasPendingMcpServers?: boolean;
  skipCacheWrite?: boolean; // 禁止写入 prompt cache
  agentId?: AgentId; // 仅子 agent 设置
  outputFormat?: BetaJSONOutputFormat;
  advisorModel?: string;
  fetchOverride?: ClientOptions["fetch"]; // 用于 dumpPrompts
  addNotification?: (notif: Notification) => void;
  queryTracking?: QueryChainTracking;
};

```

### 3\.2 请求构建管道

**paramsFromContext 构建流程**：

```Plain Text
1. normalizeModelStringForAPI(options.model)     ← 模型名标准化

2. thinking 参数决策:
   - modelSupportsAdaptiveThinking → { type: 'adaptive' }
   - 否则 → { type: 'enabled', budget_tokens: min(maxThinkingForModel, maxOutput-1) }
   - 注意：thinking 启用时 temperature 必须省略（API 默认 1）

3. Beta headers 列表构建（getAllModelBetas）:
   - REDACT_THINKING_BETA_HEADER（first-party + 非 showThinkingSummaries）
   - INTERLEAVED_THINKING_BETA_HEADER（非 disabled + 支持 ISP）
   - CONTEXT_MANAGEMENT_BETA_HEADER
   - FAST_MODE_BETA_HEADER（session stable，促进 cache 命中）
   - PROMPT_CACHING_SCOPE_BETA_HEADER

4. Prompt Cache 标记:
   - addCacheBreakpoints(messages, enablePromptCaching, ...)
   - 系统 prompt：buildSystemPromptBlocks（每段可设 cache_control）
   - cache_control: { type: 'ephemeral', ttl?: '1h', scope?: 'global' }
   - 1h TTL：gated by subscriber/ant + GrowthBook allowlist

5. Context management（API-side compaction）:
   getAPIContextManagement({ hasThinking, isRedactThinkingActive, clearAllThinking })

6. Output config（结构化输出、task budget）:
   taskBudget → output_config.task_budget = { total, remaining? }

7. Fast mode:
   speed: 'fast'（当 isFastMode + not cooldown）
   — beta header session-stable 但 speed 字段每请求动态，允许 cooldown 时不发

```

### 3\.3 流式响应处理（SSE 事件处理）

**7 种 SSE 事件类型与处理**：

|事件|处理行为|
|---|---|
|`message_start`|初始化 `partialMessage`，记录 TTFT，`updateUsage(EMPTY, message.usage)`|
|`content_block_start`|初始化 `contentBlocks[index]`：text→`{text:''}`, tool→`{input:''}`, thinking→`{thinking:'',signature:''}`|
|`content_block_delta`|追加 `text_delta` / `thinking_delta` / `signature_delta` / `input_json_delta`（工具输入 JSON 字符串）|
|`content_block_stop`|从 `partialMessage` \+ 单 block 构建 `AssistantMessage`，push \+ yield|
|`message_delta`|`updateUsage(current, delta.usage)`；mutate 最后 assistant 消息的 `usage` 和 `stop_reason`；调用 `addToTotalSessionCost`|
|`message_stop`|no\-op|

**重要细节**：`stop_reason` 和最终 `usage` 在 `message_delta` 到达（晚于 `content_block_stop`），因此代码对**已 yield 的最后消息进行就地 mutate**，确保 transcript 序列化时看到正确数据。

**双重 yield**：每个 SSE 事件既触发 `AssistantMessage` yield，又触发 `{ type: 'stream_event', event: part }` yield（供 UI 和诊断）。

**Idle 看门狗**（可选）：`CLAUDE_ENABLE_STREAM_WATCHDOG` \+ `CLAUDE_STREAM_IDLE_TIMEOUT_MS`（默认 90s），超时则 abort 流并触发 fallback。

### 3\.4 多云支持（client\.ts）

**getAnthropicClient 四分支**：

|条件|客户端|认证方式|
|---|---|---|
|`CLAUDE_CODE_USE_BEDROCK`|`AnthropicBedrock`|IAM（`refreshAndGetAwsCredentials`）或 `AWS_BEARER_TOKEN_BEDROCK`|
|`CLAUDE_CODE_USE_FOUNDRY`|`AnthropicFoundry`|API key 或 Azure AD `DefaultAzureCredential`|
|`CLAUDE_CODE_USE_VERTEX`|`AnthropicVertex`|`GoogleAuth`，`getVertexRegionForModel(model)`|
|else|`Anthropic`|API key 或 OAuth Bearer|

**共享配置**：`defaultHeaders`（`x-app`, `User-Agent`, session id, remote/container 标识）；`timeout: API_TIMEOUT_MS`（默认 600s）；可选 proxy fetch 包装；`x-client-request-id` 仅在 firstParty \+ firstParty base URL 时注入。

### 3\.5 重试策略（withRetry\.ts）

**withRetry async generator 签名**：

```TypeScript
withRetry<T>(
  getClient: () => Promise<Anthropic>,
  operation: (client, attempt, retryContext) => Promise<T>,
  options: RetryOptions
): AsyncGenerator<SystemAPIErrorMessage, T>

```

**重试决策矩阵**：

|错误|前台|后台|特殊处理|
|---|---|---|---|
|529 overloaded|≤3 次后尝试 Opus fallback|立即 `CannotRetryError`|多次 529 → `REPEATED_529_ERROR_MESSAGE`|
|429 rate limit|订阅者 \+ enterprise 重试|视情况|短 `Retry-After` → sleep；长/unknown → fast mode cooldown|
|401/403|OAuth refresh 后重试|同左|Bedrock 403, Vertex auth 失败各自处理|
|connection error|重试（可选关闭 keep\-alive）|同左|`ECONNRESET`, `EPIPE`|
|Fast mode 拒绝|不用 fast mode 重试|N/A|`handleFastModeRejectedByAPI`|

**Unattended 模式**（`CLAUDE_CODE_UNATTENDED_RETRY`）：ant 用户的长时间重试，分块 sleep 期间发送 heartbeat。

**默认最大重试次数**：10（`CLAUDE_CODE_MAX_RETRIES` 可覆盖）。

### 3\.6 Token 用量追踪

**updateUsage 的正确性保证**：streaming 中 `message_start` 带来的 input/cache 数值不会被后续 `message_delta` 的 0 值覆盖（只有 \> 0 才覆写）。

```TypeScript
// 输出 tokens 直接覆写（累积），输入 tokens 只有非零才覆写
input_tokens: partUsage.input_tokens > 0
  ? partUsage.input_tokens
  : usage.input_tokens;
output_tokens: partUsage.output_tokens ?? usage.output_tokens; // 直接覆写

```

**accumulateUsage**：跨多个 assistant turn 求和（用于 QueryEngine\.totalUsage）。

**快速成本计算**：`calculateUSDCost(resolvedModel, usage)` 在 `message_delta` 时调用，加到 `totalSessionCost`（`bootstrap/state.ts` 维护）。

### 3\.7 错误分类体系

**classifyAPIError**（analytics 用）：`aborted` / `api_timeout` / `repeated_529` / `rate_limit` / `server_overload` / `prompt_too_long` / `pdf_error` / `image_error` / `tool_mismatch` / `invalid_model` / `credit_balance_low` / `authentication_failed` / `bedrock_model_access` / `ssl_cert_error` / `connection_error` / `unknown` 等。

**getAssistantMessageFromError**（用户可见错误）：映射 HTTP 状态和 API error types 到用户友好文本，设置 `error` 字段（`rate_limit` / `invalid_request` / `authentication_failed` / `billing_error` / `unknown`）。

## 第四章：工具系统详解

### 4\.1 工具契约（Tool\.ts）

每个工具实现 `Tool<Input, Output>` 接口：

```TypeScript
interface Tool<Input, Output, P = unknown> {
  name: string;
  aliases?: string[];
  description: (ctx: ToolUseContext) => string;
  inputSchema: ZodSchema<Input>;
  inputJSONSchema?: JSONSchema; // MCP-style schema（补充 Zod）
  call(
    args: Input,
    ctx: ToolUseContext,
    canUseTool: CanUseToolFn,
    parentMessage: AssistantMessage,
    onProgress?: ProgressFn,
  ): Promise<ToolResult<Output>>;

  // 安全元数据
  isEnabled(ctx: ToolUseContext): boolean;
  isReadOnly(input: Input): boolean;
  isConcurrencySafe(input: Input): boolean;
  isDestructive?: (input: Input) => boolean;

  // 权限钩子
  checkPermissions?(input: Input, ctx: ToolUseContext): Promise<PermissionDecision>;
  requiresUserInteraction?: (input: Input) => boolean;

  // 执行特性
  interruptBehavior?: "none" | "ask" | "force";
  searchHint?: string; // 延迟工具发现的搜索提示
}

```

**ToolResult 结构**：

```TypeScript
type ToolResult<Output> = {
  data: Output;
  newMessages?: Message[]; // 工具可注入新消息到历史
  contextModifier?: ContextModifier; // 可修改 ToolUseContext
  mcpMeta?: MCPToolMeta;
};

```

### 4\.2 BashTool — Shell 执行引擎

**文件**：`src/tools/BashTool/BashTool.tsx`（约 1143 逻辑行）

**输入 Schema 设计**（注意 `_simulatedSedEdit` 被刻意从模型可见 schema 中剥离）：

```TypeScript
// 完整 schema（内部使用）
fullInputSchema = z.strictObject({
  command: z.string(),
  timeout: z.number().optional(),
  run_in_background: z.boolean().optional(),
  dangerouslyDisableSandbox: z.boolean().optional(),
  _simulatedSedEdit: z.object({ filePath, newContent }).optional(),
  // 不暴露给模型，防止绕过 sed 验证直接写文件
});
// 模型可见 schema = fullInputSchema.omit({ _simulatedSedEdit: true })

```

**执行流程**：

```Plain Text
call() → runShellCommand() [async generator]
  ↓
  exec(command, abortSignal, 'bash', {
    timeout: timeoutMs,
    onProgress: callback,
    preventCwdChanges: !isMainThread,   ← 子 agent 不能改父 cwd
    shouldUseSandbox: shouldUseSandbox(input),
    shouldAutoBackground
  })
  ↓
  Progress 轮询（PROGRESS_THRESHOLD_MS = 2s 后开始）:
    TaskOutput.startPolling(taskId)
    Promise.race(resultPromise, progressSignal)
    每次 onProgress 触发 → yield bash_progress 事件
      { snippet, fullOutput, elapsedSeconds, lineCount, byteCount, taskId, timeoutMs }

```

**超时与自动后台化**：到达 `timeoutMs` 时，若 `shouldAutoBackground`，调用 `startBackgrounding()` 而非失败。Kairos 模式：15s（`ASSISTANT_BLOCKING_BUDGET_MS`）后主线程命令自动后台化。

### 4\.3 Bash 安全检查层（三层防御）

**第一层：tree\-sitter AST 分析**（`utils/bash/ast.ts`）

```Plain Text
parseCommandRaw(command)  ← tree-sitter 解析
    ↓
parseForSecurityFromAst(command, root)
    ├── too-complex（unknown 节点类型）→ ask（fail-closed！）
    └── simple → checkSemantics(commands)
        ├── 剥离包装器（time/nohup/timeout/nice/stdbuf）
        │   └── timeout: unknown flag → 'too-complex'（fail-closed）
        ├── 检查危险命令名（eval, procfs, zsh builtins...）
        ├── 检查 newline+# 混淆（argv 中 \n+# 组合）
        └── ok: false → ask + reason

```

**第二层：传统正则安全检查**（`tools/BashTool/bashSecurity.ts`）

20\+ 个检查项：控制字符注入（ASCII \< 32）、Shell 引号 bug、Heredoc 提取、IFS 变量操纵、混淆手段（brace expansion）、`jq -e` 退出码伪装、重定向劫持。

**第三层：语义权限规则**（`tools/BashTool/bashPermissions.ts`）

```Plain Text
bashToolHasPermission(input, context):
  1. AST/传统安全检查（见上）
  2. checkEarlyExitDeny（从已有 deny rules 快速拒绝）
  3. getSandboxAutoAllowSetting → auto allow when sandbox + autoAllowBashIfSandboxed
  4. 精确/前缀/通配符命令规则匹配（alwaysAllowRules 中的 Bash 内容规则）
  5. GrowthBook BASH_CLASSIFIER → pendingClassifierCheck
  → 返回 { behavior: 'allow' | 'ask' | 'deny', reason?, pendingClassifierCheck? }

```

### 4\.4 FileEditTool — 字符串替换引擎

**核心算法**：

```Plain Text
findActualString(fileContent, searchString):
  1. 精确 includes() → 直接返回
  2. normalizeQuotes(search + file) → 在规范化 file 中找 index
     → 返回 fileContent.substring(index, index + searchString.length)
     （保留原始文件的字符，包括 curly/smart quotes）
  3. 返回 null（未找到）

```

**多处匹配保护**：`file.split(actualOldString).length - 1 > 1` 且 `!replace_all` → 返回 `ask`，提示模型使用 `replace_all` 或增加上下文以唯一定位。

**换行符处理**：文件内容用 `\r\n → \n` 规范化做匹配；`new_string === ''` 的删除：自动尝试匹配 `old_string + '\n'`；非 Markdown 文件：`normalizeFileEditInput` 剥离每行尾部空格。

**Stale 检查（读写一致性）**：要求 `readFileState` 中有该文件的完整读取记录（非 partial view）。若 mtime 比 cache 新 → 检查是否内容相同（Windows mtime 噪声 workaround）→ 若不同则拒绝编辑。

### 4\.5 FileReadTool — 多类型文件读取

**类型分支**：

|文件类型|处理方式|
|---|---|
|`.ipynb`|`readNotebook()` → JSON 序列化，token 预算检查|
|图片（png/jpg/gif/webp）|`readImageWithTokenBudget()` → 读字节 \+ 格式检测 \+ 自适应压缩/降采样 → `image` block|
|PDF|若指定 `pages`：`extractPDFPages()` → per\-page JPG → `image` blocks；否则 `readPDF()` \+ `document` block；超限时报错要求 pages 参数|
|文本|`readFileInRange()` \+ `maxSizeBytes` \+ `validateContentTokens`；可选 `file_unchanged` dedup stub|

**Binary 文件保护**：`hasBinaryExtension()` 拒绝读取，除非是 PDF / 图片白名单扩展。

**重复读取 dedup**（`tengu_read_dedup_killswitch` 可关闭）：同 range \+ 同 mtime → 返回 `file_unchanged` stub，节省 context tokens。

### 4\.6 AgentTool — 子 Agent 生命周期

**同步 vs 异步决策**：

```TypeScript
const shouldRunAsync =
  (run_in_background === true ||
    selectedAgent.background === true ||
    isCoordinator ||
    isForkSubagentEnabled() ||
    (feature("KAIROS") && appState.kairosEnabled) ||
    proactiveModule?.isProactiveActive()) &&
  !isBackgroundTasksDisabled;

```

**执行模式三分支**：

```Plain Text
isolation: undefined / 'worktree'
  → in-process: runAgent() in same runtime
    - sync: shareSetAppState: true（共享父 AppState 更新）
    - async: void runWithAgentContext(runAsyncAgentLifecycle(...))（不阻塞父 Agent）

isolation: 'worktree'
  → runWithCwdOverride(worktreePath, ...) 在 Git worktree 中运行

isolation: 'remote' (ant only)
  → CCR 远端执行 → return { status: 'remote_launched', sessionUrl }

```

**runAgent 上下文 fork 细节**：

- `forkContextMessages` → `filterIncompleteToolCalls` 过滤未完成调用

- `readFileState`：in\-process fork 时 clone 父 cache；新会话新建（`READ_FILE_STATE_CACHE_SIZE` 限制）

- `allowedTools` 覆盖 session allow rules（保留 `cliArg` 规则，来自 SDK `--allowedTools`）

**Teardown finally 块**（防止子 agent 僵尸进程）：MCP 清理、`clearSessionHooks`、`readFileState.clear()`、`killShellTasksForAgent`、`killMonitorMcpTasksForAgent`。

### 4\.7 GrepTool — ripgrep 集成

**ripgrep 路径解析**（`utils/ripgrep.ts`）：

```Plain Text
1. 系统 rg（防止 PATH 劫持：argv0: 'rg'）
2. Bun bundle 嵌入模式（process.execPath，argv0: 'rg'）
3. 预置 vendor binary（utils/vendor/ripgrep）

```

**参数构建**：`--hidden`；排除 `.git/.svn/...`；`--max-columns 500`；支持 `-U --multiline-dotall`；从 plugin cache 获取额外 ignore globs；`-i`（不区分大小写）、`-l`（files）、`-c`（count）、`-n`（行号）、`-B/-A/-C`（上下文行）。

**结果处理**：`files_with_matches`（默认）：stat 每个路径，按 **mtime 排序**（测试环境使用 filename 排序保证确定性），head\-limit/offset，路径相对化。

### 4\.8 WebFetchTool — 网页内容获取

**安全管道**：

```Plain Text
validateURL(url)
  → 长度检查、无 userinfo、hostname ≥2 labels

LRU Cache 查找（15min TTL，50MB 上限）

HTTP → HTTPS 升级

Domain blocklist 检查（可选）:
  GET https://api.anthropic.com/api/web/domain_info?domain=...
  5min 缓存"已允许"域名

getWithPermittedRedirects（手动跟随，严格跨域控制）:
  - maxRedirects: 0（不自动跟随）
  - isPermittedRedirect: 同协议/端口，hostname 同根或加/去 www
  - 跨 host 重定向 → 返回 redirect 对象，让模型重新调用
  - 最大 10 跳，60s 超时，10MB body 上限

响应处理:
  binary content-type → persistBinaryContent（路径在结果中）
  HTML → Turndown markdown 转换
  other → UTF-8 string

applyPromptToMarkdown（Haiku 模型压缩，≤100k 字符输入）

```

## 第五章：权限系统深度解析

### 5\.1 完整决策树（Phase A\-C）

**权限决策三阶段完整流程**

**Phase A：hasPermissionsToUseToolInner（静态规则）**

1. `getDenyRuleForTool` → 匹配则 **deny**

2. `getAskRuleForTool` → 匹配则 **ask**

3. `tool.checkPermissions()` → deny / ask / allow / passthrough

4. `requiresUserInteraction` / 内容级 ask rule / safetyCheck → ask（bypass 免疫）

5. `bypassPermissions?` / `plan+isBypassAvailable?` → 是则 **allow\(mode\)**

6. `toolAlwaysAllowedRule` → 匹配则 **allow\(rule\)**

7. 默认 → **ask\(default\)**

**Phase B：模式处理（hasPermissionsToUseTool wrapper）**

- ask 结果遇到 `dontAsk` 模式 → **deny\(dontAsk\)**（无 UI）

- ask 结果遇到 `auto` 模式 → AI 分类器流程（BashClassifier）

- ask 结果遇到 `shouldAvoidPermissionPrompts` → headless hooks

- 其他 → 进入 Phase C

**Phase C：交互路由（useCanUseTool\.tsx）**

- `awaitAutomatedChecksBeforeDialog`（coordinator）→ hooks 优先 → 分类器 → 对话

- swarm worker → 分类器（本地）→ mailbox 转发 leader → leader UI 决策

- interactive REPL → hooks \+ 分类器**并行 race** \+ UI 对话三路并行

### 5\.2 权限模式详解

|模式|Phase A 2a|其他行为|
|---|---|---|
|`default`|不 bypass|正常 ask → 用户提示|
|`plan`|若 `isBypassPermissionsModeAvailable=true` 则 bypass（历史遗留）|否则同 default|
|`bypassPermissions`|无条件 bypass（仍受 safety/interactive\-only 约束）|—|
|`acceptEdits`|—|auto 模式快速路径；`checkPermissions` 以此模式重试|
|`dontAsk`|—|ask → deny（无 UI）|
|`auto`|—|AI 分类器 \+ denial tracking \+ acceptEdits 快速路径|

### 5\.3 Always Allow 规则系统

**存储**：`ToolPermissionContext.alwaysAllowRules: ToolPermissionRulesBySource`

- 来源：`userSettings / projectSettings / localSettings / flagSettings / policySettings / cliArg / command / session`

- 规则语法：

    - `"Bash"` — 整个工具的 allow

    - `"Bash(git:*)"` — 特定命令内容的 allow（前缀/通配符匹配）

    - `"mcp__server"` — 整个 MCP server 的所有工具

    - `"mcp__server__tool"` — 特定 MCP 工具

- **Phase A 2b**：`toolAlwaysAllowedRule` 找到匹配规则 → `allow(rule)`

### 5\.4 PermissionRequest Hooks

**配置格式**（`schemas/hooks.ts`，Zod）：

```TypeScript
HooksSchema = z.partialRecord(z.enum(HOOK_EVENTS), z.array(
  z.object({
    matcher?: string,
    hooks: z.array(HookCommand)   // command | prompt | agent | http
  })
))

// PermissionRequest hook 输入
PermissionRequestHookInput = {
  hook_event_name: 'PermissionRequest',
  tool_name: string,
  tool_use_id: string,
  tool_input: Record<string, unknown>,
  permission_suggestions: PermissionUpdate[]
}

// Hook 可返回
{ decision: 'allow', updatedInput?, updatedPermissions? }
{ decision: 'deny', message?, interrupt?: boolean }

```

**执行**：`executePermissionRequestHooks` → async generator，逐步 yield `AggregatedHookResult`：

- `allow`：`handleHookAllow`（持久化 `updatedPermissions`，记录接受日志）

- `deny`：可选 `interrupt`（abort controller）→ `buildDeny(hook)`

### 5\.5 三场景权限路由差异

|场景|处理顺序|说明|
|---|---|---|
|Coordinator Agent|PermissionRequest Hooks 优先 → Bash 分类器 → 交互对话|Hooks 完全 await 完成后才进行分类器|
|Swarm Worker|Bash 分类器（本地）→ mailbox 转发给 Leader → Leader UI 决策|不在本地运行 Hooks，避免多 worker 并发提示|
|Interactive REPL|Hooks \+ 分类器 **并行 race** \+ UI 对话三路并行|快速响应：任何一路最先给出结论则采用|

## 第六章：MCP 协议系统

### 6\.1 Server 配置格式

**McpServerConfigSchema**（Zod 判别联合）：

|`type`|核心字段|Transport|
|---|---|---|
|`stdio`（或省略）|`command`, `args[]`, `env{}`|`StdioClientTransport`|
|`sse`|`url`, `headers`, `headersHelper`, `oauth{...}`|`SSEClientTransport` \+ `ClaudeAuthProvider`|
|`http`|同 sse|`StreamableHTTPClientTransport`|
|`ws`|`url`, `headers`, `headersHelper`|`WebSocketTransport`|
|`sse-ide` / `ws-ide`|`url`, `ideName`|IDE 专用（无 OAuth）|
|`sdk`|`name`|SDK 托管（host 端控制）|
|`claudeai-proxy`|`url`, `id`|Streamable HTTP \+ Claude\.ai OAuth|

**OAuth 字段**（SSE/HTTP）：`clientId`, `callbackPort`, `authServerMetadataUrl`（必须 https），`xaa`（跨应用访问 boolean）

### 6\.2 Config 合并优先级（从低到高）

```Plain Text
（最低）
plugin servers
    → user (~/.claude/settings.json mcpServers)
    → project approved (.claude/settings.json，经用户批准的条目)
    → local (.claude/settings.local.json)
（最高）

特殊覆盖：
  - Enterprise 模式（managed-mcp.json 存在）：完全覆盖上述所有
  - Claude.ai 连接器：Object.assign({}, dedupedClaudeAi, claudeCodeServers)
  - 重名去重：同内容（URL/command）的 plugin 被 manual 覆盖；plugin 内部 first-loaded wins

Policy 过滤（合并后统一应用）：
  - isMcpServerAllowedByPolicy：allowlist + denylist
  - allowManagedMcpServersOnly：只允许 managed server

```

### 6\.3 Transport 选择逻辑（connectToServer）

```Plain Text
type == 'sse':          SSEClientTransport + ClaudeAuthProvider
                        + step-up 403 检测（insufficient_scope → markStepUpPending）
type == 'http':         StreamableHTTPClientTransport + ClaudeAuthProvider
                        + session expiry 检测（HTTP 404 + JSON-RPC -32001）
type == 'ws':           WebSocketTransport（Bun/Node WS）
                        + session-ingress Authorization（JWT when applicable）
type == 'sse-ide':      SSEClientTransport（proxy-aware fetch，无 OAuth）
type == 'ws-ide':       WebSocketTransport + X-Claude-Code-Ide-Authorization
type == 'claudeai-proxy': StreamableHTTP + createClaudeAiProxyFetch（Claude.ai OAuth）
type == stdio/null:
  特殊 in-process：Chrome / ComputerUse feature → InProcessTransport linked pair
  普通：StdioClientTransport（subprocessEnv + CLAUDE_CODE_SHELL_PREFIX）

```

### 6\.4 连接生命周期

**连接缓存**：`memoize(connectToServer, getServerCacheKey(name, json(config)))`

**工具发现**：

17. `capabilities?.tools` → `tools/list` JSON\-RPC

18. 工具名标准化：`buildMcpToolName` → `mcp__<server>__<tool>`（`normalizeNameForMCP`：替换 `[^a-zA-Z0-9_-]` → `_`）

19. IDE 工具白名单过滤：仅 `mcp__ide__executeCode` \+ `mcp__ide__getDiagnostics`

20. 动态刷新：`tools/listChanged` 事件 → 清缓存 \+ 重取

**重连退避**：最多 5 次，`min(1000 * 2^(attempt-1), 30000)` ms

**Cleanup（stdio 子进程三阶段终止）**：SIGINT → SIGTERM（等待 N ms）→ SIGKILL（强制终止）

**无主动 health ping**：依赖 transport error / session expiry / close 事件。

### 6\.5 MCP 权限设计

MCP 工具的 `checkPermissions()` 返回 `behavior: 'passthrough'`，附带 `fullyQualifiedName` 的建议 allow rule。实际权限决策由全局 `hasPermissionsToUseTool` 处理，与内置工具一致——MCP 工具不享有特权，也不被歧视。

### 6\.6 MCP OAuth 流程（ClaudeAuthProvider）

21. `discoverAuthorizationServerMetadata` → RFC 9728 / 8414 / legacy 路径三级 fallback

22. PKCE 公开客户端，支持 DCR 或预配置 `oauth.clientId`

23. Token 持久化：per\-server 安全存储 key（`getSecureStorage()`）

24. `403 insufficient_scope` → `markStepUpPending` → UI 触发重新授权

25. `UnauthorizedError` → `handleRemoteAuthFailure` → `needs-auth` client \+ 15min 缓存

---

## 第七章：上下文与记忆体系

### 7\.1 Context 组装（context\.ts）

**两类上下文**（均 memoized，`BREAK_CACHE_COMMAND` 触发失效）：

**系统上下文**（`getSystemContext`）：

- `getGitStatus()`：并行执行 `git status`, `git log --oneline -10`, `git branch`, `git config user.name/email`

- 截断保护：过长的 status 截取到最大字符数

- 跳过条件：`CLAUDE_CODE_REMOTE` 或 git instructions disabled

**用户上下文**（`getUserContext`）：

- CLAUDE\.md 内容（`getClaudeMds(filterInjectedMemoryFiles(await getMemoryFiles()))`）

- `setCachedClaudeMdContent` — 供 auto\-mode 分类器使用

- 跳过条件：`CLAUDE_CODE_DISABLE_CLAUDE_MDS` 或 `--bare` 且无 `--add-dir`

- 总是包含：`currentDate`（`getLocalISODate()`）

### 7\.2 CLAUDE\.md 发现与合并

**发现顺序**（`utils/claudemd.ts`）：

```Plain Text
① Managed: getManagedFilePath()/.claude/rules/*.md
② User: ~/.claude/CLAUDE.md + ~/.claude/rules/*.md
③ Project（从 filesystem root → cwd，越近 cwd 越靠后 = 优先级越高）:
   每个目录: {dir}/CLAUDE.md
             {dir}/.claude/CLAUDE.md
             {dir}/.claude/rules/**/*.md
             {dir}/CLAUDE.local.md
④ --add-dir 额外目录（同 project 结构）
⑤ AutoMem: auto-mem MEMORY.md（若未被 filterInjectedMemoryFiles 过滤）
⑥ TeamMem: team 子目录

```

**@path 展开**：递归包含，循环检测，仅文本文件扩展名。

**合并策略**：顺序拼接 \+ 文件标签（非深度合并）。

**优先级规则**：Managed \> User \> Project（越近 cwd 越高）— 后出现的块在模型叙述中更晚，优先级更高。

### 7\.3 四层记忆体系

|层次|位置|写入时机|用于压缩|文件|
|---|---|---|---|---|
|Project 指令|`.claude/CLAUDE.md`|手动|✗|`claudemd.ts`|
|User 偏好|`~/.claude/CLAUDE.md`|手动|✗|`claudemd.ts`|
|Auto Memory|`~/.claude/auto-mem/MEMORY.md` \+ topic files|对话后 forked agent|✗|`memdir/memdir.ts`|
|Session Memory|per\-session `.md`|每轮采样后 edit\-only agent|✓（零 LLM 成本）|`SessionMemory/sessionMemory.ts`|

### 7\.4 Auto Memory 提取（extractMemories）

**门控条件**：`tengu_passport_quail` GrowthBook \+ `isAutoMemoryEnabled()` \+ 非 remote \+ 主 agent only \+ 每 N 轮一次（`tengu_bramble_lintel`，默认 1 轮）

**实现**：

- 游标 `lastMemoryMessageUuid`：只处理新消息，防止重复处理

- 若主 agent 已写入 auto\-mem 路径（`hasMemoryWritesSince`）→ 跳过（避免双写）

- `runForkedAgent` 工具集：Read/Grep/Glob \+ 只读 Bash \+ **Write/Edit 仅限 auto\-mem 目录**

- 成功后：`createMemorySavedMessage`（排除 MEMORY\.md 本身不计 analytics）

**MEMORY\.md 结构**：最大 **200 行** \+ **25,000 字节**（`truncateEntrypointContent`）；Index 文件 \+ 可选 topic 子文件。

### 7\.5 Session Memory（双重用途）

**提取触发**（`shouldExtractMemory`）：

- `querySource === 'repl_main_thread'` \+ `tengu_session_memory` feature

- 阈值：init token count / 两次更新间最小 tokens / tool calls 间距（远程配置）

- 最后 assistant turn 无工具调用（或同时满足 token \+ tool\-call 阈值）

**提取机制**：edit\-only forked agent，只能写 session memory 文件。

**双重用途**：

26. **上下文注入**：会话启动时 session memory 注入 context

27. **零成本压缩**：`trySessionMemoryCompaction` 读取该文件作为摘要，无需调用 LLM

## 第八章：上下文压缩（Compact 三策略）

### 8\.1 触发机制

```Plain Text
autoCompactIfNeeded(messagesForQuery, toolUseContext, ...):
  阈值 = getAutoCompactThreshold(model)
        = getContextWindowForModel(model)
          - min(maxOutputTokens, 20000)   ← 摘要输出预留
          - AUTOCOMPACT_BUFFER_TOKENS(13000)
          ± CLAUDE_AUTOCOMPACT_PCT_OVERRIDE / CLAUDE_CODE_AUTO_COMPACT_WINDOW

  当前用量 = tokenCountWithEstimation(messages)
           = last real assistant usage.input_tokens
             + roughTokenCountEstimationForMessages(后续消息)

  if 当前用量 - snipTokensFreed > 阈值:
    Circuit breaker（≥3 连续失败则跳过）
    → trySessionMemoryCompaction（Session Memory 路径）
      ↓ 失败则
    → compactConversation（Legacy LLM 摘要路径）

```

### 8\.2 Legacy LLM 压缩（compactConversation）

**详细流程**：

```Plain Text
1. executePreCompactHooks(trigger: 'manual'|'auto')
   ← 可返回 newCustomInstructions

2. streamCompactSummary:
   方式A（fork + prompt cache）: runForkedAgent with cacheSafeParams
   方式B（streaming fallback）: 最小工具集（FileRead + ToolSearch + MCP），
                                 system: "You are...summarizing conversations"

   输入处理:
     normalizeMessagesForAPI(getMessagesAfterCompactBoundary(messages))
     + stripImagesFromMessages
     + stripReinjectedAttachments（技能发现列表）
     + 摘要请求消息

   PTL 重试（最多3次）:
     摘要以 PROMPT_TOO_LONG_ERROR_MESSAGE 开头
     → truncateHeadForPTLRetry: 丢弃最旧 API round groups
     → 若头部是 assistant 消息，prepend synthetic meta user marker

3. 清理 readFileState 和 loadedNestedMemoryPaths

4. 重建 attachments（post-compact 上下文恢复）:
   - 最近 5 个文件（POST_COMPACT_MAX_FILES_TO_RESTORE）
   - 每文件预算 5k tokens，总预算 50k tokens（POST_COMPACT_TOKEN_BUDGET）
   - plan file（若存在）
   - plan mode 状态
   - 已调用的 skills（按预算截断）
   - deferred tools / agent listing / MCP 变更 delta
   - async agent 状态

5. processSessionStartHooks('compact') + executePostCompactHooks

6. buildPostCompactMessages:
   compact_boundary → summary user message(s) → messagesToKeep → attachments → hooks

```

### 8\.3 Session Memory 压缩（零 LLM 成本）

```Plain Text
trySessionMemoryCompaction(messages, toolUseContext):
  → 等待 session memory 提取完成（若正在进行）
  → 读取 session memory 文件
  → 确认非空（非 template）
  → 找到 lastSummarizedMessageId

  calculateMessagesToKeepIndex:
    最少保留 ~10k tokens 或 5 条文本消息
    最多保留 ~40k tokens
    遵守 tool pair 完整性（不在工具调用中间截断）
    遵守 thinking block 不变量

  注入 session memory file 内容作为摘要（无 LLM 调用）
  runPostCompactCleanup()

  若压缩后仍超阈值 → return false（降级到 Legacy 路径）

```

### 8\.4 Partial 压缩

- 可指定 `from`（仅压缩之后的部分）或 `up_to`（仅压缩之前的部分）

- 计算 delta attachments（仅压缩部分的变化）

- 不同的 prompt cache 行为（partial 不打破 session cache）

---

## 第九章：多智能体系统

### 9\.1 三种 Agent 执行模式

**子 Agent 执行模式总览**

**AgentTool（in\-process 同进程）**

- 调用方式：`AgentTool` async/sync

- 执行：`runAgent()` → `query()` 同进程

- sync 模式：`shareSetAppState: true`（共享父 AppState 更新）

- async 模式：`void runWithAgentContext(runAsyncAgentLifecycle(...))`（不阻塞父 Agent）

**InProcessTeammate（共享进程 \+ 独立 context）**

- 调用方式：`TeamCreateTool`

- 执行：`spawnInProcessTeammate` → `runWithTeammateContext` → `query()` 同进程独立 ALS

- 特点：持久团队成员，有独立 identity，支持 TeammateIdle hook

**OutOfProcess Teammate（tmux/iTerm 新 pane）**

- 调用方式：`TeamCreateTool`（出进程）

- 执行：shell cmd \+ `writeToMailbox` → 独立 claude 进程 \+ tmux pane

**Remote CCR（ant only）**

- 调用方式：`AgentTool`（isolation: remote）

- 执行：CCR 远端执行 → return `{ status: 'remote_launched', sessionUrl }`

### 9\.2 AgentTool vs InProcessTeammate 对比

|维度|AgentTool|InProcessTeammate|
|---|---|---|
|任务类型|一次性子任务 / 协调者 worker|持久团队成员（有 identity）|
|状态类型|`LocalAgentTaskState`|`InProcessTeammateTaskState`|
|Context 隔离|`runWithAgentContext`（analytics）|`runWithTeammateContext`（ALS）|
|权限|async: `shouldAvoidPermissionPrompts`；sync: 全 UI|`createInProcessCanUseTool`：转发 leader 队列|
|工具集|async: `ASYNC_AGENT_ALLOWED_TOOLS`；forked: 可自定义|`IN_PROCESS_TEAMMATE_ALLOWED_TOOLS`（含 Agent\+Task 工具）|
|Plan 支持|无|`awaitingPlanApproval` 状态|
|Idle 检测|无|`TeammateIdle` hook，`isIdle` 字段|

### 9\.3 Coordinator 模式详解

**系统 Prompt 结构**（`getCoordinatorSystemPrompt`）：

```Plain Text
角色声明：
  你是 coordinator，所有输出面向用户（非 worker XML）
  不能说"based on your findings"（必须综合而非委托）

工具规则：
  使用 Agent / SendMessage / TaskStop
  不能设置 worker model（统一管理）
  单条消息多个 Agent 调用 = 并行执行

任务通知协议：
  <task-notification task-id="..." status="running|completed|failed" summary="...">
  额外字段：<result>...</result> / <usage>...</usage>

工作流四阶段：
  Research（并行 workers，read-heavy）
  Synthesis（coordinator 综合，不委托 worker）
  Implementation（写同一文件只用一个 worker）
  Verification（独立 worker 验证）

```

**Worker 工具集**（`getCoordinatorUserContext`）：从 `ASYNC_AGENT_ALLOWED_TOOLS` 过滤，排除内部工具，可包含 MCP server name 和可选 scratchpad 路径。

### 9\.4 Task 状态机

**TaskState 联合类型**（`tasks/types.ts`）：

```TypeScript
type TaskState =
  | LocalShellTaskState       // Bash 后台任务（isBackgrounded）
  | LocalAgentTaskState       // AgentTool 子 agent
  | RemoteAgentTaskState      // CCR 远端 agent
  | InProcessTeammateTaskState // 团队成员（awaitingPlanApproval, permissionMode）
  | LocalWorkflowTaskState    // Workflow 工具
  | MonitorMcpTaskState       // MCP 监控
  | DreamTaskState;           // Dream 模式

```

**TaskStateBase 公共字段**：`id`, `type`, `status`, `description`, `toolUseId`, `startTime`, `outputFile`, `outputOffset`, `notified`, `evictAfter`

**任务生命周期**（`utils/task/framework.ts`）：

- `registerTask` → `AppState.tasks[id]` 更新，emit SDK `system/task_started`

- `updateTaskState` → 不可变 patch

- `evictTerminalTask` → terminal \+ notified \+ retain rules → 从 AppState 移除

- `generateTaskAttachments` → 轮询 outputFile，更新 outputOffset（增量读取）

### 9\.5 Background Task（Ctrl\+B 机制）

**两层语义**：

```Plain Text
单次 Ctrl+B:
  task:background keybinding
  → backgroundAll() → isBackgrounded: false → true
  工作继续，UI 移到其他任务

主会话 background:
  useSessionBackgrounding
  → onBackgroundQuery()
  → LocalMainSessionTask: 独立 transcript + query() loop
    （in-process，非新进程）

auto-background（同步 agent > 120s）:
  registerAgentForeground 中的 race：
  Promise.race([agentCompletion, backgroundSignal, autoBackgroundTimer])
  → 超时 → 转异步完成路径

```

## 第十章：服务层详解

### 10\.1 LSP 集成

**文件**：`src/services/lsp/`（7 个文件）

**架构**：`manager.ts`（单例 `LSPServerManager`）→ `LSPServerManager.ts`（多服务器管理）→ `LSPServerInstance.ts`（单服务器）→ `LSPClient.ts`（vscode\-jsonrpc 连接）

**声明的客户端能力（initialize 请求）**：

```TypeScript
capabilities: {
  workspace: { configuration: false, workspaceFolders: false },
  textDocument: {
    synchronization: { didSave: true },
    publishDiagnostics: { relatedInformation: true, tagSupport: true, codeDescriptionSupport: true },
    hover: { contentFormat: ['markdown', 'plaintext'] },
    definition: { linkSupport: true },
    references: true,
    documentSymbol: { hierarchicalDocumentSymbolSupport: true },
    callHierarchy: true
  },
  general: { positionEncodings: ['utf-16'] }
}

```

**支持的协议操作**：`textDocument/didOpen`, `didChange`（full sync），`didSave`, `didClose`, `publishDiagnostics`（监听）；`sendRequest`（hover, definition, references, documentSymbol, callHierarchy）

**连接健壮性**：`-32801`（content modified）错误最多重试 3 次（带退避）；`onCrash` 处理器记录并可选重连。

### 10\.2 OAuth 2\.0 流程

**文件**：`src/services/oauth/`（5 个文件）

**完整 PKCE 流程**：

```Plain Text
1. generateCodeVerifier()
   → 32 字节随机数 → URL-safe base64（无 padding）

2. startOAuthFlow():
   → AuthCodeListener 监听本地随机端口
   → buildAuthUrl(code_challenge=S256(verifier), state=random)
   → 打开浏览器

3. waitForAuthorization():
   → 接收 ?code=&state= redirect
   → 验证 state（CSRF 防护）
   → 保持 HTTP 连接 open（等待后续重定向）

4. exchangeCodeForTokens(client.ts):
   POST TOKEN_URL
   { grant_type: 'authorization_code', code_verifier, redirect_uri, client_id, state }
   → 15s timeout
   → 返回 { access_token, refresh_token, expires_in, ... }

5. handleSuccessRedirect（自动流程）

Token 刷新:
  → isOAuthTokenExpired: now + 5min >= expiresAt
  → refreshOAuthToken: grant_type: 'refresh_token'
  → 更新 expiresAt，可选 fetchProfileInfo

```

**Token 存储**：`saveOAuthTokensIfNeeded` → `getSecureStorage()` → macOS Keychain（在 `utils/auth.ts`）。

### 10\.3 Analytics（GrowthBook）

**文件**：`src/services/analytics/`（9 个文件）

**架构**：`logEvent/logEventAsync` → 队列 → `attachAnalyticsSink()` 后分发 → Datadog（gated）\+ 1P 日志（always）

**GrowthBook 集成特点**：

- `remoteEval: true`（服务端评估，不暴露本地规则）

- **API Bug Workaround**：服务器返回 `value` 而非 `defaultValue`，客户端转换

- 已评估值缓存到 `remoteEvalFeatureValues`（SDK 重新评估忽略服务器值）

- 磁盘持久化：`cachedGrowthBookFeatures` 到 global config（全量替换）

- 覆盖机制：`CLAUDE_INTERNAL_FC_OVERRIDES`（ant）\+ `growthBookOverrides` in config

- 刷新频率：外部用户 6h，ant 20min；auth 变化后重新初始化（headers 不可更新）

**读取 API**：

- `getFeatureValue_CACHED_MAY_BE_STALE`（非阻塞，最常用）

- `checkSecurityRestrictionGate`（安全相关 gate，同步）

- `checkGate_CACHED_OR_BLOCKING`（可阻塞等待初始化）

### 10\.4 Tool Orchestration（工具并发执行）

**文件**：`src/services/tools/toolOrchestration.ts`

**runTools 批处理算法**：

```Plain Text
partitionToolCalls(toolUseBlocks):
  连续的 isConcurrencySafe = true → 同一 batch
  任何 isConcurrencySafe = false → 新 batch（通常独占一个）

for (const batch of batches):
  if batch.allConcurrencySafe:
    runToolsConcurrently(batch, concurrency=MAX_TOOL_USE_CONCURRENCY)
    context modifiers 按顺序应用（所有工具完成后）
  else:
    runToolsSerially(batch)
    每个工具的 context modifier 立即应用

```

**默认并发数**：10（`CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` 可覆盖）

### 10\.5 StreamingToolExecutor（流式并发执行）

**设计目标**：在 SSE 流式响应中，一旦 tool\_use block 开始，立即开始执行该工具，不等流式响应结束。

**并发规则**：

- `canExecuteTool(tool)`：无正在执行的工具 **OR** 新工具 safe \+ 所有运行中的工具 safe

- `processQueue`：按接收顺序处理；non\-safe 工具如果不能立即运行则 break（保持顺序）

**错误传播**：

- Bash 错误 → `hasErrored: true` \+ `siblingAbortController.abort('sibling_error')` → 兄弟子进程终止

- 非 Bash 错误 → 不取消兄弟工具

**Fallback 处理**：`discard()` 丢弃未完成工作，生成 synthetic "Streaming fallback" tool\_result。

### 10\.6 Policy Limits（企业管控）

**触发条件**：1P API \+ 1P base URL \+ （Console API key 或 OAuth enterprise/team）

**HTTP 接口**：`GET /api/claude_code/policy_limits`

- `If-None-Match: "sha256:..."` ETag（sorted JSON hash）

- 304 → 使用缓存；200 → 新数据；404 → 空策略（全放行）

**Schema**：`{ restrictions: Record<string, { allowed: boolean }> }`

**Fail\-open 策略**：获取失败无缓存 → 全放行，**除非** `allow_product_feedback` 在 "essential traffic only" 模式下（无缓存 → deny）。

**轮询**：每 1h 刷新，auth 变化时立即刷新，`waitForPolicyLimitsToLoad` 30s 超时。

### 10\.7 Remote Managed Settings（远程推送配置）

**Pull 模式**（不是 WebSocket push）：`GET /api/claude_code/settings`

**安全检查**：新配置需通过 `checkManagedSettingsSecurity` / `handleSecurityCheckResult`（可能需用户确认危险转换）

**应用路径**：`setSessionCache` → `saveSettings` → `settingsChangeDetector.notifyChange('policySettings')` → 热重载

**启动**：disk cache 优先（unblock waiters）→ 后台 1h 轮询

---

## 第十一章：Hooks 生命周期系统

### 11\.1 所有 Hook 事件

**HOOK\_EVENTS（完整列表）**：

```Plain Text
PreToolUse / PostToolUse / PostToolUseFailure
Notification
UserPromptSubmit
SessionStart / SessionEnd
Stop / StopFailure
SubagentStart / SubagentStop
PreCompact / PostCompact
PermissionRequest / PermissionDenied
Setup
TeammateIdle
TaskCreated / TaskCompleted
Elicitation / ElicitationResult
ConfigChange
WorktreeCreate / WorktreeRemove
InstructionsLoaded
CwdChanged
FileChanged

```

特殊（非 HOOK\_EVENTS）：`StatusLine`（状态栏）、`FileSuggestion`（文件补全）

### 11\.2 两种执行路径

**executeHooks**（async generator）：用于可以向 model/UI 反馈的 hooks（工具 hooks、stop hooks、permission request 等）。逐步 yield `AggregatedHookResult`。

**executeHooksOutsideREPL**：用于无 REPL 消费者的 hooks（notifications、session end、compact 等）。失败主要通过 `--debug` 可见。

### 11\.3 Hook 执行细节

**匹配**（`getMatchingHooks`）：

- 按 `matchQuery`（工具名 / session source / compact trigger 等）过滤 matchers

- `if` 条件：`prepareIfConditionMatcher` 评估 permission\-rule 语法的条件过滤（如 `Bash(git *)` 仅在 git 命令时触发）

- 信任检查：交互模式下等待 workspace trust 接受；非交互（SDK）直接运行

- Kill switches：`shouldDisableAllHooksIncludingManaged()`, `CLAUDE_CODE_SIMPLE`, HTTP hooks 在 `SessionStart`/`Setup` 禁用（防止 headless 死锁）

**命令 Hook 超时**：

- 工具 hooks：`TOOL_HOOK_EXECUTION_TIMEOUT_MS`（默认 10 分钟）

- Session end hooks：`getSessionEndHookTimeoutMs()`（默认 1500ms）

**JSON 输出协议**（`parseHookOutput` / `processHookJSONOutput`）：

```TypeScript
// hook stdout 解析为 JSON 时支持以下字段:
{
  continue?: false,          // 阻止后续操作
  decision?: 'approve' | 'block',
  systemMessage?: string,
  hookSpecificOutput?: {
    // PreToolUse:
    permissionDecision?: { behavior: 'allow', updatedInput?, updatedPermissions? }
                       | { behavior: 'deny', message?, interrupt? }
    // UserPromptSubmit / PostToolUse:
    additionalContext?: string
    updatedMCPToolOutput?: string
  }
}

```

## 第十二章：Skills、Plugins 与 Commands

### 12\.1 Skills 系统精解

**文件 Frontmatter 完整字段**（`skills/loadSkillsDir.ts`）：

|Frontmatter 字段|解析到|说明|
|---|---|---|
|`description`|`description`|可从 markdown 正文 `extractDescriptionFromMarkdown` 推断|
|`name`|`displayName`|`userFacingName = displayName | skillName`|
|`user-invocable`|`isHidden`|默认 true（可见）；false → hidden|
|`model`|`model`|`'inherit'` → undefined；否则 `parseUserSpecifiedModel`|
|`effort`|`effort`|`parseEffortValue`；invalid → undefined（警告日志）|
|`allowed-tools`|`allowedTools`|`parseSlashCommandToolsFromFrontmatter`|
|`argument-hint`|`argumentHint`|命令行提示文本|
|`arguments`|`argumentNames`|`parseArgumentNames`（`$ARGS` 展开）|
|`when_to_use`|`whenToUse`|模型调用时机说明（非 `paths` 条件）|
|`version`|`version`|—|
|`disable-model-invocation`|`disableModelInvocation`|禁止此 skill 调用模型|
|`hooks`|`hooks`|`HooksSchema().safeParse`（失败 → drop \+ 警告）|
|`context`|`executionContext`|`'fork'` → fork；其他 → inline|
|`agent`|`agent`|Agent 定义|
|`shell`|`shell`|Shell 执行策略（`parseShellFrontmatter`）|
|`paths`|条件激活逻辑|gitignore 语法，匹配文件路径时激活|

**加载顺序**：managed skills → user skills → project skills（近 cwd 优先）→ \-\-add\-dir skills

**条件激活**（`activateConditionalSkillsForPaths`）：

- `paths` 非空 \+ 未激活 → 进入 `conditionalSkills` 等待

- 某工具调用路径匹配 gitignore pattern → 激活，移入 `dynamicSkills`

- 一次性（`activatedConditionalSkillNames` 去重）

**去重**：`realpath(filePath)` 作为 key；first occurrence wins；`null` fileId 不去重。

**MCP Skills**（`skill://` 资源）：通过 `mcpSkillBuilders.ts` 注册（避免循环 import）；`resources/listChanged` → 清缓存重取。

### 12\.2 Plugin 系统

**Manifest Schema 关键字段**（`utils/plugins/schemas.ts`）：

```TypeScript
PluginManifestSchema = {
  // 元数据
  name: string,          // 必填，无空格
  version?: string,
  description?: string,
  author?: PluginAuthorSchema,

  // 扩展内容
  hooks?: HooksSource,           // 相对 .json 路径或 inline HooksSchema
  commands?: CommandsSource,     // 路径/路径数组/record<name,metadata>
  agents?: AgentsSource,         // .md 路径或数组
  skills?: SkillsSource,         // 相对目录路径
  outputStyles?: OutputStylesSource,
  channels?: Array<{server, displayName?, userConfig?}>,
  mcpServers?: MCPSource,        // 支持 JSON 路径/DXT/URL/inline record/数组混合
  lspServers?: LSPSource,
  settings?: Record<string, unknown>,  // 白名单过滤（PluginSettingsSchema）
  userConfig?: Record<string, unknown>, // ${user_config.KEY} 变量替换
  dependencies?: DepRef[]
}

```

**Plugin 来源**（从低到高优先级）：

- Marketplace 插件（settings 中 `name@marketplace` 格式）

- Session 插件（`--plugin-dir` CLI flag 或 SDK plugins 选项）

- Built\-in 插件（`name@builtin`，用户可开关）

**加载流程**：

28. `loadPluginManifest`（不存在 → 默认 manifest；存在 → JSON parse \+ Zod 验证）

29. 相对路径验证（`validatePluginPaths`）

30. hooks 文件加载（`PluginHooksSchema`）

31. userConfig 变量替换（`${user_config.KEY}`）

32. 重名去重（同 `pluginName` → error 收集到 `PluginError[]`）

### 12\.3 关键命令实现

**/compact**（manual）vs Auto\-Compact：

- Manual：先尝试 Session Memory（零成本）→ 若 REACTIVE\_COMPACT 模式用 `reactiveCompactOnPromptTooLong` → 否则传统 LLM 摘要（`isAutoCompact: false`）

- Auto：同上但 `isAutoCompact: true`，从 queryLoop 自动触发

**/review**：`type: 'prompt'`，注入 `LOCAL_REVIEW_PROMPT` 指导模型使用 `gh pr list/view/diff` 进行本地代码审查。

**/doctor**（诊断）检查项：安装方式/类型 \+ 版本 \+ ripgrep 状态 \+ 权限规则合理性 \+ CLAUDE\.md/Agent/MCP token 贡献者 \+ 沙箱状态 \+ 插件错误 \+ MCP 解析警告 \+ keybinding 冲突。

**/memory**：`clearMemoryFileCaches()` → `getMemoryFiles()` → 用户选择文件 → `mkdir`（如需）\+ `writeFile(flag:'wx')` 创建空文件 → `editFileInEditor(path)`（使用 `$VISUAL/$EDITOR`）。

---

## 第十三章：Bridge / Remote / Server / IDE 集成

### 13\.1 Environments Bridge（Remote Control）

**文件**：`src/bridge/bridgeMain.ts`

**完整协议流程**：

```Plain Text
1. 注册环境:
   POST /v1/environments/bridge
   Auth: OAuth Bearer
   Body: { machine_name, directory, branch, git_repo_url, max_sessions, metadata }
   → 返回 { environmentId, environmentSecret }

2. 轮询工作（用 environmentSecret，非 OAuth）:
   GET /v1/environments/{envId}/work/poll
   Auth: Bearer environmentSecret
   → null（无工作）或 WorkResponse { id, type, data, secret, created_at }

3. 解码 WorkSecret（base64url JSON）:
   { version: 1, session_ingress_token, api_base_url, use_code_sessions?,
     auth?, claude_code_args?, mcp_config?, environment_variables? }

4. ACK 确认接受工作:
   POST /v1/environments/{envId}/work/{workId}/ack
   Auth: Bearer session_ingress_token

5. 建立 Session 连接:
   v1（WebSocket ingress）: ws(s)://host/v1/session_ingress/ws/{sessionId}
   v2（CCR）: POST {apiBaseUrl}/v1/code/sessions/{sessionId}/worker/register
             → { worker_epoch }
             → SSE + CCRClient 写

6. 生命周期:
   empty poll → getPollIntervalConfig 退避等待
   at capacity → heartbeatActiveWorkItems（仅心跳，不轮询）
   completed → stopWork + archiveSession（compat）

```

### 13\.2 Bridge 消息协议

**入站路由**（`bridge/bridgeMessaging.ts`）：

```Plain Text
每条 WebSocket 消息 = JSON string：

1. type === 'control_response' → 权限响应回调
2. type === 'control_request' → handleServerControlRequest
   （必须快速响应，约 10-14s 服务器超时）
3. isSDKMessage（对象 + string type）:
   uuid 在 recentPostedUUIDs → echo drop
   uuid 在 recentInboundUUIDs → redelivery drop
   type === 'user' → 去重记录 + onInboundMessage

```

**Control Request 类型**：

|subtype|处理|
|---|---|
|`initialize`|返回 `{ commands: [], output_style, models: [], account: {}, pid }`|
|`set_model`|通过 callback 设置模型|
|`set_max_thinking_tokens`|通过 callback 设置|
|`interrupt`|Abort 当前操作|
|`set_permission_mode`|通过 `onSetPermissionMode` 决定|
|未知|`control_response: error`|

**BoundedUUIDSet**：FIFO ring buffer \+ set 去重，有界内存防止 UUID 无限增长。

**消息转发资格**（`isEligibleBridgeMessage`）：`user` / `assistant` / `system{subtype: 'local_command'}` → 转发；virtual 消息不转发。

### 13\.3 Remote Sessions（Cloud Session Subscriber）

**文件**：`src/remote/`

```Plain Text
SessionsWebSocket:
  连接: wss://{BASE_API_URL}/v1/sessions/ws/{sessionId}/subscribe?organization_uuid=...
  Auth: OAuth Bearer（header，非消息体）

  入站: JSON per frame → SDKMessage | control types
    can_use_tool → 权限提示
    control_cancel_request → 清除 pending

  出站用户 turn:
    POST /v1/sessions/{sessionId}/events
    Body: { events: [{ uuid, session_id, type:'user', parent_tool_use_id: null,
                       message: { role:'user', content } }] }
    Headers: OAuth + anthropic-beta: ccr-byoc-2025-07-29 + x-organization-uuid

  权限回复 / interrupt:
    WebSocket sendControlResponse / sendControlRequest（JSON string）

```

### 13\.4 Server Mode（Direct Connect）

**文件**：`src/server/`

这是 **Direct Connect 客户端协议**（不是服务器端实现）：

- `createDirectConnectSession`：`POST {serverUrl}/sessions` → `{session_id, ws_url, work_dir}`

- `DirectConnectSessionManager`：WebSocket 连接，**换行符分隔 JSON**，过滤噪声类型（`keep_alive`, `streamlined_`），处理 `control_request/can_use_tool`

### 13\.5 IDE 检测与集成

**文件**：`src/utils/ide.ts`（约 1495 行）

**检测机制**：

- Lockfile：`~/.claude/ide/{port}.lock`（WSL 额外路径）

- Lockfile JSON：`{ workspaceFolders, pid, ideName, transport: 'ws'|'sse', runningInWindows, authToken }`

- 排序：按 mtime 最新优先

- 匹配：cwd vs workspaceFolders（NFC normalization \+ WSL 路径转换 \+ Windows 大小写 drive letters）

- 多窗口消歧：**祖先 PID 遍历**

**连接 URL**：

- WebSocket：`ws://{detectHostIP}:{port}`

- SSE：`http://{detectHostIP}:{port}/sse`

- Host：127\.0\.0\.1 vs WSL→Windows gateway（`detectHostIP`）

**IDE 支持进程关键字**（`supportedIdeConfigs`）：

- VS Code 家族：vscode/cursor/windsurf 进程名

- JetBrains：idea/webstorm/pycharm/\.\.\. 进程名

**MCP 集成**：`callIdeRpc` → `mcp__ide__` 工具；`closeOpenDiffs` → `callIdeRpc('closeAllDiffTabs')`；`hasAccessToIDEExtensionDiffFeature` 检测扩展能力。

## 第十四章：Terminal UI（React \+ Ink）

### 14\.1 Ink 渲染引擎

**文件**：`src/ink/ink.tsx`（自定义 Ink 引擎）

**核心组件**：

- **React Reconciler**：将 React 树映射到 Yoga 布局节点

- **Yoga 布局**：Flexbox CSS 布局引擎（C\+\+ → WebAssembly）

- **双缓冲帧**：`frontFrame` / `backFrame`，差异比较后输出最小 ANSI 序列

- **Alt\-screen**：全屏模式，启动时切换，关闭时恢复

- **Raw mode stdin**：`useInput` 捕获键盘事件

- **Kitty keyboard flags**：支持现代终端的按键增强协议

- **IME/a11y cursor**：光标声明

**公开 Facade**（`src/ink.ts`）：`render`, `createRoot` 均包装在 `ThemeProvider` 中，统一主题。

### 14\.2 processUserInput 管道

**完整处理路径**：

```Plain Text
用户 keypress → PromptInput → REPL.onSubmit
→ handlePromptSubmit:
  1. expandPastedTextRefs(input, pastedContents)  ← 展开 [Pasted text #N] 引用
  2. 若 queryBusy → enqueue(QueuedCommand)        ← 加入队列等待
  3. 否则 → executeUserInput:
     → queryGuard.reserve()
     → for each QueuedCommand:
       → processUserInput(input, ...)
         → processUserInputBase:
           1. 多模态处理（image blocks resize）
           2. pasted images → storeImages + imageMetadata
           3. Bridge skip 逻辑（isBridgeSafeCommand）
           4. Ultraplan keyword 重路由（feature gated）
           5. getAttachmentMessages（@file, MCP resources, @agent-...）
           6. mode === 'bash' → processBashCommand（! 命令）
           7. input.startsWith('/') → processSlashCommand
           8. else → processTextPrompt → { shouldQuery: true }
         ← executeUserPromptSubmitHooks（可阻止或添加 hook context）
     → onQuery(newMessages, abortController, shouldQuery=true)
        → query(...) [main loop]

```

**Attachment 类型**（`@` 引用）：

- `@/path/to/file` → FileReadTool 结果

- `@agent-{name}` → 已注册 Agent 的描述

- `@{mcp-resource-uri}` → MCP resource 内容

### 14\.3 REPL 屏幕组件树

`src/screens/REPL.tsx` 是主交互会话 UI，组合了：

```Plain Text
REPL
├── Messages（对话历史 transcript）
│   └── VirtualMessageList（虚拟化滚动）
├── PermissionRequest（工具权限提示）
├── WorkerPermissionRequest（swarm worker 权限）
├── MCPElicitationDialog（MCP 服务请求用户确认）
├── PromptDialog（通用交互对话框）
├── CostThresholdDialog（费用阈值提醒）
├── IdleReturnDialog（超时返回提示）
├── TaskListV2（后台任务列表）
├── Spinner / LoadingIndicator
├── StatusLine（底部状态栏）
├── VoiceInput（条件加载）
└── PromptInput（底部输入框）
    ├── VimTextInput（Vim 模式）
    ├── CommandSuggestions（斜杠命令补全）
    └── FilePathCompletion（文件路径补全）

```

**对话框模式**（`interactiveHelpers.tsx`）：`showDialog(root, renderer)` → `Promise`，通过 `done(result)` 解析。本质是临时替换 React 树，Promise 结束后恢复。

### 14\.4 Vim 模式

**文件**：`src/vim/`（`types.ts`, `transitions.ts`, `operators.ts`, `motions.ts`, `textObjects.ts`）

**状态机**：

```Plain Text
VimState
  INSERT（记录插入文本用于 . 重复）
  NORMAL
    CommandState:
      idle | operator | operatorTextObj | find | g | replace | indent | ...

```

**集成**：`PromptInput` 中检测 `editor-mode === 'vim'` → 使用 `VimTextInput` 组件 → `useVimInput` hook → `transition(state, input, ctx)` → `useTextInput`（底层光标/值管理）

---

## 第十五章：Sandbox、Worktree 与 Plan Mode

### 15\.1 Sandbox（`utils/sandbox/`）

**底层实现**（非 `sandbox-exec`）：

- macOS：`@anthropic-ai/sandbox-runtime`（平台原生沙箱）

- Linux / WSL2\+：**bubblewrap \(bwrap\)**（需 `apt install bubblewrap socat`）

- WSL1：不支持

**convertToSandboxRuntimeConfig 配置生成**：

```Plain Text
网络限制:
  allowedDomains/deniedDomains ← WebFetch 权限规则 + sandbox.network + policy allowManagedDomainsOnly

文件系统限制:
  allowWrite: ['.', <Claude 临时目录>]  ← 始终允许当前目录
  + Edit/Read 权限规则 → allowWrite/denyWrite/allowRead/denyRead
  + 硬编码 denyWrite: [settings files, managed settings, .claude/skills]
  + bare-repo 伪装防护: HEAD/objects/refs → denyWrite（若存在）

Git worktree 兼容:
  若 cwd 是 linked worktree → allowWrite: [worktreeMainRepoPath]
  （允许更新 main repo 的 index/lock）

```

**绕过场景**：`!` bash 模式使用 `dangerouslyDisableSandbox: true`，受 `areUnsandboxedCommandsAllowed()` 外层保护。

### 15\.2 Worktree 隔离

**文件**：`src/tools/EnterWorktreeTool/EnterWorktreeTool.ts`

**执行流程**：

33. 若已在 worktree session → 拒绝

34. 若 cwd 在现有 worktree 内 → 移动到 canonical main repo root（防止嵌套）

35. `createWorktreeForSession(sessionId, slug)` → `WorktreeCreate` hook 优先；否则 `git worktree add`

36. slug 验证：`validateWorktreeSlug`（segments、禁止 `..`、长度上限）

37. `process.chdir + setCwd` → 工作目录切换

38. 失效：system prompt sections / CLAUDE\.md 缓存 / plans 目录缓存

### 15\.3 Plan Mode

**限制内容**：

- 工具标记：`isReadOnly: true`

- Tool result text：强调"explore only，不要 edit/write 文件，直到 ExitPlanMode"

- 权限模式：`plan`（bypass\-immune ask\-rules 仍有效）

- `checkEditableInternalPath`：plan files / scratchpad 允许写入

**prepareContextForPlanMode**：

- 存储 `prePlanMode`（供 ExitPlanMode 恢复）

- 若 auto 模式：可能保留或激活 auto classifier（`shouldPlanUseAutoMode`）

- 剥离/恢复危险权限布局

**禁用条件**：`getAllowedChannels().length > 0`（Kairos 渠道激活时禁止进入 plan）

---

## 第十六章：Settings、Config 与迁移

### 16\.1 Settings 分层体系

**合并顺序（从低到高优先级）**：

```Plain Text
plugin base settings
  → userSettings   : ~/.claude/settings.json
  → projectSettings: {cwd}/.claude/settings.json
  → localSettings  : {cwd}/.claude/settings.local.json
  → flagSettings   : --settings 文件 or SDK inline
  → policySettings : remote managed / MDM / managed-settings.json / HKCU

```

**安全设计（projectSettings 隔离）**：

```TypeScript
// 安全敏感字段忽略 projectSettings（防止恶意 repo 提升权限）
hasSkipDangerousModePermissionPrompt:
  仅读取 user/local/flag/policy
// 同类保护应用于其他危险权限字段

```

**验证流程**：`parseSettingsFileUncached` → `filterInvalidPermissionRules` → `SettingsSchema().safeParse` → ValidationError 收集（不 crash）

### 16\.2 GlobalConfig vs Settings

|—|GlobalConfig|Settings|
|---|---|---|
|文件|`~/.claude/.claude.json`|`settings.json` 各级|
|内容|会话状态（lastCost, migrationVersion, projects\{\}, trust, worktree）|用户永久偏好（permissions, env, MCP, plugins）|
|操作|`getGlobalConfig()` / `saveGlobalConfig()`|`getSettingsForSource()` / `updateSettingsForSource()`|
|锁|自动（内部）|文件锁（history\.jsonl 等）|

### 16\.3 Migration 系统

**版本化迁移**（`main.tsx`）：

```TypeScript
const CURRENT_MIGRATION_VERSION = 11  // 当前版本

function runMigrations() {
  if (getGlobalConfig().migrationVersion !== CURRENT_MIGRATION_VERSION) {
    migrateAutoUpdatesToSettings()
    migrateBypassPermissionsAccepted...()
    migrateEnableAllProjectMcpServers...()
    resetProToOpusDefault()
    migrateSonnet1mToSonnet45()
    // ... 共 11 个迁移
    saveGlobalConfig(prev => ({ ...prev, migrationVersion: CURRENT_MIGRATION_VERSION }))
  }
  migrateChangelogFromConfig()  // 异步，不阻塞
}

```

---

## 第十七章：Keybindings、Model 选择与 Output Styles

### 17\.1 Keybinding 系统

**架构**：`defaultBindings.ts`（默认）→ `loadUserBindings.ts`（用户叠加，hot\-reload）→ `resolver.ts`（解析输入）

**解析规则**：最后绑定胜（覆盖）；Chord 前缀（`ctrl+x ctrl+e`）：较长 chord 优先于单键；Escape 取消 chord 状态；`null` → unbind。

**Chokidar 热重载**：`tengu_keybinding_customization_release` GrowthBook 门控，监听 `~/.claude/keybindings.json`

### 17\.2 Model 选择逻辑

**getMainLoopModel 优先级**：

```Plain Text
1. 会话覆盖（--model CLI / env ANTHROPIC_MODEL）
2. settings.model
3. getDefaultMainLoopModelSetting():
   - Claude.ai Max/Team Premium + merge 功能 → Opus [1m]
   - 其他 → Sonnet

```

**parseUserSpecifiedModel 别名解析**：

- `opus` → 当前 opus 版本

- `sonnet` → 当前 sonnet 版本

- `haiku` → 当前 haiku 版本

- `best` → 最强可用模型

- `opusplan` → plan mode 专用 opus

- `[1m]` 后缀 → 1M context window 版本

### 17\.3 Output Styles

**Output styles 是 AI 写作风格 persona，不是 CLI 输出格式**

**getAllOutputStyles 合并顺序**（后者优先）：plugin → user → project → managed

**内置样式**（`constants/outputStyles.ts`）：`default` / `Explanatory` / `Learning` \+ 自定义 markdown 文件。

**Frontmatter 字段**：`name`，`description`，`keep-coding-instructions`（是否保留编程风格指令）

---

## 第十八章：OpenTelemetry 遥测

**文件**：`src/utils/telemetry/instrumentation.ts`

**懒加载策略（关键性能优化）**：

```TypeScript
// init.ts 中注册，不立即加载
export function initializeTelemetryAfterTrust(): void {
  if (isEligibleForRemoteManagedSettings()) {
    void waitForRemoteManagedSettingsToLoad().then(async () => {
      applyConfigEnvironmentVariables();
      await doInitializeTelemetry(); // 此时才加载约 1.1GB 的 OTel
    });
  } else {
    void doInitializeTelemetry();
  }
}

async function doInitializeTelemetry() {
  const { initializeTelemetry } =
    await import("../utils/telemetry/instrumentation.js");
  // 动态 import 懒加载
}

```

**initializeTelemetry 内部初始化**：

```Plain Text
bootstrapTelemetry() → 映射 ANT_OTEL_* → OTEL_* 标准环境变量

Console exporter 过滤（格式化输出模式下移除 console sink，防止破坏 JSON）

initializePerfettoTracing()

OTLP readers（telemetry 启用时）:
  getOtlpReaders() → OTLP metric readers（OTLP/HTTP 或 gRPC）

Resource 构建:
  service.name / service.version / os.type / host.arch / 环境标识

Full OTEL:
  logs + traces + OTLP + registerCleanup(graceful shutdown)

```

---

## 第十九章：代码质量与开发接手指南

### 19\.1 核心文件优先级地图

|优先级|文件|开发必要性|
|---|---|---|
|⭐⭐⭐⭐⭐|`src/QueryEngine.ts`|对话状态机，所有 AI 交互的入口|
|⭐⭐⭐⭐⭐|`src/query.ts`|流式主循环，工具执行，压缩触发|
|⭐⭐⭐⭐⭐|`src/services/api/claude.ts`|Anthropic API 调用，streaming，thinking|
|⭐⭐⭐⭐⭐|`src/tools.ts` \+ `src/Tool.ts`|工具注册表与接口定义|
|⭐⭐⭐⭐⭐|`src/utils/permissions/permissions.ts`|权限决策树入口|
|⭐⭐⭐⭐|`src/hooks/toolPermission/`|完整权限路由|
|⭐⭐⭐⭐|`src/services/mcp/client.ts` \+ `config.ts`|MCP 完整集成|
|⭐⭐⭐⭐|`src/services/compact/compact.ts` \+ `autoCompact.ts`|压缩策略|
|⭐⭐⭐⭐|`src/tools/AgentTool/AgentTool.tsx` \+ `runAgent.ts`|子 agent 执行|
|⭐⭐⭐⭐|`src/state/AppStateStore.ts` \+ `store.ts`|全局状态模型|
|⭐⭐⭐|`src/commands.ts`|命令注册表|
|⭐⭐⭐|`src/utils/claudemd.ts`|CLAUDE\.md 加载合并|
|⭐⭐⭐|`src/context.ts`|上下文组装|
|⭐⭐⭐|`src/main.tsx` \+ `src/entrypoints/init.ts` \+ `src/setup.ts`|启动流程|
|⭐⭐⭐|`src/utils/hooks.ts`|Hooks 执行引擎|
|⭐⭐|`src/bridge/`|Remote Control 协议|
|⭐⭐|`src/skills/loadSkillsDir.ts`|Skills 加载|
|⭐⭐|`src/utils/plugins/pluginLoader.ts`|Plugin 加载|
|⭐⭐|`src/screens/REPL.tsx`|主交互 UI|
|⭐⭐|`src/utils/ide.ts`|IDE 检测与集成|

### 19\.2 扩展开发快速入门

**新增工具**：

```TypeScript
// 1. 创建 src/tools/MyTool/MyTool.ts
export const MyTool: Tool<Input, Output> = {
  name: 'my_tool',
  description: () => '...',
  inputSchema: z.object({ param: z.string() }),
  isReadOnly: () => true,
  isConcurrencySafe: () => true,
  async call(args, ctx) { /* ... */ }
}

// 2. 在 src/tools.ts getAllBaseTools() 中注册
// 3. 可选：feature gate with feature('MY_FEATURE')

```

**新增命令**：

```TypeScript
// 1. 创建 src/commands/mycommand/index.ts
export default {
  name: "mycommand",
  description: "Description",
  type: "prompt", // 或 'local-jsx' 渲染 React UI
  getPromptForCommand: (args) => `Prompt text ${args}`,
};

// 2. 在 src/commands.ts COMMANDS() 数组中添加 lazy import

```

**新增 Skill**：

```Markdown
# .claude/skills/my-skill/SKILL.md
---
description: What this skill does
allowed-tools: Bash, Read, Edit
model: sonnet
when_to_use: Use when user needs to ...
---

The prompt content here...

```

**新增 Hook**：

```JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo $CLAUDE_TOOL_INPUT | my-audit-script"
          }
        ]
      }
    ]
  }
}

```

### 19\.3 已知限制与注意事项

**构建依赖缺失**：无 `package.json` / `tsconfig.json` → 需要从 npm bundle 补全依赖版本。`bun:bundle` 的 `feature()` 调用需要正确 Bun 构建配置（直接运行 ts\-node 会包含所有分支）。

**Thinking Signature 绑定**：Protected thinking blocks 签名与模型绑定。模型 fallback 时必须调用 `stripSignatureBlocks` 清除签名，否则 API 返回 400 "thinking blocks cannot be modified"。

**Ant 专属功能**（`USER_TYPE === 'ant'`）：`INTERNAL_ONLY_COMMANDS`（commit helper, ctx\_viz, debug\-tool\-call）、CCR `isolation: 'remote'` AgentTool 路径。`USER_TYPE !== 'ant'` 的代码路径是生产用户实际走的路径。

---

## 附录：关键常量速查

|常量|值|位置|
|---|---|---|
|`AUTOCOMPACT_BUFFER_TOKENS`|13,000|`services/compact/autoCompact.ts`|
|`COMPACT_MAX_OUTPUT_TOKENS`|20,000|`utils/context.ts`|
|`POST_COMPACT_MAX_FILES_TO_RESTORE`|5|`services/compact/compact.ts`|
|`POST_COMPACT_TOKEN_BUDGET`|\~50,000|`services/compact/compact.ts`|
|`MAX_MCP_DESCRIPTION_LENGTH`|2,048|`services/mcp/client.ts`|
|`TOOL_HOOK_EXECUTION_TIMEOUT_MS`|600,000（10分钟）|`utils/hooks.ts`|
|`SESSION_END_HOOK_TIMEOUT_MS`（默认）|1,500|`utils/hooks.ts`|
|`PROGRESS_THRESHOLD_MS`|2,000|`tools/BashTool/BashTool.tsx`|
|`ASSISTANT_BLOCKING_BUDGET_MS`|15,000|`tools/BashTool/BashTool.tsx`|
|`CURRENT_MIGRATION_VERSION`|11|`main.tsx`|
|`MCP reconnect max attempts`|5|`services/mcp/MCPConnectionManager.tsx`|
|`GrowthBook refresh (external)`|6h|`services/analytics/growthbook.ts`|
|`GrowthBook refresh (ant)`|20min|`services/analytics/growthbook.ts`|
|`Policy limits polling`|1h|`services/policyLimits/index.ts`|
|`OAuth token expiry buffer`|5 min|`services/oauth/index.ts`|
|`Max retries`|10|`services/api/withRetry.ts`|
|`API timeout`|600s|`services/api/client.ts`|
|`WebFetch cache TTL`|15 min|`tools/WebFetchTool/utils.ts`|
|`WebFetch max body`|10 MB|`tools/WebFetchTool/utils.ts`|
|`Max tool use concurrency`|10|`services/tools/toolOrchestration.ts`|
|`MEMORY.md max lines`|200|`memdir/memdir.ts`|
|`MEMORY.md max bytes`|25,000|`memdir/memdir.ts`|

