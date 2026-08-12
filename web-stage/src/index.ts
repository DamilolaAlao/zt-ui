/**
 * @zt-ui/stage — portable Zig/WASM stage seam for any browser host.
 *
 * Hosts (Astro, Next.js, vanilla) own page chrome.
 * This package owns mount, input forwarding, and Canvas2D paint of Zig command buffers.
 */

export type {
  FrameStats,
  MountOptions,
  MountedStage,
  RenderFrame,
  RuntimeSnapshot,
  StageElements,
  ZtRuntimeExports,
} from "./contracts";

export { STAGE_ROLES, roleSelector, type StageRole } from "./roles";
export { collectStageElements, mountStage } from "./mount";
export { createStageRuntime } from "./runtime";
export { createRenderer } from "./renderer";
export { readRuntimeSnapshot } from "./snapshot";
