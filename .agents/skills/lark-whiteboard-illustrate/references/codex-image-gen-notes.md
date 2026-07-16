# Codex CLI 内置 image_gen 工具 — 实战笔记

## 它到底是什么

Codex CLI（`codex` 命令）登录 ChatGPT Plus 后会自动启用一个内置工具 `image_gen.imagegen({ prompt?: string | null })`，**和 chatgpt.com 网页里的"画图"按钮调用同一个后端**。

## 关键事实

| 问题 | 答案 |
|---|---|
| 后端模型是什么？ | Codex 自己也说"不知道"——tool spec 没暴露模型名。chatgpt.com 当前用的图像模型就是它（OpenAI 没把版本号写在 tool spec 里）。要确认到具体 model 字段需要抓包 |
| 是不是 GPT Image 2.0？ | 大概率是 / 接近——chatgpt.com 网页"画图"功能背后就是 OpenAI 最新的图像模型，"Image 2.0"是营销名 |
| 走什么计费？ | **ChatGPT Plus 月度订阅配额**，不是 OpenAI API 单独计费 |
| 单张 token 消耗？ | 实测 ~15-30k tokens（含输入图理解 + 输出图生成） |
| 输出图分辨率？ | 默认 1672 × 941（接近 16:9），通过 prompt 里写"16:9 横版"可以引导 |
| 文件落盘在哪？ | `~/.codex/generated_images/<thread_id>/ig_<hash>.png` |

## 调用模式

```bash
codex exec \
    --image ./input.png \              # 喂参考图（必须是相对路径或脚本 cd 后的路径）
    --skip-git-repo-check \             # 工作目录非 git 时必加
    --full-auto \                       # 自动确认 + 沙盒执行 model 生成的命令
    "<prompt>"
```

### 重要 flag 解释

- `--image <file>` — 把参考图（你想"重画"的源图）喂给 codex。**必须是相对路径或当前 cwd 下的文件**，否则 codex 报 unsafe path
- `--skip-git-repo-check` — 不在 git repo 里跑必加，否则报错
- `--full-auto` — 等价于 sandbox=workspace-write + 自动批准。让 codex 能自己 `cp` 生成的图、保存到当前目录
- 不需要 `-c model=...` — image_gen 工具不受文本模型选择影响

### prompt 必须包含

1. **生成什么**：基于附图的什么主题、什么风格
2. **保存路径**：`保存到当前目录的 ./xxx.png`（让 codex 自己 cp 出来）
3. **明确禁用 API**：避免 codex 回退到写 Python 调付费 OpenAI API
   ```
   重要：用你内置的 image_gen 工具生成，不要写 Python 调付费 API。
   我希望走 ChatGPT Plus 配额而不是 API 计费。
   ```

## 常见 gotchas

### 1. codex 不在 git repo 报错

```
Error: not in a git repository
```

解决：

```bash
codex exec --skip-git-repo-check --full-auto ...
```

### 2. codex 说"已保存"但 cwd 找不到 png

Codex 自己输出里会有：

```
exec /bin/zsh -lc 'cp ~/.codex/generated_images/<thread>/ig_xxx.png ./vivid.png && ls -lh ./vivid.png'
```

如果这条 cp 没执行（旧版 codex / sandbox 拒绝写），手动 fallback：

```bash
LATEST=$(find ~/.codex/generated_images -name 'ig_*.png' -newer ./board.png 2>/dev/null | sort | tail -1)
[ -n "$LATEST" ] && cp "$LATEST" ./vivid.png
```

### 3. codex 用了 Python 调 API（绕过）

如果 codex 在没有内置 image_gen 时（例如旧版本 / 未登录 ChatGPT），它**会自己写 Python 调 OpenAI API**——这会扣 API 钱。

验证 codex 用的是内置工具的方法：在 prompt 里加：

```
重要：用你内置的 image_gen 工具生成，不要写 Python/curl 代码去调付费的 OpenAI API。
如果你确实没有内置图像生成能力，请明确告诉我"不知道"，不要尝试任何付费 API 调用。
```

执行后看 codex 输出里是否有 `image_gen.imagegen(...)` 调用 — 有就是内置工具。

### 4. ~/.codex 路径问题

`~/.codex/generated_images/` 在 macOS / Linux 都成立，Windows 上是 `%USERPROFILE%\.codex\`。脚本里用 `${CODEX_HOME:-$HOME/.codex}` 兼容。

### 5. 中文文字糊 / 节点标签错位

image_gen 对长 CJK 文字标签的 OCR/渲染弱。三个缓解策略：

- 标签控制在 ≤ 12 个字，用空格分隔英文 + 中文
- 用 `cartoon-isometric` 风格让模型把文字画进 UI mockup（按钮 / 卡片标题），而不是悬浮 label
- 重要标签后面加上短英文别名，例：`Browser Agent (BA)`

### 6. token 消耗超出 ChatGPT Plus 月度配额

单张 ~15-30k tokens，Plus 用户月度配额（限速版）应该足够每月几十张。如果触顶：

- 等月度重置（每月 1 号 / 订阅日）
- 降级到 `nano banana pro` (`gemini-3-pro-image-preview`)，需 `GEMINI_API_KEY`，~$0.04/ 张付费
- 临时去 chatgpt.com 网页手动画一张然后 download

## 验证 codex 状态

```bash
codex --version              # codex-cli 0.125.0+
codex login status           # 应显示 "Logged in using ChatGPT"
```

如果显示 "Not logged in"：用户需要跑 `codex login`（浏览器流程，~30 秒）。**不要**让用户配 OPENAI_API_KEY，那是另一套付费路径。

## 输入图大小建议

- 飞书画板预览图通常 100-200KB（mermaid 渲染），ok
- 太小（< 50KB）模型可能识别不清节点；太大（> 5MB）codex 可能拒绝
- 如果原画板分辨率太高，先 `pip install pillow` 然后：
  ```python
  from PIL import Image
  img = Image.open('board.png')
  img.thumbnail((2048, 2048))
  img.save('board.png')
  ```

## 实测案例（来自 SE 文档生产记录）

| 画板主题 | tokens | 单次生成耗时 | 满意度 |
|---|---|---|---|
| Nike 6 步购物 + CDP Listener | 17.9k | ~45s | 高（cartoon-isometric） |
| 路径 A/B 双路径架构图 | 21.6k | ~60s | 高 |
| Skill 三件套（Coding Agent + LLM + Skill）| 14.8k | ~30s | 高 |
| 同 3 张的 minimalist 重画 | 21k / 22.6k / 29.6k | ~50s 平均 | 中（用户偏好 cartoon 版本）|

平均一次成功生成 ≈ 20k tokens，60 秒。
