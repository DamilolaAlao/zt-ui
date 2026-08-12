import type { MountOptions, MountedStage, StageElements } from "./contracts";
import { STAGE_ROLES, roleSelector, type StageRole } from "./roles";
import { createStageRuntime } from "./runtime";

function optionalElement<T extends Element>(root: ParentNode, role: StageRole): T | null {
  return root.querySelector(roleSelector(role)) as T | null;
}

function requireCanvas(root: HTMLElement): HTMLCanvasElement {
  const existing = optionalElement<HTMLCanvasElement>(root, STAGE_ROLES.canvas);
  if (existing) return existing;

  const canvas = document.createElement("canvas");
  canvas.dataset.role = STAGE_ROLES.canvas;
  canvas.tabIndex = 0;
  canvas.setAttribute("aria-label", "Zig immediate mode stage canvas");
  root.appendChild(canvas);
  return canvas;
}

/**
 * Collect stage bindings from a host root. Only the canvas is required —
 * missing chrome nodes are left null so frameworks can mount a minimal stage.
 * If no canvas exists under `root`, one is created automatically.
 */
export function collectStageElements(root: HTMLElement): StageElements {
  return {
    canvas: requireCanvas(root),
    runtimeStatus: optionalElement(root, STAGE_ROLES.runtimeStatus),
    backendBadge: optionalElement(root, STAGE_ROLES.backendBadge),
    frameBadge: optionalElement(root, STAGE_ROLES.frameBadge),
    focusStat: optionalElement(root, STAGE_ROLES.focusStat),
    viewportStat: optionalElement(root, STAGE_ROLES.viewportStat),
    overlayTitle: optionalElement(root, STAGE_ROLES.overlayTitle),
    overlayCopy: optionalElement(root, STAGE_ROLES.overlayCopy),
    deltaStat: optionalElement(root, STAGE_ROLES.deltaStat),
    fpsStat: optionalElement(root, STAGE_ROLES.fpsStat),
    commandStat: optionalElement(root, STAGE_ROLES.commandStat),
    textStat: optionalElement(root, STAGE_ROLES.textStat),
    pointStat: optionalElement(root, STAGE_ROLES.pointStat),
    importStat: optionalElement(root, STAGE_ROLES.importStat),
    exportList: optionalElement(root, STAGE_ROLES.exportList),
    importList: optionalElement(root, STAGE_ROLES.importList),
    diagnostics: optionalElement(root, STAGE_ROLES.diagnostics),
  };
}

function isStageElements(value: HTMLElement | StageElements): value is StageElements {
  return "canvas" in value && value.canvas instanceof HTMLCanvasElement;
}

/**
 * Mount the Zig/WASM stage into any host DOM.
 *
 * @example Vanilla / Astro
 * ```ts
 * await mountStage(document.querySelector("[data-zt-stage-root]"), {
 *   wasmUrl: "/wasm/app.wasm",
 *   hostLabel: "Astro host",
 * });
 * ```
 *
 * @example Next.js client component
 * ```ts
 * useEffect(() => {
 *   let stage: MountedStage | undefined;
 *   void mountStage(rootRef.current!, { hostLabel: "Next.js host" }).then((s) => {
 *     stage = s;
 *   });
 *   return () => stage?.destroy();
 * }, []);
 * ```
 */
export async function mountStage(
  target: HTMLElement | StageElements,
  options: MountOptions = {},
): Promise<MountedStage> {
  const elements = isStageElements(target) ? target : collectStageElements(target);
  const runtime = createStageRuntime(elements, options);
  await runtime.mount();
  return runtime;
}
