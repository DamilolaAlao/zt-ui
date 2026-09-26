# Ternary Bonsai × zt-ui

Host-side example that runs **PrismML Ternary-Bonsai-1.7B** (1.58-bit / GGUF Q2_0) next to the zt-ui dashboard and streams normalized `AudioEvent` payloads — the seam documented in [`docs/audio-sequences.md`](../../docs/audio-sequences.md).

Available as **Docker Compose** or a **macOS desktop app**.

```text
browser (bridge UI :8090)
  ↓ POST /api/sequence + WS /ws
bridge (Node)
  ↓ OpenAI chat completions
llama-server (PrismML fork, Ternary-Bonsai-1.7B-Q2_0)
  ↑ tokens
bridge emits AudioEvent JSON
  → (future) browser host → Zig applyEvent
zt-ui dashboard (:8080)   # reference inspector; inference stays outside WASM
```

Inference, STT, and TTS stay **outside** `app.wasm`. This example only proves the producer side of the contract.

## What you get

| Service | Port | Role |
| --- | --- | --- |
| `zt-ui` | 8080 | Zig/WASM reference dashboard |
| `llama` | 8081 | PrismML `llama-server` + Ternary-Bonsai-1.7B Q2_0 (~442 MB) |
| `bridge` | 8090 | Demo host: prompt → sequence events over WebSocket |

Default model: [`prism-ml/Ternary-Bonsai-1.7B-gguf`](https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-gguf) (`Ternary-Bonsai-1.7B-Q2_0.gguf`).

Q2_0 ternary kernels are **not** in mainline llama.cpp yet; the `llama` image installs PrismML’s prebuilt CPU binaries from [PrismML-Eng/llama.cpp releases](https://github.com/PrismML-Eng/llama.cpp/releases) on **Ubuntu 24.04** (glibc ≥ 2.38).

## Desktop App (macOS, MLX)

Apple Silicon only. The build embeds [`LiquidAI/LFM2.5-2.6B-MLX-bf16`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-MLX-bf16) (~5.4 GB), the MLX export of [`LiquidAI/LFM2.5-2.6B`](https://huggingface.co/LiquidAI/LFM2.5-2.6B), and serves it with `mlx_lm.server` next to the Node bridge and `zt-ui-serve`.

```sh
./scripts/build-macos-app.sh
open "../../dist/macos-mlx/zt-ui LFM2.5.app"
```

Weights are copied into the app at build time (`Contents/Resources/models/LFM2.5-2.6B-MLX-bf16`). Launch does not download a model.

The window opens a chat thread: sidebar, message column, and a composer along the bottom. Menu **View → Thread** (`⌘1`) and **View → zt-ui Dashboard** (`⌘2`) switch the embedded surfaces. Docker still serves the ops bridge page.

Docker still uses PrismML **GGUF Q2_0** + `llama-server` (cross-platform CPU). The macOS app uses MLX.

## Run (Docker)

```sh
docker compose up --build
```

First boot downloads the GGUF into the `bonsai-models` volume (one-time, ~442 MB). Model load on CPU can take a few minutes.

Then open:

- Bridge UI: http://127.0.0.1:8090  
- zt-ui: http://127.0.0.1:8080  
- Raw llama OpenAI API: http://127.0.0.1:8081/v1/models  

Click **Run sequence** in the bridge UI. You should see `segment_started` → `transcript_delta` → `tool_call` → assistant deltas → `sequence_completed`.

## Event contract

Bridge events mirror `src/platform/audio_events.zig`:

```json
{ "type": "segment_started", "sequence_id": "seq_…", "segment_id": "a1", "kind": "assistant_speech", "start_ms": 2800 }
{ "type": "transcript_delta", "sequence_id": "seq_…", "segment_id": "a1", "text": "There was an error spike ", "is_final": false }
{ "type": "tool_call", "sequence_id": "seq_…", "segment_id": "tool1", "tool_name": "metrics.query", "status": "completed", "latency_ms": 350 }
```

Subscribe with:

```js
const ws = new WebSocket("ws://127.0.0.1:8090/ws");
ws.onmessage = (m) => console.log(JSON.parse(m.data));
```

Or trigger without the UI:

```sh
curl -s http://127.0.0.1:8090/api/sequence \
  -H 'content-type: application/json' \
  -d '{"prompt":"Summarize the gateway error spike.","with_tool":true}'
```

## Config

| Variable | Default | Notes |
| --- | --- | --- |
| `MODEL_FILE` | `Ternary-Bonsai-1.7B-Q2_0.gguf` | Swap only if you place another GGUF in the volume |
| `LLAMA_CTX` | `2048` | Keep modest on CPU |
| `LLAMA_NGL` | `0` | CPU-only image; raise only with a CUDA build |
| `LLAMA_THREADS` | `4` | Tune to host cores |
| `SYSTEM_PROMPT` | ops voice agent… | Set on `bridge` service |

## Why not ONNX inside Zig?

ONNX / ORT can host Bonsai builds in the browser, but this repo’s architecture keeps inference in the host. Docker + PrismML GGUF is the practical path for Ternary Bonsai Q2_0 today; the bridge is what you would also put in front of an ONNX or remote endpoint.

## Wiring the dashboard

The producer contract is unchanged. Point a zt-ui host at the bridge socket and it calls `applyEvent` for each JSON message:

```text
http://127.0.0.1:8080/?audio=ws://127.0.0.1:8090/ws
```

`@zt-ui/stage` hosts pass the same URL as `audioEventsUrl`. The audio panel switches from the canned demo to `host feed` on the first event. A new `sequence_id` starts a new sequence. Inference stays in llama-server.
