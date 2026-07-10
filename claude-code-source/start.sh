#!/bin/bash
# Launch claude-code-source in interactive mode
cd "$(dirname "$0")"

# Load .env file if it exists (for local development)
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

# Validate required environment variables
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "Error: ANTHROPIC_API_KEY is not set. Set it via environment or .env file." >&2
  exit 1
fi

export ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-}"
export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-}"
export NODE_ENV=production
export CLAUBBIT=1
export USE_BUILTIN_RIPGREP=0
export DISABLE_INTERLEAVED_THINKING=1
export DISABLE_PROMPT_CACHING=1

exec node --no-warnings --import tsx/esm --import ./shims/cjs-extensions.mjs --loader ./shims/loader.mjs run.ts "$@"
