---
name: lark-whiteboard-illustrate
description: 把飞书文档里的画板（mermaid / DSL 渲染的工程图）通过 Codex CLI 内置 image_gen 工具（GPT Image，走 ChatGPT Plus 配额，零 API 成本）重画成更生动的等距 3D 插图，然后插入到原画板下方或上方。当用户提到"画板太工程化 / 把画板变生动 / 给画板配一张配图 / illustrate this whiteboard / 用 GPT Image / 用 nano banana 重画画板"等场景时使用。
metadata:
  requires:
    bins: ["lark-cli", "codex"]
---

# lark-whiteboard-illustrate

把飞书文档里的"工程感"mermaid / DSL 画板，用 **Codex CLI 内置 `image_gen` 工具**（GPT Image，走 ChatGPT Plus 月度配额，**零 API 成本**）重画成生动的等距 3D 插图，插入到原画板下方或上方。

> ⚠️ **前置条件**：先用 Read 工具读 [`../lark-shared/SKILL.md`](../lark-shared/SKILL.md)（lark-cli 认证）。如果 `codex login status` 不是"Logged in using ChatGPT"，告诉用户去跑 `codex login`，不要尝试用 OpenAI API key（那是另一套计费）。

## 核心 workflow（4 步）

### Step 1. 拉画板预览图

```bash
lark-cli whiteboard +query \
    --whiteboard-token <wbcn_xxx> \
    --output_as image \
    --output ./board.png \
    --as user
```

输出 PNG 到 `./board.png`，飞书服务端直接渲染（mermaid / PlantUML / DSL 都行）。

### Step 2. 拼 prompt → codex 内置 image_gen 生图

完整 prompt = **风格基底**（reference/prompts.md 里的 4 选 1）+ **主题描述**（用户提供 / 从画板上下文抽取）+ **关键节点列表**。

调用 codex（一定要带 `--image` 把画板预览图喂进去）：

```bash
codex exec \
    --image ./board.png \
    --skip-git-repo-check \
    --full-auto \
    "<完整 prompt>。把生成的图保存到当前目录 ./vivid.png。重要：用你内置的 image_gen 工具生成，不要写 Python 调付费 API。"
```

> **关键 gotchas**（详见 [`references/codex-image-gen-notes.md`](references/codex-image-gen-notes.md)）：
> - **codex 不支持 `--cd <abs_path>`**，会报 git repo 错。要么 `--skip-git-repo-check`，要么 `cd` 进去再跑
> - **codex 把生成的原图放在** `~/.codex/generated_images/<thread_id>/ig_<hash>.png`，要 `cp` 到 cwd 才好用
> - **codex 自己会做这步 cp**（如果 prompt 里说"保存到 ./vivid.png"），不需要后续手动找
> - 但保险起见，脚本可以二次确认：`find ~/.codex/generated_images -newer ./board.png -name '*.png' | head -1`
> - **token 消耗 ~15-30k 一张**，按 ChatGPT Plus 月度配额计费，不是 API

### Step 3. 找到生成的图

如果 codex 输出里能看到 `cp .../ig_xxx.png ./vivid.png` 就直接用 `./vivid.png`。

如果 codex 只在 `~/.codex/generated_images/` 留了图、没 cp 出来，自己 cp：

```bash
LATEST=$(find ~/.codex/generated_images -name 'ig_*.png' -newer ./board.png 2>/dev/null | sort | tail -1)
cp "$LATEST" ./vivid.png
```

### Step 4. 插入回飞书文档

用 `docs +media-insert` + `--selection-with-ellipsis` 锚定到画板上方/下方的某段确定的文字（标题或独特文本）。**`--before` = 插在锚点之前；省略 = 插在锚点之后**。

```bash
# 插在画板下方（锚定到下一节标题，--before）
lark-cli docs +media-insert \
    --doc <doc_url_or_token> \
    --type image \
    --file ./vivid.png \
    --selection-with-ellipsis "<画板下方一节的标题>" \
    --before \
    --align center \
    --caption "等距 3D 插图（codex CLI 生成）" \
    --as user
```

