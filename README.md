# Local AI Model Runner — Uncensored Qwen on CPU

Runs the **Qwen3.5-9B-abliterated** (uncensored, abliterated) model entirely on CPU.

**Target hardware:** 4 vCPU · 16 GB RAM · 14 GB SSD · x64 Ubuntu

## Model

| | |
|---|---|
| Model | [Qwen3.5-9B-abliterated-GGUF](https://huggingface.co/lukey03/Qwen3.5-9B-abliterated-GGUF) |
| Quant | Q4_K_M (~5.6 GB) |
| Runtime | [llama.cpp](https://github.com/ggml-org/llama.cpp) (CPU, `-t 4`) |
| Download | plain `curl` from Hugging Face (public, no token needed) |
| Context | 4096 tokens |

## Run on your machine

```bash
./scripts/run-model.sh                # one-shot prompt -> answer
./scripts/run-model.sh "your prompt"  # same, with your prompt
```

First run: builds llama.cpp (~2–5 min) and downloads the model (~5.6 GB). Later runs start instantly.

Env overrides: `THREADS`, `CTX_SIZE`, `MODEL_DIR`, `LLAMA_DIR`.

## 3 ways to talk to the AI

Start the server first (loads the model once, stays in background):

```bash
./scripts/serve.sh          # start — prints the URLs when ready
./scripts/serve.sh --status # check if it's up
./scripts/serve.sh --logs   # follow logs
./scripts/serve.sh --stop   # stop it
```

Then communicate:

### 1. Web UI (easiest)
Open **http://127.0.0.1:8080** in your browser — llama-server ships with a built-in chat UI.

### 2. Terminal chat

```bash
./scripts/chat.sh            # REPL with session memory + live token streaming
```

In-chat commands: `/quit`, `/reset` (clear history), `/system <text>` (change persona).
Extras: `MAX_TOKENS=1024 ./scripts/chat.sh`, `BASE_URL=http://other-host:8080 ./scripts/chat.sh` to talk to a remote instance.

### 3. REST API (OpenAI-compatible)

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello!"}]}'
```

```python
from openai import OpenAI            # pip install openai
client = OpenAI(base_url="http://127.0.0.1:8080/v1", api_key="none")
reply = client.chat.completions.create(
    model="local", messages=[{"role": "user", "content": "Hello!"}]
)
print(reply.choices[0].message.content)
```

Any OpenAI-compatible tool (LangChain, Open WebUI, VS Code extensions...) can point at `http://127.0.0.1:8080/v1`.

## Run via GitHub Actions (manual button)

1. Push this repo to GitHub.
2. Go to **Actions → Run Local AI Model → Run workflow**.
3. Optionally type a prompt and max token count, then press **Run workflow**.
4. The answer appears in the run summary and in the logs.

The workflow: builds llama.cpp → curls the GGUF → starts `llama-server` → sends your prompt → writes the response to the job summary.

## Expected performance (CPU only)

| Phase | Time |
|---|---|
| Model load (cold) | ~30–60 s |
| Generation speed | ~3–5 tok/s |
| 512-token answer | ~2–3 min |

## Notes

- Model is **uncensored/abliterated** — it will not refuse most prompts. Use responsibly; you are responsible for what you generate and for compliance with your local laws.
- ⚠️ This workflow only runs *inside* GitHub-hosted runners. It cannot reach into your local machine — "local" here means the model runs fully self-contained on whatever host executes the script (your PC when you run it locally, the runner when triggered via Actions).

## License note

Base model Qwen3.5 is Apache-2.0; abliteration by huihui-ai/lukey03. Check the upstream repos for current license terms.
