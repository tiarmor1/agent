#!/usr/bin/env bash
# illustrate.sh — 把飞书画板用 Codex CLI 的内置 image_gen 工具重画成生动插图，并插回飞书文档
#
# Usage:
#   illustrate.sh \
#       --doc <doc_url_or_token> \
#       --board-token <wbcn_xxx> \
#       --anchor "<目标锚点文字>" \
#       [--position before|after]    # default: before（插在锚点之前）
#       [--style cartoon-isometric|minimalist-isometric|hand-drawn-marker|cinematic-3d]
#                                     # default: cartoon-isometric
#       [--topic "<主题描述>"]         # 一两句话讲清画板讲什么
#       [--key-nodes "<节点列表>"]     # 多行字符串，每行一个节点
#       [--prompt-extra "<追加要求>"]  # 在 style 模板基础上追加细节
#       [--prompt-file <path>]        # 完全自定义 prompt（覆盖 style 模板）
#       [--output-dir <dir>]          # default: /tmp/whiteboard-illustrate-<timestamp>
#       [--keep-tmp]                  # 保留中间 board.png / vivid.png
#       [--dry-run]                   # 只生图不插入飞书
#
# Returns (stdout, JSON):
#   {
#     "board_preview_png": "...",
#     "vivid_png": "...",
#     "doc_id": "...",
#     "inserted_block_id": "...",     # 仅在非 --dry-run
#     "inserted_file_token": "...",
#     "tokens_used_approx": "..."     # codex 报告的 token 用量
#   }

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPTS_FILE="$SKILL_DIR/references/prompts.md"

# --- defaults ---
POSITION="before"
STYLE="cartoon-isometric"
TOPIC=""
KEY_NODES=""
PROMPT_EXTRA=""
PROMPT_FILE=""
KEEP_TMP=0
DRY_RUN=0
OUTPUT_DIR="/tmp/whiteboard-illustrate-$(date +%Y%m%dT%H%M%S)"
DOC=""
BOARD_TOKEN=""
ANCHOR=""

# --- parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --doc) DOC="$2"; shift 2 ;;
        --board-token) BOARD_TOKEN="$2"; shift 2 ;;
        --anchor) ANCHOR="$2"; shift 2 ;;
        --position) POSITION="$2"; shift 2 ;;
        --style) STYLE="$2"; shift 2 ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --key-nodes) KEY_NODES="$2"; shift 2 ;;
        --prompt-extra) PROMPT_EXTRA="$2"; shift 2 ;;
        --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
        --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        --keep-tmp) KEEP_TMP=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            grep '^#' "$0" | head -40
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# --- validate ---
[[ -z "$DOC" ]] && { echo "ERROR: --doc required" >&2; exit 1; }
[[ -z "$BOARD_TOKEN" ]] && { echo "ERROR: --board-token required" >&2; exit 1; }
if (( DRY_RUN == 0 )); then
    [[ -z "$ANCHOR" ]] && { echo "ERROR: --anchor required (unless --dry-run)" >&2; exit 1; }
fi

case "$POSITION" in
    before|after) ;;
    *) echo "ERROR: --position must be before|after" >&2; exit 1 ;;
esac

case "$STYLE" in
    cartoon-isometric|minimalist-isometric|hand-drawn-marker|cinematic-3d) ;;
    *) echo "ERROR: --style must be cartoon-isometric|minimalist-isometric|hand-drawn-marker|cinematic-3d" >&2; exit 1 ;;
esac

# --- preflight ---
command -v lark-cli >/dev/null || { echo "ERROR: lark-cli not in PATH" >&2; exit 1; }
command -v codex >/dev/null || { echo "ERROR: codex CLI not in PATH" >&2; exit 1; }

CODEX_LOGIN=$(codex login status 2>&1 | head -1)
if [[ "$CODEX_LOGIN" != *"Logged in using ChatGPT"* ]]; then
    echo "ERROR: codex must be logged in via ChatGPT (run: codex login)" >&2
    echo "       current status: $CODEX_LOGIN" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# --- Step 1: pull whiteboard preview ---
echo "[1/4] Pulling whiteboard preview to $OUTPUT_DIR/board.png ..." >&2
lark-cli whiteboard +query \
    --whiteboard-token "$BOARD_TOKEN" \
    --output_as image \
    --output ./board.png \
    --as user >/dev/null

[[ ! -s ./board.png ]] && { echo "ERROR: board.png is empty" >&2; exit 1; }

