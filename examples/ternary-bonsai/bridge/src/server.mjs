import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { WebSocketServer } from "ws";
import {
  chunkText,
  errorEvent,
  makeSequenceId,
  nowMs,
  permissionChanged,
  segmentCompleted,
  segmentStarted,
  sequenceCompleted,
  toolCall,
  transcriptDelta,
} from "./audio-events.mjs";
import { streamChat, waitForLlama } from "./llama-client.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, "..", "public");

const HOST = process.env.HOST ?? "0.0.0.0";
const PORT = Number(process.env.PORT ?? 8090);
const LLAMA_URL = (process.env.LLAMA_URL ?? "http://127.0.0.1:8081").replace(/\/$/, "");
const ZT_UI_URL = process.env.ZT_UI_URL ?? "http://127.0.0.1:8080";
const MODEL_NAME = process.env.MODEL_NAME ?? "Ternary-Bonsai-1.7B";
const INFERENCE_BACKEND = process.env.INFERENCE_BACKEND ?? "llama";
const SYSTEM_PROMPT =
  process.env.SYSTEM_PROMPT ??
  "You are an ops voice agent for zt-ui. Keep answers short (2-4 sentences). Prefer concrete metrics language.";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".json": "application/json",
};

/** @type {Set<import('ws').WebSocket>} */
const sockets = new Set();

function broadcast(event) {
  const payload = JSON.stringify(event);
  for (const ws of sockets) {
    if (ws.readyState === ws.OPEN) ws.send(payload);
  }
}

function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "access-control-allow-origin": "*",
  });
  res.end(data);
}

function serveStatic(req, res) {
  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
  let rel = url.pathname === "/" ? "/index.html" : url.pathname;
  rel = path.normalize(rel).replace(/^(\.\.[/\\])+/, "");
  const filePath = path.join(PUBLIC_DIR, rel);
  if (!filePath.startsWith(PUBLIC_DIR)) {
    res.writeHead(403).end("forbidden");
    return;
  }
  fs.readFile(filePath, (err, buf) => {
    if (err) {
      res.writeHead(404).end("not found");
      return;
    }
    const ext = path.extname(filePath);
    res.writeHead(200, { "content-type": MIME[ext] ?? "application/octet-stream" });
    res.end(buf);
  });
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (chunks.length === 0) return {};
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

/**
 * Run one voice-agent style sequence:
 * user speech → optional tool_call → assistant speech (streamed from Ternary Bonsai).
 */
async function runSequence({ prompt, withTool = true }) {
  const origin = Date.now();
  const sequenceId = makeSequenceId();
  const emit = (event) => {
    broadcast({ ...event, _wall_ms: Date.now() });
  };

  emit(permissionChanged(sequenceId, "granted"));

  const userStart = nowMs(origin);
  emit(segmentStarted(sequenceId, "u1", "user_speech", userStart));
  emit(transcriptDelta(sequenceId, "u1", prompt, true));
  const userEnd = nowMs(origin);
  emit(segmentCompleted(sequenceId, "u1", userEnd));

  if (withTool) {
    const toolStart = nowMs(origin);
    emit(segmentStarted(sequenceId, "tool1", "tool_call", toolStart));
    emit(toolCall(sequenceId, "tool1", "metrics.query", "running", null));
    await new Promise((r) => setTimeout(r, 350));
    const toolLatency = nowMs(origin) - toolStart;
    emit(toolCall(sequenceId, "tool1", "metrics.query", "completed", toolLatency));
    emit(segmentCompleted(sequenceId, "tool1", nowMs(origin)));
  }

  const assistantStart = nowMs(origin);
  emit(segmentStarted(sequenceId, "a1", "assistant_speech", assistantStart));

  let firstTokenMs = null;
  let buffer = "";
  let fullText = "";

  try {
    const messages = [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: withTool
          ? `${prompt}\n\n(Context: metrics.query returned a synthetic gateway error spike in the last 6 minutes.)`
          : prompt,
      },
    ];

    for await (const delta of streamChat(LLAMA_URL, { messages })) {
      if (firstTokenMs === null) firstTokenMs = nowMs(origin);
      fullText += delta;
      const { emit: piece, rest } = chunkText(buffer, delta);
      buffer = rest;
      if (piece) emit(transcriptDelta(sequenceId, "a1", piece, false));
    }
    if (buffer) emit(transcriptDelta(sequenceId, "a1", buffer, true));
    else if (fullText) emit(transcriptDelta(sequenceId, "a1", "", true));
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    emit(errorEvent("llama_stream", message, nowMs(origin), sequenceId, "a1"));
    throw err;
  }

  const assistantEnd = nowMs(origin);
  emit(segmentCompleted(sequenceId, "a1", assistantEnd));
  emit(sequenceCompleted(sequenceId, assistantEnd));

  return {
    sequence_id: sequenceId,
    prompt,
    response: fullText,
    first_token_latency_ms: firstTokenMs === null ? null : firstTokenMs - assistantStart,
    total_response_latency_ms: assistantEnd - assistantStart,
  };
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "access-control-allow-origin": "*",
      "access-control-allow-methods": "GET,POST,OPTIONS",
      "access-control-allow-headers": "content-type",
    });
    res.end();
    return;
  }

  const url = new URL(req.url ?? "/", `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/healthz") {
    sendJson(res, 200, { ok: true, llama_url: LLAMA_URL, zt_ui_url: ZT_UI_URL });
    return;
  }

  if (req.method === "GET" && url.pathname === "/config") {
    sendJson(res, 200, {
      llama_url: LLAMA_URL,
      zt_ui_url: ZT_UI_URL,
      model: MODEL_NAME,
      backend: INFERENCE_BACKEND,
      family: "ternary",
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/sequence") {
    try {
      const body = await readJson(req);
      const prompt =
        typeof body.prompt === "string" && body.prompt.trim()
          ? body.prompt.trim()
          : "Show me the latest error spike.";
      const withTool = body.with_tool !== false;
      const result = await runSequence({ prompt, withTool });
      sendJson(res, 200, result);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      sendJson(res, 502, { error: message });
    }
    return;
  }

  if (req.method === "GET" || req.method === "HEAD") {
    serveStatic(req, res);
    return;
  }

  res.writeHead(405).end("method not allowed");
});

const wss = new WebSocketServer({ server, path: "/ws" });
wss.on("connection", (ws) => {
  sockets.add(ws);
  ws.send(
    JSON.stringify({
      type: "bridge_ready",
      model: MODEL_NAME,
      backend: INFERENCE_BACKEND,
      zt_ui_url: ZT_UI_URL,
    }),
  );
  ws.on("close", () => sockets.delete(ws));
});

server.listen(PORT, HOST, async () => {
  console.log(`ternary-bonsai bridge on http://${HOST}:${PORT}`);
  console.log(`  inference (${INFERENCE_BACKEND}) → ${LLAMA_URL}`);
  console.log(`  zt-ui → ${ZT_UI_URL}`);
  console.log(`  ws    → ws://${HOST}:${PORT}/ws`);
  try {
    await waitForLlama(LLAMA_URL);
    console.log("inference server is ready");
  } catch (err) {
    console.warn(err instanceof Error ? err.message : err);
    console.warn("bridge is up; sequences will fail until inference is healthy");
  }
});
