---
name: knowledge-lint
description: |
  知识库健康检查。检测 frontmatter 缺失、索引不一致、断链、过期内容、覆盖度不足、孤立页面等问题。
  触发词："knowledge-lint"、"检查知识库"、"健康检查"、"knowledge base health"、"/knowledge-lint"。
  建议每周或每 10 次 wiki 变更后执行一次。
---

# /knowledge-lint — 知识库健康检查

对 SEA Pearl 知识库执行全面健康检查，输出结构化报告。

## 检查项

### 1. Frontmatter 完整性

扫描 `wiki/` 下所有 `.md` 文件（排除 `_index.md` 和 `log.md`）：

```
Glob: wiki/**/*.md（排除 _index.md、log.md）
```

每个文件必须包含以下 YAML frontmatter 字段：
- `title`（string）
- `category`（必须是 7 个合法值之一：architecture / services / modules / infrastructure / workflows / concepts / external）
- `tags`（array）
- `created`（YYYY-MM-DD 格式）
- `updated`（YYYY-MM-DD 格式）

**报告**：列出缺失字段的文件和具体缺失项。

### 2. 索引一致性

双向检查：

#### 正向：wiki 页面 → 索引
- 每个 `wiki/<category>/<slug>.md` 必须在 `wiki/<category>/_index.md` 中有对应条目
- 每个 `wiki/<category>/<slug>.md` 必须在 `wiki/_index.md` 中有对应条目

#### 反向：索引 → wiki 页面
- `_index.md` 中引用的每个 `(slug.md)` 链接必须对应一个实际存在的文件

**检查方法**：
```
Read: wiki/_index.md
Glob: wiki/<category>/*.md（对每个 category）
对比两个列表，报告差异
```

### 3. 交叉引用与断链检测

扫描所有 wiki 页面中的资源导航表和正文链接：
- `[text](../xxx/yyy.md)` 形式的相对路径 → 检查目标文件存在
- `[text](zzz.md)` 形式的同目录链接 → 检查目标文件存在

**报告**：列出断链的源文件、链接文本、目标路径。

### 4. 内容新鲜度

根据 frontmatter 中的 `updated` 字段计算页面年龄：

| 状态 | 条件 | 标记 |
|------|------|------|
| 正常 | updated < 90 天 | - |
| 可能过期 | 90 天 <= updated < 180 天 | Warning |
| 很可能过期 | updated >= 180 天 | Error |

### 5. 覆盖度分析

#### Services 覆盖率

参照 CLAUDE.md 中 14 个 SEA 核心仓库列表，统计已创建 wiki 的仓库数量：

```
期望：sms-api, sea-operation-seller, sea-operation-product, sea-operation-order,
      sea-operation-aftersale, sea-operation-finance, sea-operation-logistics,
      sea-operation-promotion, sea-operation-governance, sea-operation-common,
      sea-operation-data, seller-extended, pearl-faas, pearl-config
      + insights-export-faas（已有但不在 14 个核心列表中）
```

#### 空分类检测

检查每个 category 目录下是否有实际文档（排除 `_index.md`）。

#### Raw 来源覆盖

如果 `raw/` 目录存在，统计：
- raw 文件总数
- 已关联 wiki 页面的 raw 文件数
- 未关联（孤立）的 raw 文件

### 6. 孤立内容检测

- **孤立 wiki 页面**：不被任何 `_index.md` 或其他 wiki 页面引用的文件
- **孤立 raw 文件**：`raw/_manifest.md` 中未被任何 wiki 页面的 `sources` 字段引用的文件
- **根目录残留**：项目根目录下不属于 wiki/ 或 raw/ 的 `.md` 文件（排除 README.md、CLAUDE.md）

## 输出格式

```markdown
## 知识库健康报告

**检查时间**：YYYY-MM-DD | **页面总数**：N | **分类数**：7

### 概览

| 指标 | 值 |
|------|-----|
| Wiki 页面 | N 篇 |
| Raw 来源 | N 个 |
| Services 覆盖率 | X/14 (Y%) |
| 最近更新 | YYYY-MM-DD |
| 最久未更新 | YYYY-MM-DD (Z 天前) |

### 通过项

- Frontmatter 完整性 — N/N 页面合规
- 索引一致性 — 全部一致
- ...

### 警告

- `concepts/` 分类为空 — 建议添加基础业务概念
- `wiki/xxx.md` 已 95 天未更新 — 考虑检查是否过期
- ...

### 错误

- `wiki/xxx.md` 资源导航表中 `../yyy/zzz.md` 指向不存在的文件
- ...

### 建议下一步

1. 优先补充 sms_api (BFF 入口) 的 wiki 文档
2. ...
```

## 执行注意事项

- 只读操作，不修改任何文件
- 如果发现问题，只报告不自动修复（用户决定是否修复）
- 检查完成后在 `wiki/log.md` 追加一行 LINT 记录

## 示例

```
用户：/knowledge-lint
→ 扫描 wiki/ 下所有文件
→ 执行 6 项检查
→ 输出结构化健康报告

用户：检查一下知识库的健康状况
→ 自动触发 /knowledge-lint
→ 同上
```
