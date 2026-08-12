import type {
  MountedStage,
  MountOptions,
  RuntimeSnapshot,
  StageElements,
  ZtRuntimeExports,
} from "./contracts";
import { createRenderer } from "./renderer";
import { readRuntimeSnapshot } from "./snapshot";

function setText(node: HTMLElement | null | undefined, text: string) {
  if (node) node.textContent = text;
}

function logDiagnostic(target: HTMLElement | null | undefined, message: string) {
  if (!target) return;
  const item = document.createElement("li");
  item.textContent = message;
  target.prepend(item);
  while (target.children.length > 6) {
    target.removeChild(target.lastElementChild as Element);
  }
}

function setOverlay(elements: StageElements, title: string, copy: string) {
  setText(elements.overlayTitle, title);
  setText(elements.overlayCopy, copy);
}

function listModuleItems(
  target: HTMLElement | null | undefined,
  items: string[],
  emptyLabel: string,
) {
  if (!target) return;
  target.innerHTML = "";
  const values = items.length > 0 ? items : [emptyLabel];
  for (const value of values) {
    const item = document.createElement("li");
    item.textContent = value;
    target.appendChild(item);
  }
}

function keyCodeForEvent(event: KeyboardEvent): number | null {
  if (event.code === "Backquote") return 192;
  if (event.code === "KeyG") return 71;
  if (event.code === "Space") return 32;
  if (event.code === "ArrowUp") return 38;
  if (event.key && event.key.length === 1) {
    return event.key.toUpperCase().charCodeAt(0);
  }
  return null;
}

