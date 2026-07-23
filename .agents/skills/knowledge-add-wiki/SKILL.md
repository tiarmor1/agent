---
name: knowledge-add-wiki
description: |
  创建或更新 SEA Pearl 知识库的 wiki 文档。根据用户提供的主题，自动调研（代码库分析、飞书文档获取、用户信息整理），
  按模板生成规范文档，写入 wiki/ 目录并更新索引。当用户说"添加 wiki"、"新增文档"、"记录到知识库"、
  "add wiki"、"/knowledge-add-wiki"时使用此技能。也适用于用户想把某个主题的知识沉淀到知识库的场景，
  即使没有明确说"wiki"——比如"帮我记录一下 sms_api 的架构"、"把这个流程写到知识库里"。
---

# /knowledge-add-wiki — 知识库文档创建与更新

根据用户提供的主题和信息，深入调研后按规范创建或更新 wiki 文档。

## 工作流程

### 1. 解析输入

从用户输入中提取三个要素：

- **主题**：要创建/更新的文档主题（必需）
- **category**：目标分类（可选，未指定则自动判断）
- **素材**：用户直接提供的信息、飞书链接、代码路径等

### 2. 确定 category

根据主题自动匹配到以下 7 个分类之一：

| Category | 内容范围 | 判断线索 |
|----------|---------|---------|
| `architecture` | 系统架构、数据流、部署拓扑 | "架构"、"设计"、"拓扑"、"数据流" |
| `services` | 代码仓库，每个仓库一篇 | 仓库名（sms_api, sea_operation_*）、"仓库"、"代码库" |
| `modules` | 业务模块，按领域划分 | "商品"、"订单"、"商家"、"售后"、"物流"、"营销" |
| `infrastructure` | 中间件、存储、消息队列 | "MySQL"、"ES"、"EventBus"、"Redis"、"TCC" |
| `workflows` | 开发/部署/运维流程 | "流程"、"步骤"、"如何"、"部署"、"发布" |
| `concepts` | 业务术语、规则、枚举值 | "什么是"、"定义"、"枚举"、"状态" |
| `external` | 外部资源导航 | "飞书文档"、"外部链接"、"文档导航" |

无法判断时，用 AskUserQuestion 确认。

### 3. 查重

在 `wiki/` 目录下搜索是否已存在同主题文档：

```
Grep: 在 wiki/ 中搜索主题关键词（标题、tags）
Glob: wiki/<category>/*.md
```

- **已存在** → 转为更新模式，读取现有文档，保留原有内容，增量更新
- **不存在** → 创建新文档

### 4. 调研

这是最核心的步骤。根据 category 和素材类型采用不同策略，使用 Subagents 并行调研保持主上下文干净。

#### ⚡ 优先使用已有技能和工具

**调研时优先使用已有技能获取信息，不要只依赖用户口述或文档链接。**

| 场景 | 推荐方式 | 说明 |
|------|---------|------|
| 查看 Web 配置页面 | 浏览器自动化（连接本地浏览器） | 复用用户登录态，直接访问内部系统获取实时信息 |
| 获取飞书文档内容 | `feishu-cli-read` / `feishu-cli-export` | 直接读取飞书文档，提取关键信息 |
| 分析代码仓库 | Explore agent / Glob / Grep | 代码库分析 |
| 查询已有知识 | `/query` | 先查知识库避免重复 |
| 获取网页内容 | `web-content-fetcher` / WebFetch | 从任意 URL 提取信息 |

**浏览器自动化实现要点**：

通过 Chrome DevTools Protocol (CDP) 连接用户正在使用的本地浏览器，复用已有的登录态、Cookie 和扩展。

```bash
# 1. 连接前检查（确保浏览器开启了远程调试）
npx agent-browser --auto-connect get url 2>&1
# 返回 URL 说明连接成功，返回 Failed 则需引导用户开启调试

# 2. 核心操作循环：导航 → 快照 → 交互 → 再快照
npx agent-browser --auto-connect open 'https://pearl.tiktok-row.net/xxx'
npx agent-browser --auto-connect wait --load networkidle  # 等待页面加载
npx agent-browser --auto-connect snapshot                 # 获取页面结构
npx agent-browser --auto-connect click @e1               # 点击元素
npx agent-browser --auto-connect fill @e2 "text"         # 填写输入框
npx agent-browser --auto-connect eval '...'              # 执行 JS 提取数据

# 3. 常用命令
npx agent-browser --auto-connect snapshot -i     # 仅交互元素
npx agent-browser --auto-connect screenshot      # 截图
npx agent-browser --auto-connect get text @e1   # 获取元素文本
npx agent-browser --auto-connect scroll down 500 # 滚动页面
```

**关键注意事项**：
- 页面跳转或刷新后，之前的元素引用（`@e1`, `@e2`）全部失效，需重新 `snapshot`
- 多个任务并行操作同一浏览器会互相干扰，应串行执行
- 慢加载页面要在 `open` 后加 `wait --load networkidle`