定位锚点选择策略：
- **画板下方插入** → 锚定到下一个 `# / ##` 标题或下一段稳定文字，`--before`
- **画板上方插入** → 锚定到本节内画板上方的稳定文字，省略 `--before`（即 after）
- 如果文档里同一段文字出现多次，用 `开头...结尾` 形式确保唯一性

## 一键脚本（推荐）

复杂场景由 Claude 直接编排上述 4 步；快速场景用脚本：

```bash
~/.claude/skills/lark-whiteboard-illustrate/scripts/illustrate.sh \
    --doc <doc_url_or_token> \
    --board-token <wbcn_xxx> \
    --anchor "<画板下方某段稳定文字>" \
    --position before \
    --style cartoon-isometric \
    --topic "你的主题描述（一两句话讲清画板讲什么）"
```

可选参数：
- `--prompt-extra "<追加要求>"` — 在 style 模板基础上追加细节要求
- `--prompt-file <path>` — 完全自定义 prompt（覆盖 style 模板）
- `--keep-tmp` — 保留中间 board.png / vivid.png 不清理
- `--dry-run` — 只生图不插入飞书

## 风格预设

详见 [`references/prompts.md`](references/prompts.md)。一句话总结：

| Style | 特点 | 适合场景 |
|---|---|---|
| `cartoon-isometric`（默认） | 拟人化机器人 + UI mockup + 流程图标 | 给非技术受众看的能力介绍、SE/产品对齐 |
| `minimalist-isometric` | 几何卡片 + 大量留白 + 克制配色 | editorial-grade 文档、向上汇报 |
| `hand-drawn-marker` | 白板手绘 / marker 笔触 | brainstorm / discussion notes |
| `cinematic-3d` | 电影渲染 / 强光影 | 发布物料 / 营销页 |

## Batch 模式

文档里有多个画板要批量处理时，让 Claude 用循环调脚本：

```bash
# 1. 先 fetch 文档 detail with-ids 找到所有 <whiteboard token=...> 块
# 2. 对每个 token + 它周围的标题：调一次 illustrate.sh
# 3. 跑完后建议把原 mermaid 画板挪到 doc 末尾的 "Appendix" section
#    （用 docs +update --api-version v2 --command block_move_after，
#    多个 move 要按目标位置从后往前，避免后面的 move 干扰前面已就位的块）
```

## 常见错误

| 症状 | 原因 | 解决 |
|---|---|---|
| `codex` 报 not in git repo | 工作目录非 git | 加 `--skip-git-repo-check` |
| codex 说"已保存"但找不到 png | codex 没 cp 到 cwd，只在 generated_images/ | 用 `find ~/.codex/generated_images -newer ./board.png` 找 |
| 生成的图风格不对 / 信息丢失 | prompt 太抽象 | 在 `--topic` / `--prompt-extra` 里把节点名 + 流向都列清楚 |
| 中文文字糊 | image_gen 对长 CJK 标签弱 | 标签写短一点；或用 `cartoon-isometric` 配 UI mockup（让模型把文字画进 UI 而不是节点 label） |
| `docs +media-insert` 报 unsafe path | --file 给了绝对路径 | 改成相对路径或 `cd` 到 png 所在目录再跑 |
| 锚点找不到 | 文字不唯一 | 改成 `开头...结尾` 长锚点 |

## 计费与配额

- **零 API 成本** — 用的是 ChatGPT Plus 订阅自带的 image_gen 配额（和 chatgpt.com 网页画图同源）
- 单张 ~15-30k tokens；ChatGPT Plus 月度配额内可批量使用
- 如果 codex 反馈"配额用尽"，等月度重置或临时降级到 `nano banana pro`（需要 GEMINI_API_KEY，付费）
- **不要**让 codex 写 Python 调 OpenAI API，prompt 里要明确禁止
