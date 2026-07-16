# Prompt 模板（4 个风格预设）

每个 style 的 prompt 由 3 段组成：**风格基底** + **主题描述**（调用方填）+ **关键节点和流向**（调用方填）+ **保存指令**（脚本固定）。

---

## cartoon-isometric（默认）—— 给非技术受众看的"生动版"

```
基于附图，重新生成一张更生动的等距 (isometric) 3D 风格插图。

【整体要求】
- 保留原图的全部信息（流程顺序、节点名称、连线方向、关键标签）
- 用拟人化机器人 / 角色化场景代替抽象方框
  - 机器人坐在电脑前操作、机器人在 IDE 敲代码、机器人查看手册等
- 每个核心节点配一个具体的视觉场景：
  - 浏览器步骤 → 真的浏览器 UI mockup（带具体按钮如 "Add to Bag" / "Checkout"）
  - 手册 / 知识 → 厚厚的书本封面
  - 评分 / 评估 → 评分卡 / 仪表盘
  - 对话 → 飞书风格的 IM 对话气泡
- 保留所有节点的中英文文字标签（标签长度尽量 ≤ 12 个字）
- 整体配色协调（避免彩虹），背景干净，明暗对比明确
- 横版 16:9
- 微妙 3D 光影 + drop shadow，但避免过度渲染

【主题】
{topic}

【关键节点和流向】
{key_nodes}
```

---

## minimalist-isometric —— editorial-grade 简约版

```
基于附图，重新生成一张简约美观的等距 (isometric) 3D 信息图。

【风格要求 — 重要】
- editorial-grade 简约信息图，**绝对不要画机器人 / 人物 / 表情**
- 每个节点用一个简单的 3D 几何卡片或图标（购物车 / 标签 / 信用卡 / 锁 / 对勾 / 文档 / 数据库 / 仪表盘）
- 不要画详细的 UI mockup 或屏幕里的代码
- 大量留白，节点之间空间充足，文字标签清晰可读
- 配色克制：最多 3-4 个主色（蓝 / 绿点缀 / 灰白为主），避免彩虹
- 微妙 3D 光影但不要电影渲染
- 不要装饰小物件（流体 / 火花 / 闪电 / 星星等）
- 所有节点中英文标签保留
- 横版 16:9

【主题】
{topic}

【关键节点和流向】
{key_nodes}
```

---

## hand-drawn-marker —— 白板手绘 / brainstorm 感

```
基于附图，重新生成一张白板手绘风格的流程图。

【风格要求】
- 白板背景（轻微纸纹）+ marker 笔触
- 节点用手绘风格的方框 / 圆角矩形 / 圆形，线条略不规则但清晰
- 配色限制在 3 种 marker 颜色：黑 / 蓝 / 红（强调节点用红）
- 文字用手写体（中英文都要可读）
- 箭头用手绘箭头，可以略带波浪感
- 不要 3D / 渐变 / 阴影
- 横版 16:9
- 视觉感受是"工程师在白板上推演"，不是"PPT 配图"

【主题】
{topic}

【关键节点和流向】
{key_nodes}
```

---

## cinematic-3d —— 发布物料 / 营销

```
基于附图，重新生成一张电影感 3D 渲染插图。

【风格要求】
- 全屏 cinematic 3D 渲染，强光影、景深、体积光
- 每个节点是有质感的 3D 物件（玻璃 / 金属 / 发光材质都可）
- 主体居中、背景柔焦
- 配色饱和度高但协调（深蓝 + 紫 + 金，或深绿 + 青 + 白）
- 所有节点保留中英文标签，标签放在节点底部或浮在物件附近
- 横版 16:9
- 适合做发布会主视觉 / 营销页面 hero image

【主题】
{topic}

【关键节点和流向】
{key_nodes}
```

---

## 通用尾巴（脚本拼接，用户不用管）

每个 style 的 prompt 末尾会自动追加：

```
把生成的图保存到当前目录 ./{output_name}.png。

重要：用你内置的 image_gen 工具生成，不要写 Python/curl 代码去调付费的 OpenAI API ——
我希望走 ChatGPT Plus 配额而不是走 API 计费。如果你确实没有内置图像生成能力，
请明确告诉我，不要尝试任何付费 API 调用。
```

---

## 调用方填什么

### `{topic}`（一两句话）

讲清这张画板"讲的是什么"。例：

> 一个 AI agent 在 Nike 网站模拟下单的 6 步流程，过程中 CDP Listener 抓到 ViewContent / AddToCart / InitiateCheckout 三个 Pixel 事件入库给 Grading Agent 评分。

### `{key_nodes}`（项目符号清单）

列出每个节点的中英文名 + 简短描述。例：

```
- ① browser_navigate（商品详情页）
- ② browser_click（选 Size 9）
- ③ browser_click（Add to Bag）
- ④ browser_click（View Bag → 购物车页）
- ⑤ browser_click（Checkout）
- ⑥ guest checkout（停在支付页之前）
- CDP Listener（analytics.tiktok.com / fb-tr）→ ViewContent / AddToCart / InitiateCheckout
- 入库 → Grading Agent 评分
```

如果调用方没提供 `{key_nodes}`，可以用 `lark-cli docs +fetch --keyword "<画板上方标题>"` 抽取上下文文字喂给 codex 自己推断。
