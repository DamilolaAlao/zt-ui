const statusEl = document.getElementById("status");
const eventsEl = document.getElementById("events");
const assistantEl = document.getElementById("assistant");
const metricsEl = document.getElementById("metrics");
const promptEl = document.getElementById("prompt");
const withToolEl = document.getElementById("with-tool");
const runEl = document.getElementById("run");
const ztLink = document.getElementById("zt-link");

let assistantText = "";
let firstTokenAt = null;
let sequenceStartedAt = null;

function setStatus(text, state) {
  statusEl.textContent = text;
  statusEl.dataset.state = state;
}

function pushEvent(event) {
  const li = document.createElement("li");
  const type = event.type ?? "unknown";
  const copy = { ...event };
  delete copy._wall_ms;
  li.innerHTML = `<span class="type">${type}</span> ${JSON.stringify(copy)}`;
  eventsEl.prepend(li);
  while (eventsEl.children.length > 120) {
    eventsEl.removeChild(eventsEl.lastChild);
  }

  if (type === "segment_started" && event.kind === "assistant_speech") {
    assistantText = "";
    firstTokenAt = null;
    sequenceStartedAt = event.start_ms ?? 0;
    assistantEl.textContent = "";
  }
  if (type === "transcript_delta" && event.segment_id === "a1") {
    if (!firstTokenAt && event.text) firstTokenAt = performance.now();
    assistantText += event.text ?? "";
    assistantEl.textContent = assistantText || "…";
  }
  if (type === "sequence_completed") {
    const rows = [];
    if (firstTokenAt && sequenceStartedAt !== null) {
      rows.push(["first visible token", `${Math.round(firstTokenAt - (window.__runStarted ?? firstTokenAt))} ms (client)`]);
    }
    rows.push(["completed_at_ms", String(event.completed_at_ms ?? "")]);
    metricsEl.innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("");
  }
}

function connectWs() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.addEventListener("open", () => setStatus("ws ready", "ready"));
  ws.addEventListener("close", () => {
    setStatus("ws reconnecting", "error");
    setTimeout(connectWs, 1500);
  });
  ws.addEventListener("message", (msg) => {
    try {
      pushEvent(JSON.parse(msg.data));
    } catch {
      /* ignore */
    }
  });
}

async function loadConfig() {
  const res = await fetch("/config");
  if (!res.ok) return;
  const cfg = await res.json();
  if (cfg.zt_ui_url) ztLink.href = cfg.zt_ui_url;
}

async function runSequence() {
  runEl.disabled = true;
  window.__runStarted = performance.now();
  assistantEl.textContent = "Generating…";
  metricsEl.innerHTML = "";
  try {
    const res = await fetch("/api/sequence", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        prompt: promptEl.value,
        with_tool: withToolEl.checked,
      }),
    });
    const body = await res.json();
    if (!res.ok) throw new Error(body.error ?? res.statusText);
    const rows = [
      ["sequence_id", body.sequence_id],
      ["first_token_latency_ms", String(body.first_token_latency_ms ?? "n/a")],
      ["total_response_latency_ms", String(body.total_response_latency_ms ?? "n/a")],
    ];
    metricsEl.innerHTML = rows.map(([k, v]) => `<dt>${k}</dt><dd>${v}</dd>`).join("");
    if (body.response) assistantEl.textContent = body.response;
  } catch (err) {
    setStatus(err instanceof Error ? err.message : String(err), "error");
    assistantEl.textContent = "Sequence failed — is llama-server healthy?";
  } finally {
    runEl.disabled = false;
  }
}

runEl.addEventListener("click", () => void runSequence());
void loadConfig();
connectWs();
