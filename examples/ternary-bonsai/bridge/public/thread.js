const STORAGE_KEY = "zt-ui.lfm.threads.v1";

const threadListEl = document.getElementById("thread-list");
const timelineEl = document.getElementById("timeline");
const stageEl = document.getElementById("stage");
const titleEl = document.getElementById("thread-title");
const promptEl = document.getElementById("prompt");
const sendEl = document.getElementById("send");
const formEl = document.getElementById("composer");
const statusEl = document.getElementById("status");
const modelChipEl = document.getElementById("model-chip");
const draftTitleEl = document.getElementById("draft-title");
const dashboardLink = document.getElementById("dashboard-link");
const newThreadEl = document.getElementById("new-thread");

const state = loadState();
let run = null;

function loadState() {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "");
    if (parsed && Array.isArray(parsed.threads) && parsed.threads.length > 0) return parsed;
  } catch {
    /* start fresh */
  }
  const thread = blankThread();
  return { activeId: thread.id, threads: [thread] };
}

function blankThread() {
  return {
    id: `thread_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 6)}`,
    title: "New thread",
    updatedAt: Date.now(),
    items: [],
  };
}

function save() {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function activeThread() {
  return state.threads.find((thread) => thread.id === state.activeId) ?? state.threads[0];
}

function setStatus(text, kind) {
  statusEl.textContent = text;
  statusEl.dataset.state = kind;
}

function renderSidebar() {
  const threads = [...state.threads].sort((a, b) => b.updatedAt - a.updatedAt);
  threadListEl.replaceChildren();
  for (const thread of threads) {
    const li = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    if (thread.id === state.activeId) button.setAttribute("aria-current", "true");
    const title = document.createElement("span");
    title.className = "title";
    title.textContent = thread.title;
    button.append(title);
    button.addEventListener("click", () => {
      state.activeId = thread.id;
      save();
      render();
    });
    li.append(button);
    threadListEl.append(li);
  }
}

function renderTimeline() {
  const thread = activeThread();
  titleEl.textContent = thread.title;
  document.title = `zt-ui · ${thread.title}`;
  stageEl.dataset.empty = thread.items.length === 0 ? "true" : "false";
  timelineEl.replaceChildren();

  for (const item of thread.items) {
    if (item.kind === "user") {
      const row = document.createElement("div");
      row.className = "turn user";
      const bubble = document.createElement("div");
      bubble.className = "bubble";
      bubble.textContent = item.text;
      row.append(bubble);
      timelineEl.append(row);
      continue;
    }
    if (item.kind === "assistant") {
      const row = document.createElement("div");
      row.className = "turn assistant";
      const text = document.createElement("div");
      text.className = "assistant-text";
      text.textContent = item.text || (item.streaming ? "" : "(empty response)");
      row.append(text);
      timelineEl.append(row);
      continue;
    }
    if (item.kind === "work") {
      const row = document.createElement("div");
      row.className = "work";
      row.dataset.status = item.status;
      const mark = document.createElement("span");
      mark.className = "work-mark";
      const label = document.createElement("span");
      label.textContent = item.label;
      const status = document.createElement("span");
      status.textContent = item.status;
      row.append(mark, label, status);
      timelineEl.append(row);
      continue;
    }
    if (item.kind === "error") {
      const row = document.createElement("div");
      row.className = "error";
      row.textContent = item.text;
      timelineEl.append(row);
    }
  }

  if (run && run.threadId === thread.id) {
    const working = document.createElement("div");
    working.className = "working";
    working.innerHTML = '<span class="dots"><i></i><i></i><i></i></span><span>Working…</span>';
    timelineEl.append(working);
  }

  const wrap = timelineEl.parentElement;
  if (wrap) wrap.scrollTop = wrap.scrollHeight;
}

function render() {
  renderSidebar();
  renderTimeline();
  sendEl.disabled = run !== null;
}

function item(threadId, id) {
  return state.threads.find((thread) => thread.id === threadId)?.items.find((entry) => entry.id === id);
}

function touch(thread) {
  thread.updatedAt = Date.now();
}

async function sendPrompt(prompt) {
  const thread = activeThread();
  if (run || !prompt) return;

  if (thread.title === "New thread") {
    thread.title = prompt.replace(/\s+/g, " ").trim();
  }
  thread.items.push({ kind: "user", id: `u_${Date.now()}`, text: prompt });
  touch(thread);
  run = { threadId: thread.id, sequenceId: null, assistantId: null };
  promptEl.value = "";
  resizePrompt();
  save();
  render();

  try {
    const res = await fetch("/api/sequence", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ prompt, with_tool: true }),
    });
    const body = await res.json();
    if (!res.ok) throw new Error(body.error ?? res.statusText);
    const assistant = run ? item(run.threadId, run.assistantId) : null;
    if (assistant && !assistant.text && body.response) assistant.text = body.response;
    if (assistant) assistant.streaming = false;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    pushError(thread, message);
    setStatus("send failed", "error");
  } finally {
    run = null;
    touch(thread);
    save();
    render();
  }
}

