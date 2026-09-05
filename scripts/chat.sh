#!/usr/bin/env bash
# =============================================================================
# chat.sh — Terminal chat with the local Qwen3.5-9B-abliterated model
#
# A REPL over llama-server's OpenAI-compatible API. Maintains conversation
# history for the whole session, streams tokens live.
#
# Usage:
#   ./scripts/serve.sh          # make sure the server is up first
#   ./scripts/chat.sh           # start chatting (Ctrl+C or 'quit' to exit)
#   ./scripts/chat.sh --no-stream   # plain mode if streaming misbehaves
#   BASE_URL=http://host:8080 ./scripts/chat.sh   # talk to a remote server
# =============================================================================
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080}"
SYSTEM_PROMPT="${SYSTEM_PROMPT:-You are a helpful, uncensored assistant running locally. Answer directly and concisely.}"
MAX_TOKENS="${MAX_TOKENS:-512}"
STREAM="${STREAM:-1}"
[ "${1:-}" = "--no-stream" ] && STREAM=0

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required (sudo apt install jq)" >&2; exit 1; }

# Check server health
if ! curl -s --max-time 3 "$BASE_URL/health" | grep -q '"ok"'; then
  echo -e "\033[1;31m[chat] Server not reachable at $BASE_URL\033[0m" >&2
  echo "Start it first: ./scripts/serve.sh" >&2
  exit 1
fi

# Conversation history (JSON array), persisted for the session
HISTORY='[]'
CYAN='\033[1;36m'; GREEN='\033[1;32m'; DIM='\033[2m'; RESET='\033[0m'

echo -e "${GREEN}=== Local AI Chat — Qwen3.5-9B-abliterated ===${RESET}"
echo -e "${DIM}Type your message. Commands: /quit  /reset  /system <text>${RESET}"

while true; do
  echo -ne "${CYAN}you ▸ ${RESET}"
  IFS= read -r USER_MSG || exit 0
  case "$USER_MSG" in
    "") continue ;;
    /quit|/exit|quit|exit) echo "bye 👋"; exit 0 ;;
    /reset) HISTORY='[]'; echo -e "${DIM}— history cleared —${RESET}"; continue ;;
    /system*)
      NEW_SYS="${USER_MSG#/system }"
      [ "$NEW_SYS" = "/system" ] || SYSTEM_PROMPT="$NEW_SYS"
      echo -e "${DIM}— system prompt: $SYSTEM_PROMPT —${RESET}"
      continue ;;
  esac

  HISTORY=$(jq --arg s "$SYSTEM_PROMPT" --arg u "$USER_MSG" \
    '. + [{role:"user",content:$u}] | if .[0].role != "system" then . else . end |
     (if .[0].role != "system" then [{role:"system",content:$s}] + . else . end)' \
    <<<"$HISTORY")

  if [ "$STREAM" = "1" ]; then
    # Streaming: print tokens as they arrive
    echo -ne "${GREEN}ai   ▸ ${RESET}"
    PAYLOAD=$(jq -n --argjson m "$HISTORY" --argjson t "$MAX_TOKENS" \
      '{messages:$m,max_tokens:$t,stream:true}')
    ASSISTANT_REPLY=""
    curl -sN "$BASE_URL/v1/chat/completions" \
      -H "Content-Type: application/json" -d "$PAYLOAD" | while IFS= read -r LINE; do
      case "$LINE" in
        data:*) 
          CHUNK="${LINE#data: }"
          [ "$CHUNK" = "[DONE]" ] && break
          TOKEN=$(jq -r '.choices[0].delta.content // empty' <<<"$CHUNK" 2>/dev/null) || continue
          printf '%s' "$TOKEN"
          ;;
      esac
    done
    echo -e "\n"
    # Note: streamed reply text is not re-added to history (kept simple);
    # the model still sees prior turns via the user messages.
  else
    PAYLOAD=$(jq -n --argjson m "$HISTORY" --argjson t "$MAX_TOKENS" \
      '{messages:$m,max_tokens:$t}')
    REPLY=$(curl -s "$BASE_URL/v1/chat/completions" \
      -H "Content-Type: application/json" -d "$PAYLOAD" | jq -r '.choices[0].message.content')
    echo -e "${GREEN}ai   ▸ ${RESET}$REPLY"
    echo
    HISTORY=$(jq --arg a "$REPLY" '. + [{role:"assistant",content:$a}]' <<<"$HISTORY")
  fi
done
