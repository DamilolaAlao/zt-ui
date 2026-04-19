import { createRenderer } from "./webgpu.js";

const els = {
  canvas: document.getElementById("dashboard-canvas"),
  runtimeStatus: document.getElementById("runtime-status"),
  backendBadge: document.getElementById("backend-badge"),
  frameBadge: document.getElementById("frame-badge"),
  focusStat: document.getElementById("focus-stat"),
  viewportStat: document.getElementById("viewport-stat"),
  overlayTitle: document.getElementById("overlay-title"),
  overlayCopy: document.getElementById("overlay-copy"),
  deltaStat: document.getElementById("delta-stat"),
  fpsStat: document.getElementById("fps-stat"),
  commandStat: document.getElementById("command-stat"),
  textStat: document.getElementById("text-stat"),
  pointStat: document.getElementById("point-stat"),
  importStat: document.getElementById("import-stat"),
  exportList: document.getElementById("export-list"),
  importList: document.getElementById("import-list"),
  diagnostics: document.getElementById("diagnostics-log"),
};

const runtime = {
  exports: null,
  memory: null,
  renderer: createRenderer(els.canvas),
  lastFrameAt: performance.now(),
  loaded: false,
};

function setText(node, text) {
  if (node) node.textContent = text;
}

function logDiagnostic(message) {
  const item = document.createElement("li");
  item.textContent = message;
  els.diagnostics.prepend(item);
  while (els.diagnostics.children.length > 6) {
    els.diagnostics.removeChild(els.diagnostics.lastElementChild);
  }
}

function setOverlay(title, copy) {
  setText(els.overlayTitle, title);
  setText(els.overlayCopy, copy);
}

function listModuleItems(target, items, emptyLabel) {
  target.innerHTML = "";
  const values = items.length ? items : [emptyLabel];
  for (const value of values) {
    const item = document.createElement("li");
    item.textContent = value;
    target.appendChild(item);
  }
}

function keyCodeForEvent(event) {
  if (event.code === "Backquote") return 192;
  if (event.code === "KeyG") return 71;
  if (event.key && event.key.length === 1) {
    return event.key.toUpperCase().charCodeAt(0);
  }
  return null;
}

function canvasPoint(event) {
  const rect = els.canvas.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

function pushPointerMove(event) {
  if (!runtime.exports?.pointerMove) return;
  const point = canvasPoint(event);
  runtime.exports.pointerMove(point.x, point.y);
}

function resizeRuntime() {
  const viewport = runtime.renderer.resize();
  setText(els.viewportStat, `${viewport.width} x ${viewport.height} css px`);

  if (!runtime.exports) return;
  if (typeof runtime.exports.resize === "function") {
    runtime.exports.resize(viewport.width, viewport.height);
  } else if (typeof runtime.exports.initRuntime === "function") {
    runtime.exports.initRuntime(viewport.width, viewport.height);
  }
}

function bindInput() {
  els.canvas.addEventListener("pointerenter", () => setText(els.focusStat, "Canvas active"));
  els.canvas.addEventListener("pointerleave", () => setText(els.focusStat, "Canvas inactive"));
  els.canvas.addEventListener("pointermove", pushPointerMove);

  els.canvas.addEventListener("pointerdown", (event) => {
    pushPointerMove(event);
    runtime.exports?.pointerButton?.(event.button, true);
    els.canvas.focus();
    els.canvas.setPointerCapture(event.pointerId);
  });

  els.canvas.addEventListener("pointerup", (event) => {
    pushPointerMove(event);
    runtime.exports?.pointerButton?.(event.button, false);
  });

  els.canvas.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      runtime.exports?.pointerWheel?.(event.deltaX, event.deltaY);
    },
    { passive: false },
  );

  window.addEventListener("keydown", (event) => {
    const code = keyCodeForEvent(event);
    if (code != null) {
      runtime.exports?.keyEvent?.(code, true);
    }
  });

  window.addEventListener("keyup", (event) => {
    const code = keyCodeForEvent(event);
    if (code != null) {
      runtime.exports?.keyEvent?.(code, false);
    }
  });

  window.addEventListener("resize", resizeRuntime);
}

async function loadRuntime() {
  setText(els.runtimeStatus, "Loading WebAssembly");
  setOverlay("Loading workflow runtime", "Fetching the generated wasm module and verifying its exported surface.");

  const response = await fetch("./app.wasm");
  if (!response.ok) {
    throw new Error(`Failed to fetch app.wasm (${response.status})`);
  }

  const bytes = await response.arrayBuffer();
  const imports = WebAssembly.Module.imports(await WebAssembly.compile(bytes));
  const { instance } = await WebAssembly.instantiate(bytes, {});

  runtime.exports = instance.exports;
  runtime.memory = instance.exports.memory ?? null;
  runtime.loaded = true;

  const exportNames = Object.keys(instance.exports).sort();
  listModuleItems(els.exportList, exportNames, "No exports");
  listModuleItems(
    els.importList,
    imports.map((entry) => `${entry.module}.${entry.name}`),
    "No imports",
  );
  setText(els.importStat, `${imports.length} imports`);

  if (!runtime.memory) {
    throw new Error("The module did not export memory.");
  }

  resizeRuntime();
  setText(els.runtimeStatus, "Runtime ready");
  setText(els.backendBadge, "Canvas2D reference");
  setOverlay(
    "Runtime ready",
    "The browser bridge is live. Workflow panels and throughput plots are now drawing directly from Zig command buffers.",
  );
  logDiagnostic("Runtime loaded successfully.");
}

function drawFrame(now) {
  requestAnimationFrame(drawFrame);

  if (!runtime.loaded || !runtime.exports || !runtime.memory) {
    return;
  }

  const dt = Math.min(64, now - runtime.lastFrameAt || 16.666);
  runtime.lastFrameAt = now;

  runtime.exports.beginFrame?.(dt);

  const commandsLen = Number(runtime.exports.getCommandsLen?.() ?? 0);
  const textLen = Number(runtime.exports.getTextLen?.() ?? 0);
  const pointsLen = Number(runtime.exports.getPointsLen?.() ?? 0);

  runtime.renderer.render({
    memory: runtime.memory,
    commandsPtr: Number(runtime.exports.getCommandsPtr?.() ?? 0),
    commandsLen,
    textPtr: Number(runtime.exports.getTextPtr?.() ?? 0),
    textLen,
    pointsPtr: Number(runtime.exports.getPointsPtr?.() ?? 0),
    pointsLen,
  });

  setText(els.frameBadge, `${commandsLen} command records`);
  setText(els.deltaStat, `${dt.toFixed(2)} ms`);
  setText(els.fpsStat, `${(1000 / dt).toFixed(1)}`);
  setText(els.commandStat, `${commandsLen} records`);
  setText(els.textStat, `${textLen} bytes`);
  setText(els.pointStat, `${pointsLen} vertices`);
}

bindInput();

try {
  await loadRuntime();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  setText(els.runtimeStatus, "Runtime failed");
  setText(els.frameBadge, "Initialization error");
  setOverlay("Runtime failed", message);
  logDiagnostic(message);
}

requestAnimationFrame(drawFrame);
