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
./scripts/run-model.sh                # interactive chat
./scripts/run-model.sh "your prompt"  # one-shot prompt -> answer
```

First run: builds llama.cpp (~2–5 min) and downloads the model (~5.6 GB). Later runs start instantly.

Env overrides: `THREADS`, `CTX_SIZE`, `MODEL_DIR`, `LLAMA_DIR`.

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