# --- Step 2: build prompt ---
echo "[2/4] Building prompt (style=$STYLE) ..." >&2

if [[ -n "$PROMPT_FILE" ]]; then
    BASE_PROMPT=$(cat "$PROMPT_FILE")
else
    # extract the style block from prompts.md
    BASE_PROMPT=$(awk -v style="$STYLE" '
        $0 ~ "^## " style {capture=1; next}
        capture && /^---$/ {capture=0}
        capture && /^```$/ {in_code = !in_code; next}
        capture && in_code {print}
    ' "$PROMPTS_FILE")

    # substitute placeholders
    BASE_PROMPT="${BASE_PROMPT//\{topic\}/$TOPIC}"
    BASE_PROMPT="${BASE_PROMPT//\{key_nodes\}/$KEY_NODES}"
fi

FULL_PROMPT="$BASE_PROMPT

${PROMPT_EXTRA}

把生成的图保存到当前目录的 ./vivid.png。

重要：用你内置的 image_gen 工具生成，不要写 Python/curl 代码去调付费的 OpenAI API ——
我希望走 ChatGPT Plus 配额而不是走 API 计费。如果你确实没有内置图像生成能力，请明确告诉我，
不要尝试任何付费 API 调用。"

# --- Step 3: invoke codex ---
echo "[3/4] Calling codex (this may take ~30-60s)..." >&2

CODEX_LOG="$OUTPUT_DIR/codex.log"
codex exec \
    --image ./board.png \
    --skip-git-repo-check \
    --full-auto \
    "$FULL_PROMPT" 2>&1 | tee "$CODEX_LOG" >/dev/null || true

# Find the generated image
if [[ -s ./vivid.png ]]; then
    VIVID_PNG="$OUTPUT_DIR/vivid.png"
else
    # fallback: find latest generated image newer than board.png
    LATEST=$(find "${CODEX_HOME:-$HOME/.codex}/generated_images" -name 'ig_*.png' -newer ./board.png 2>/dev/null | sort | tail -1 || true)
    if [[ -n "$LATEST" && -s "$LATEST" ]]; then
        cp "$LATEST" ./vivid.png
        VIVID_PNG="$OUTPUT_DIR/vivid.png"
    else
        echo "ERROR: codex did not produce an image. See $CODEX_LOG for details." >&2
        exit 1
    fi
fi

TOKENS_USED=$(awk '/^tokens used$/ {getline; print; exit}' "$CODEX_LOG" 2>/dev/null | tr -d '\n' || echo "?")
[[ -z "$TOKENS_USED" ]] && TOKENS_USED="?"

# --- Step 4: insert into Lark doc ---
if (( DRY_RUN == 1 )); then
    cat <<EOF
{
  "board_preview_png": "$OUTPUT_DIR/board.png",
  "vivid_png": "$VIVID_PNG",
  "doc_id": "$DOC",
  "tokens_used_approx": "$TOKENS_USED",
  "dry_run": true
}
EOF
    exit 0
fi

echo "[4/4] Inserting into Lark doc ..." >&2

INSERT_FLAGS=()
[[ "$POSITION" == "before" ]] && INSERT_FLAGS+=(--before)

INSERT_RESULT=$(lark-cli docs +media-insert \
    --doc "$DOC" \
    --type image \
    --file ./vivid.png \
    --selection-with-ellipsis "$ANCHOR" \
    "${INSERT_FLAGS[@]}" \
    --align center \
    --caption "等距 3D 风格插图（codex CLI 生成 · style=$STYLE）" \
    --as user)

BLOCK_ID=$(echo "$INSERT_RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["block_id"])')
FILE_TOKEN=$(echo "$INSERT_RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["data"]["file_token"])')

cat <<EOF
{
  "board_preview_png": "$OUTPUT_DIR/board.png",
  "vivid_png": "$VIVID_PNG",
  "doc_id": "$DOC",
  "inserted_block_id": "$BLOCK_ID",
  "inserted_file_token": "$FILE_TOKEN",
  "tokens_used_approx": "$TOKENS_USED",
  "style": "$STYLE",
  "anchor": "$ANCHOR",
  "position": "$POSITION"
}
EOF

# --- cleanup ---
if (( KEEP_TMP == 0 )); then
    rm -f "$OUTPUT_DIR/codex.log"
    # keep board.png and vivid.png for manual inspection
fi
