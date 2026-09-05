#!/usr/bin/env bash
# =============================================================================
# serve.sh — Start the Qwen3.5-9B-abliterated model as a background server
#
# After it's up, you can talk to the AI via:
#   1. Web UI:        http://127.0.0.1:8080  (open in browser, built into llama-server)
#   2. REST API:      POST http://127.0.0.1:8080/v1/chat/completions
#   3. scripts/chat.sh (terminal chat)
#
# Usage:
#   ./scripts/serve.sh            # start server (exits after server is ready)
#   ./scripts/serve.sh --logs     # start and follow logs (Ctrl+C = stop following)
#   ./scripts/serve.sh --stop     # stop the server
#   ./scripts/serve.sh --status   # is it running?
#
# Reuses the same model/build paths as run-model.sh.
# =============================================================================
set -euo pipefail

MODEL_REPO="lukey03/Qwen3.5-9B-abliterated-GGUF"
MODEL_FILE="Qwen3.5-9B-abliterated-Q4_K_M.gguf"
MODEL_URL="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
MODEL_DIR="${MODEL_DIR:-$HOME/.cache/qwen-uncensored}"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
LLAMA_DIR="${LLAMA_DIR:-$HOME/.cache/llama.cpp}"
PID_FILE="$MODEL_DIR/server.pid"
LOG_FILE="$MODEL_DIR/server.log"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
THREADS="${THREADS:-4}"
CTX_SIZE="${CTX_SIZE:-4096}"

log()  { printf '\033[1;32m[serve]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[serve] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

server_running() {
  [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

ensure_model_and_llamacpp() {
  # Same bootstrap as run-model.sh: build llama.cpp + download model if needed
  [ "$(uname -m)" = "x86_64" ] || fail "x86_64 required"
  command -v curl >/dev/null || fail "curl is required"

  LLAMA_SERVER="$LLAMA_DIR/build/bin/llama-server"
  if [ ! -x "$LLAMA_SERVER" ]; then
    log "Building llama.cpp (first run only)..."
    if ! command -v cmake >/dev/null; then
      sudo apt-get update -y && sudo apt-get install -y build-essential cmake git
    fi
    mkdir -p "$(dirname "$LLAMA_DIR")"
    [ -d "$LLAMA_DIR" ] || git clone --depth 1 https://github.com/ggml-org/llama.cpp "$LLAMA_DIR"
    cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" -DGGML_NATIVE=ON
    cmake --build "$LLAMA_DIR/build" --config Release -j"$THREADS"
  fi

  mkdir -p "$MODEL_DIR"
  if [ ! -s "$MODEL_PATH" ]; then
    log "Downloading model (~5.6 GB)..."
    curl -L --fail --retry 3 --retry-delay 5 -C - \
      --progress-bar -o "$MODEL_PATH.part" "$MODEL_URL"
    mv "$MODEL_PATH.part" "$MODEL_PATH"
  fi
}

case "${1:-}" in
  --stop)
    if server_running; then
      kill "$(cat "$PID_FILE")" && rm -f "$PID_FILE"
      log "Server stopped."
    else
      log "Server is not running."
      rm -f "$PID_FILE"
    fi
    exit 0
    ;;
  --status)
    if server_running && curl -s --max-time 2 "http://$HOST:$PORT/health" | grep -q '"ok"'; then
      log "Running: http://$HOST:$PORT (pid $(cat "$PID_FILE"))"
    else
      log "Not running."
    fi
    exit 0
    ;;
  --logs)
    tail -f "$LOG_FILE"
    exit 0
    ;;
esac

if server_running; then
  log "Server already running: http://$HOST:$PORT (pid $(cat "$PID_FILE"))"
  exit 0
fi

ensure_model_and_llamacpp

log "Starting llama-server on http://$HOST:$PORT ..."
nohup "$LLAMA_DIR/build/bin/llama-server" \
  -m "$MODEL_PATH" -c "$CTX_SIZE" -t "$THREADS" --no-warmup \
  --host "$HOST" --port "$PORT" \
  >"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

# Wait until healthy (model load takes ~30-60s cold)
for i in $(seq 1 180); do
  if curl -s --max-time 2 "http://$HOST:$PORT/health" 2>/dev/null | grep -q '"ok"'; then
    log "✅ AI is up and talking at:"
    log "   Web UI:  http://$HOST:$PORT"
    log "   API:     POST http://$HOST:$PORT/v1/chat/completions"
    log "   Chat:    ./scripts/chat.sh"
    log "   Logs:    ./scripts/serve.sh --logs   |   Stop: ./scripts/serve.sh --stop"
    exit 0
  fi
  if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    fail "server process died — check $LOG_FILE"
  fi
  sleep 1
done
fail "server not healthy after 180s — check $LOG_FILE"
