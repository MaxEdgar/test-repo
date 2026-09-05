#!/usr/bin/env bash
# =============================================================================
# run-model.sh — Download & run the uncensored Qwen3.5-9B-abliterated model
#
# Hardware target: 4 vCPU / 16 GB RAM / 14 GB SSD (x64 Ubuntu)
# Model: Qwen3.5-9B-abliterated Q4_K_M (~5.6 GB) — newest uncensored Qwen
#
# Usage:
#   ./scripts/run-model.sh              # interactive chat (llama-cli)
#   ./scripts/run-model.sh "prompt"     # one-shot prompt -> answer, then exit
#
# Requires: curl, build tools (installed automatically if missing, needs sudo)
# =============================================================================
set -euo pipefail

MODEL_REPO="lukey03/Qwen3.5-9B-abliterated-GGUF"
MODEL_FILE="Qwen3.5-9B-abliterated-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
MODEL_DIR="${MODEL_DIR:-$HOME/.cache/qwen-uncensored}"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
LLAMA_DIR="${LLAMA_DIR:-$HOME/.cache/llama.cpp}"

THREADS="${THREADS:-4}"
CTX_SIZE="${CTX_SIZE:-4096}"
PROMPT="${1:-}"

log()  { printf '\033[1;32m[run-model]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[run-model] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. Sanity checks -------------------------------------------------------
[ "$(uname -m)" = "x86_64" ] || fail "x86_64 required (found: $(uname -m))"
command -v curl >/dev/null || fail "curl is required (sudo apt install curl)"

# --- 1. Disk space guard (need ~7 GB free for model + llama.cpp build) ------
free_kb=$(df -Pk "$HOME" | awk 'NR==2 {print $4}')
if [ "$free_kb" -lt 7500000 ]; then
  fail "Less than ~7 GB free on $HOME partition (found $((free_kb / 1024)) MB free). Model is 5.6 GB."
fi

# --- 2. Build llama.cpp (CPU only, skipped if already built) -----------------
LLAMA_SERVER="$LLAMA_DIR/build/bin/llama-server"
LLAMA_CLI="$LLAMA_DIR/build/bin/llama-cli"
if [ ! -x "$LLAMA_CLI" ]; then
  log "Building llama.cpp (first run only, ~2-5 min)..."
  if ! command -v cmake >/dev/null || ! command -v make >/dev/null; then
    log "Installing build tools (cmake, build-essential)..."
    sudo apt-get update -y && sudo apt-get install -y build-essential cmake git
  fi
  mkdir -p "$(dirname "$LLAMA_DIR")"
  if [ -d "$LLAMA_DIR" ]; then
    git -C "$LLAMA_DIR" pull --ff-only || true
  else
    git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
  fi
  cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DGGML_NATIVE=ON
  cmake --build "$LLAMA_DIR/build" --config Release -j"$THREADS"
else
  log "llama.cpp already built: $LLAMA_CLI"
fi

# --- 3. Download model via curl (resumable, skipped if complete) -------------
mkdir -p "$MODEL_DIR"
if [ -f "$MODEL_PATH" ] && [ -s "$MODEL_PATH" ]; then
  log "Model already downloaded: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"
else
  log "Downloading $MODEL_FILE (~5.6 GB) from Hugging Face..."
  curl -L --fail --retry 3 --retry-delay 5 -C - \
    --progress-bar -o "$MODEL_PATH.part" "$MODEL_URL"
  mv "$MODEL_PATH.part" "$MODEL_PATH"
  log "Download complete: $(du -h "$MODEL_PATH" | cut -f1)"
fi

# --- 4. Run -------------------------------------------------------------------
COMMON_ARGS=(-m "$MODEL_PATH" -c "$CTX_SIZE" -t "$THREADS" --no-warmup)

if [ -n "$PROMPT" ]; then
  # One-shot: spin up server, ask, print answer, shut down.
  log "Starting llama-server on 127.0.0.1:8080 ..."
  "$LLAMA_SERVER" "${COMMON_ARGS[@]}" --host 127.0.0.1 --port 8080 &
  SERVER_PID=$!
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 1 120); do
    curl -s --max-time 2 http://127.0.0.1:8080/health | grep -q '"ok"' && break
    sleep 1
  done
  curl -s --fail http://127.0.0.1:8080/health | grep -q '"ok"' \
    || fail "server did not become healthy in 120s"
  log "Model loaded. Sending prompt..."
  curl -s http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg p "$PROMPT" \
      '{messages:[{role:"user",content:$p}],max_tokens:512}')" \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])"
else
  # Interactive chat (conversation mode uses the template embedded in the GGUF)
  exec "$LLAMA_CLI" "${COMMON_ARGS[@]}" --color -cnv
fi