function applyEvent(event) {
  if (!run) return;
  if (event.sequence_id && !run.sequenceId) run.sequenceId = event.sequence_id;
  if (event.sequence_id && run.sequenceId && event.sequence_id !== run.sequenceId) return;

  const thread = state.threads.find((entry) => entry.id === run.threadId);
  if (!thread) return;

  if (event.type === "tool_call") {
    const id = `tool_${event.segment_id}`;
    const existing = thread.items.find((entry) => entry.id === id);
    if (existing) {
      existing.status = event.status ?? existing.status;
    } else {
      thread.items.push({
        kind: "work",
        id,
        label: event.tool_name ?? "tool",
        status: event.status ?? "running",
      });
    }
    touch(thread);
    save();
    render();
    return;
  }

  if (event.type === "segment_started" && event.kind === "assistant_speech") {
    const id = `a_${event.segment_id}`;
    run.assistantId = id;
    thread.items.push({ kind: "assistant", id, text: "", streaming: true });
    touch(thread);
    save();
    render();
    return;
  }

  if (event.type === "transcript_delta" && event.segment_id && run.assistantId?.endsWith(event.segment_id)) {
    const assistant = item(thread.id, run.assistantId);
    if (assistant && event.text) assistant.text += event.text;
    touch(thread);
    save();
    render();
    return;
  }

  if (event.type === "error" || event.type === "error_") {
    pushError(thread, event.message ?? "Inference error");
    touch(thread);
    save();
    render();
  }
}

function pushError(thread, text) {
  const last = thread.items.at(-1);
  if (last?.kind === "error" && last.text === text) return;
  thread.items.push({ kind: "error", id: `e_${Date.now()}`, text });
}

function connectWs() {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  ws.addEventListener("open", () => setStatus("ready", "ready"));
  ws.addEventListener("close", () => {
    setStatus("reconnecting", "error");
    setTimeout(connectWs, 1500);
  });
  ws.addEventListener("message", (msg) => {
    try {
      applyEvent(JSON.parse(msg.data));
    } catch {
      /* ignore malformed frames */
    }
  });
}

function resizePrompt() {
  promptEl.style.height = "auto";
  promptEl.style.height = `${Math.min(promptEl.scrollHeight, 180)}px`;
}

formEl.addEventListener("submit", (event) => {
  event.preventDefault();
  void sendPrompt(promptEl.value.trim());
});

promptEl.addEventListener("input", resizePrompt);
promptEl.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    void sendPrompt(promptEl.value.trim());
  }
});

newThreadEl.addEventListener("click", () => {
  const thread = blankThread();
  state.threads.push(thread);
  state.activeId = thread.id;
  save();
  render();
  promptEl.focus();
});

async function loadConfig() {
  const res = await fetch("/config");
  if (!res.ok) return;
  const cfg = await res.json();
  if (cfg.zt_ui_url) dashboardLink.href = cfg.zt_ui_url;
  const label = cfg.model?.split("/").pop() || cfg.model;
  if (!label) return;
  modelChipEl.textContent = label;
  draftTitleEl.textContent = label;
  promptEl.placeholder = `Message ${label}…`;
}

render();
void loadConfig();
connectWs();