export function createStageRuntime(
  elements: StageElements,
  options: MountOptions = {},
): MountedStage & { mount(): Promise<void> } {
  const wasmUrl = options.wasmUrl ?? "/wasm/app.wasm";
  const hostLabel = options.hostLabel ?? "Host";
  const renderer = createRenderer(elements.canvas);
  const events = new AbortController();

  let exportsRef: ZtRuntimeExports | null = null;
  let memoryRef: WebAssembly.Memory | null = null;
  let loaded = false;
  let lastFrameAt = performance.now();
  let frameHandle = 0;

  function publishStatus(status: string) {
    setText(elements.runtimeStatus, status);
    options.onStatus?.(status);
  }

  function canvasPoint(event: PointerEvent) {
    const rect = elements.canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }

  function pushPointerMove(event: PointerEvent) {
    if (!exportsRef) return;
    const point = canvasPoint(event);
    exportsRef.pointerMove(point.x, point.y);
  }

  function applySnapshot(snapshot: RuntimeSnapshot | null) {
    options.onSnapshot?.(snapshot);
    if (!snapshot) return;

    if (snapshot.title || snapshot.summary) {
      setOverlay(
        elements,
        snapshot.title ?? elements.overlayTitle?.textContent ?? "Runtime ready",
        snapshot.summary ?? elements.overlayCopy?.textContent ?? "",
      );
    }
  }

  function resizeRuntime() {
    const viewport = renderer.resize();
    setText(elements.viewportStat, `${viewport.width} × ${viewport.height} css px`);

    if (!exportsRef) return;
    if (typeof exportsRef.resize === "function") {
      exportsRef.resize(viewport.width, viewport.height);
    } else if (typeof exportsRef.initRuntime === "function") {
      exportsRef.initRuntime(viewport.width, viewport.height);
    }
  }

  function bindInput() {
    const signal = events.signal;

    elements.canvas.addEventListener(
      "pointerenter",
      () => setText(elements.focusStat, "Canvas active"),
      { signal },
    );
    elements.canvas.addEventListener(
      "pointerleave",
      () => setText(elements.focusStat, "Canvas inactive"),
      { signal },
    );
    elements.canvas.addEventListener("pointermove", pushPointerMove, { signal });

    elements.canvas.addEventListener(
      "pointerdown",
      (event) => {
        pushPointerMove(event);
        exportsRef?.pointerButton(event.button, true);
        elements.canvas.focus();
        elements.canvas.setPointerCapture(event.pointerId);
      },
      { signal },
    );

    elements.canvas.addEventListener(
      "pointerup",
      (event) => {
        pushPointerMove(event);
        exportsRef?.pointerButton(event.button, false);
      },
      { signal },
    );

    elements.canvas.addEventListener(
      "pointercancel",
      (event) => {
        pushPointerMove(event);
        exportsRef?.pointerButton(event.button, false);
      },
      { signal },
    );

    elements.canvas.addEventListener(
      "wheel",
      (event) => {
        event.preventDefault();
        exportsRef?.pointerWheel(event.deltaX, event.deltaY);
      },
      { passive: false, signal },
    );

    window.addEventListener(
      "keydown",
      (event) => {
        const code = keyCodeForEvent(event);
        if (code != null) exportsRef?.keyEvent(code, true);
      },
      { signal },
    );

    window.addEventListener(
      "keyup",
      (event) => {
        const code = keyCodeForEvent(event);
        if (code != null) exportsRef?.keyEvent(code, false);
      },
      { signal },
    );

    window.addEventListener("resize", resizeRuntime, { signal });
  }

  async function loadRuntime() {
    publishStatus("Loading WebAssembly");
    setOverlay(
      elements,
      "Loading workflow runtime",
      "Fetching the generated wasm module and verifying its exported surface.",
    );

    const response = await fetch(wasmUrl);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${wasmUrl} (${response.status})`);
    }

    const bytes = await response.arrayBuffer();
    const module = await WebAssembly.compile(bytes);
    const imports = WebAssembly.Module.imports(module);
    // instantiate(Module) returns the Instance directly (not { instance }).
    const instance = await WebAssembly.instantiate(module, {});

    exportsRef = instance.exports as unknown as ZtRuntimeExports;
    memoryRef = exportsRef.memory ?? null;
    loaded = true;

    if (!memoryRef) {
      throw new Error("The module did not export memory.");
    }

    listModuleItems(elements.exportList, Object.keys(instance.exports).sort(), "No exports");
    listModuleItems(
      elements.importList,
      imports.map((entry) => `${entry.module}.${entry.name}`),
      "No imports",
    );
    setText(elements.importStat, `${imports.length} imports`);

    resizeRuntime();
    publishStatus("Runtime ready");
    setText(elements.backendBadge, "Canvas2D reference");
    setOverlay(
      elements,
      "Runtime ready",
      `${hostLabel} is live. Zig command buffers are now driving the stage.`,
    );
    logDiagnostic(elements.diagnostics, "Runtime loaded successfully.");
  }

  function drawFrame(now: number) {
    frameHandle = window.requestAnimationFrame(drawFrame);

    if (!loaded || !exportsRef || !memoryRef) {
      return;
    }

    const dt = Math.min(64, now - lastFrameAt || 16.666);
    lastFrameAt = now;

    exportsRef.beginFrame(dt);

    const commandsLen = Number(exportsRef.getCommandsLen() ?? 0);
    const textLen = Number(exportsRef.getTextLen() ?? 0);
    const pointsLen = Number(exportsRef.getPointsLen() ?? 0);

    renderer.render({
      memory: memoryRef,
      commandsPtr: Number(exportsRef.getCommandsPtr() ?? 0),
      commandsLen,
      textPtr: Number(exportsRef.getTextPtr() ?? 0),
      textLen,
      pointsPtr: Number(exportsRef.getPointsPtr() ?? 0),
      pointsLen,
    });

    setText(elements.frameBadge, `${commandsLen} command records`);
    setText(elements.deltaStat, `${dt.toFixed(2)} ms`);
    setText(elements.fpsStat, `${(1000 / dt).toFixed(1)}`);
    setText(elements.commandStat, `${commandsLen} records`);
    setText(elements.textStat, `${textLen} bytes`);
    setText(elements.pointStat, `${pointsLen} vertices`);

    options.onFrame?.({
      deltaMs: dt,
      fps: 1000 / dt,
      commandsLen,
      textLen,
      pointsLen,
    });

    applySnapshot(readRuntimeSnapshot(exportsRef, memoryRef));
  }

  return {
    async mount() {
      bindInput();

      try {
        await loadRuntime();
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        publishStatus("Runtime failed");
        setText(elements.frameBadge, "Initialization error");
        setOverlay(elements, "Runtime failed", message);
        logDiagnostic(elements.diagnostics, message);
        return;
      }

      frameHandle = window.requestAnimationFrame(drawFrame);
    },

    destroy() {
      events.abort();
      loaded = false;
      if (frameHandle) {
        window.cancelAnimationFrame(frameHandle);
      }
    },
  };
}