**示例**：
- 用户说"添加子站点权限的 wiki" → 直接打开 Pearl 后台配置页面，获取实际配置项和操作流程
- 用户说"查看某配置" → 直接打开配置页面提取内容，而不是问用户要截图
- 用户提供飞书链接 → 用 `feishu-cli-read` 直接获取内容，不要让用户自己复制粘贴

#### services（代码仓库）

仓库路径固定为 `~/go/src/code.byted.org/oec/<repo>/`，用 Explore agent 分析：

- 目录结构（顶层 + 关键子目录）
- `go.mod` 依赖
- 核心接口定义（handler、service 层）
- 配置文件、数据库 model
- 关键 README 或文档

#### modules（业务模块）

- 定位相关代码仓库中的业务逻辑
- 梳理核心流程和接口调用链
- 提取数据模型和业务规则

#### 用户提供飞书文档链接

使用 `feishu-cli-read` 或 `feishu-cli-export` 获取文档内容，提取关键信息作为素材。

#### 用户直接提供信息

整理归纳用户提供的文本，补充缺失的上下文。

### 4.5 保存原始素材

将调研过程中获取的外部内容（非用户口述）保存到 `raw/` 目录，建立追溯链：

- 飞书文档内容 → `raw/feishu/YYYY-MM-DD_<slug>.md`
- 代码分析结果 → `raw/code-analysis/YYYY-MM-DD_<slug>.md`
- 网页/API 响应 → `raw/other/YYYY-MM-DD_<slug>.md`

每个 raw 文件的 frontmatter：

```yaml
---
source_type: "feishu | code-analysis | meeting | other"
source_url: "原始 URL（如有）"
captured_date: "YYYY-MM-DD"
feeds_wiki: ["wiki/<category>/<slug>.md"]
---
```

同时在 `raw/_manifest.md` 追加一行映射记录。

> **跳过条件**：如果所有素材都来自用户直接提供的文本（无外部源），跳过此步。

### 5. 生成文档

读取模板文件 `.claude/skills/add-wiki/templates/wiki-template.md`，根据 category 选择对应的文档结构。

**文件命名规则**：
- slug：英文小写，单词用 `-` 连接
- 路径：`wiki/<category>/<slug>.md`
- 示例：`wiki/services/sms-api.md`、`wiki/concepts/product-audit-status.md`

**必须包含**：
- YAML frontmatter：title, category, tags, created, updated
- 紧跟 frontmatter 的一句话摘要（将被索引引用）
- 资源导航表（飞书链接、代码路径、相关 wiki）

**风格要求**：
- 导航优先：已有飞书文档的内容放链接，不复制全文
- 代码路径用反引号标注，精确到文件或目录
- 表格优于长段落
- Mermaid 图表遵循项目 `rules/markdown-style-guide.md` 的视觉规范

### 6. 更新索引

创建或更新文档后，必须同步更新两个索引文件：

#### 分类索引 `wiki/<category>/_index.md`

在 `<!-- 由 /knowledge-add-wiki 自动维护 -->` 注释下方添加/更新条目：

```markdown
- [文档标题](slug.md) — 一句话摘要
```

如果存在 `_暂无文档` 占位文本，替换掉。

#### 全局索引 `wiki/_index.md`

在对应分类的 `<!-- 文档列表（由 /knowledge-add-wiki 自动维护） -->` 注释下方添加/更新条目，格式同上。

### 6.5 级联交叉引用

创建或更新文档后，检查是否需要更新相关文档的交叉引用：

1. **正向引用**：新文档的「资源导航」表中引用的其他 wiki 页面
2. **反向引用**：用 Grep 搜索所有现有 wiki 页面，找到与新文档主题相关（共享 PSM 名、模块名、关键实体）但未互链的页面

对于每个应该添加反向引用的页面：
- 在其「资源导航」表中添加指向新文档的链接
- 更新其 frontmatter 的 `updated` 日期

**范围限制**：最多更新 5 个相关页面，避免过度扩散。

### 6.8 追加操作日志

在 `wiki/log.md` 的 `<!-- LOG_START -->` 下方插入一行：

```
| YYYY-MM-DD | CREATE/UPDATE | <category>/<slug>.md | add-wiki | <一句话说明> |
```

### 7. 输出摘要

完成后告知用户：

- 文档路径（可点击）
- 一句话摘要
- 更新了哪些索引文件
- 级联更新了哪些页面的交叉引用
- 如果是更新模式，说明变更内容

## 14 个 SEA 核心仓库参考

创建 services 类文档时，参考 CLAUDE.md 中的代码仓库映射表确定仓库名和 slug 的对应关系。

## 示例

```
用户：/knowledge-add-wiki sms_api 仓库概览
→ 分析 ~/go/src/code.byted.org/oec/sms_api/
→ 生成 wiki/services/sms-api.md
→ 更新 wiki/services/_index.md 和 wiki/_index.md

用户：/knowledge-add-wiki 商品审核流程
→ category = modules 或 workflows（需判断）
→ 调研相关代码和文档
→ 生成 wiki/modules/product-audit.md

用户：/knowledge-add-wiki EventBus 使用指南
→ category = infrastructure
→ 生成 wiki/infrastructure/eventbus.md
```
