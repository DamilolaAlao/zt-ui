export interface ZtRuntimeExports {
  memory: WebAssembly.Memory;
  initRuntime(width: number, height: number): void;
  resize(width: number, height: number): void;
  beginFrame(dtMs: number): void;
  pointerMove(x: number, y: number): void;
  pointerButton(button: number, down: boolean): void;
  pointerWheel(deltaX: number, deltaY: number): void;
  keyEvent(code: number, down: boolean): void;
  getCommandsPtr(): number;
  getCommandsLen(): number;
  getTextPtr(): number;
  getTextLen(): number;
  getPointsPtr(): number;
  getPointsLen(): number;
  getSnapshotPtr?(): number;
  getSnapshotLen?(): number;
  getAudioEventBufPtr?(): number;
  getAudioEventBufCap?(): number;
  pushAudioEvent?(len: number): void;
}

export interface RenderFrame {
  memory: WebAssembly.Memory;
  commandsPtr: number;
  commandsLen: number;
  textPtr: number;
  textLen: number;
  pointsPtr: number;
  pointsLen: number;
}

/**
 * Only `canvas` is required. Diagnostics/overlay nodes are optional so hosts
 * (Next.js, vanilla embeds, Astro) can mount a minimal stage without chrome.
 */
export interface StageElements {
  canvas: HTMLCanvasElement;
  runtimeStatus?: HTMLElement | null;
  backendBadge?: HTMLElement | null;
  frameBadge?: HTMLElement | null;
  focusStat?: HTMLElement | null;
  viewportStat?: HTMLElement | null;
  overlayTitle?: HTMLElement | null;
  overlayCopy?: HTMLElement | null;
  deltaStat?: HTMLElement | null;
  fpsStat?: HTMLElement | null;
  commandStat?: HTMLElement | null;
  textStat?: HTMLElement | null;
  pointStat?: HTMLElement | null;
  importStat?: HTMLElement | null;
  exportList?: HTMLElement | null;
  importList?: HTMLElement | null;
  diagnostics?: HTMLElement | null;
}

export interface RuntimeSnapshot {
  title?: string;
  summary?: string;
  feedState?: string;
  selectedId?: string | null;
  metrics?: Record<string, boolean | number | string | null>;
}

export interface FrameStats {
  deltaMs: number;
  fps: number;
  commandsLen: number;
  textLen: number;
  pointsLen: number;
}

export interface MountOptions {
  /** Default: `/wasm/app.wasm` */
  wasmUrl?: string;
  /** Called when Zig publishes an optional JSON shell snapshot. */
  onSnapshot?: (snapshot: RuntimeSnapshot | null) => void;
  /** Called once per painted frame with buffer stats. */
  onFrame?: (stats: FrameStats) => void;
  /** Called with lifecycle status strings (loading / ready / failed). */
  onStatus?: (status: string) => void;
  /** Host label used in ready messaging. Default: "Host". */
  hostLabel?: string;
  /**
   * WebSocket that emits AudioEvent JSON, for example `ws://127.0.0.1:8090/ws`.
   * Inference stays on that producer. The stage only forwards payloads into Zig.
   */
  audioEventsUrl?: string;
}

export interface MountedStage {
  destroy(): void;
}
