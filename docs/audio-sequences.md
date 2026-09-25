# LLM Audio Sequences

`zt-ui` represents voice-agent interactions as plain-data sequences of timestamped segments. The UI owns state inspection, rendering, and control surfaces; speech recognition, TTS, audio decoding, and LLM inference stay outside the core runtime.

## Goals

- Visualize user speech, assistant playback, silence, and tool-call boundaries.
- Preserve the browser-hosted WASM-first architecture and command-buffered renderer.
- Keep sequence state inspectable as plain data inside the reference dashboard.
- Accept normalized browser-side streaming events without turning `zt-ui` into an audio SDK.

## Layer Fit

| Layer | Responsibility |
| --- | --- |
| `src/platform` | Browser permission state, input-level snapshots, and normalized audio event payloads. |
| `src/gfx` | Existing rectangles, strokes, text, and polylines used to render lanes, markers, and transcript cards. |
| `src/ui` | Reusable immediate-mode rules once audio interactions repeat across more than one surface. |
| `src/app` | The current reference implementation: sequence state, demo data, timeline rendering, transcript rows, and inspector controls. |

The first implementation intentionally keeps the audio panel in `src/app` because it is still a single reference surface. If the interaction rules begin to repeat, the shared pieces can move into `src/ui` later without changing the data model.

## Current Files

- `src/app/audio_sequence_state.zig`
- `src/app/audio_sequence_panel.zig`
- `src/platform/audio_events.zig`

## Core Model

The model is centered on:

- `AudioSequence`: sequence identity, language, sample rate, lifecycle state, segments, and latency metrics.
- `AudioSegment`: timestamped user speech, assistant speech, tool calls, silence, background audio, or interruption markers.
- `VoiceSpec`: playback voice identity plus style, emotion, speed, pitch, and gain controls.
- `ToolCallSpec`: tool name, JSON payloads, execution status, and latency.
- `InterruptionSpec`: target segment, interruption time, and reason.
- `AudioSequenceMetrics`: input audio duration, assistant audio duration, transcription latency, first-token latency, first-audio latency, total response latency, tool calls, interruptions, and errors.

Validation currently enforces:

1. Unique segment ids per sequence.
2. Non-negative segment ranges.
3. Optional duration values that match `end_ms - start_ms`.
4. Required assistant payloads (`text` or `audio_uri`).
5. Required user payloads (`transcript` or `audio_uri`).
6. Required tool names for tool-call segments.
7. Existing target segment references for interruption segments.
8. Voice control ranges:
   - `0.5 <= speed <= 2.0`
   - `-12.0 <= pitch_semitones <= 12.0`
   - `-24.0 <= gain_db <= 12.0`

## Reference Panel

The reference dashboard renders:

- A summary strip with sequence state, playback cursor, first-audio latency, and tool-call count.
- A three-lane timeline for user speech, tool calls, and assistant speech.
- Transcript rows that can be clicked to pin a segment in the inspector.
- An inspector with cursor controls, selection clearing, a completed-demo/live-replay toggle, and optional debug-field output.

The shipped demo sequence models:

`[User speech] -> [Tool: metrics.query] -> [Assistant speech]`

with response text about an API gateway error spike.

The reference app now supports two demo modes:

- a completed sequence for static inspection
- a live replay driven by normalized `AudioEvent` values to demonstrate streaming segment starts, transcript deltas, tool-call progress, and sequence completion

## Streaming Event Boundary

`src/platform/audio_events.zig` defines the normalized payloads expected from the browser host. The current event union includes:

- `permission_changed`
- `input_level`
- `segment_started`
- `transcript_delta`
- `audio_delta`
- `tool_call`
- `interruption`
- `segment_completed`
- `sequence_completed`
- `error_`

Those events are the seam between browser-owned capture/playback concerns and Zig-owned dashboard state.

## Host example: Ternary Bonsai

[`examples/ternary-bonsai`](../examples/ternary-bonsai) is a Docker Compose stack that keeps inference outside Zig:

- PrismML **Ternary-Bonsai-1.7B** (GGUF Q2_0) via PrismML `llama-server`
- A Node bridge that emits the `AudioEvent` payloads above over WebSocket
- The existing zt-ui dashboard alongside the bridge demo UI

```sh
cd examples/ternary-bonsai
docker compose up --build
```

The reference host consumes that socket with `?audio=ws://127.0.0.1:8090/ws`. `@zt-ui/stage` takes the same URL as `audioEventsUrl`. Each JSON message is copied into the wasm buffer and `pushAudioEvent` calls `AudioDemoState.applyHostJson`. The first event switches the panel to `host feed`. A new `sequence_id` starts a new sequence.

## Next Milestones

1. Add a selected-segment metadata pane with richer payload formatting and optional JSON snapshots.
2. Add interruption markers, richer input-level metering, and playback error surfacing in the canvas stage.
3. Add coarse DOM-facing state snapshots for non-canvas shells when needed.
