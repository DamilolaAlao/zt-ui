/** Stable data-role selectors every host can bind against. */
export const STAGE_ROLES = {
  canvas: "dashboard-canvas",
  runtimeStatus: "runtime-status",
  backendBadge: "backend-badge",
  frameBadge: "frame-badge",
  focusStat: "focus-stat",
  viewportStat: "viewport-stat",
  overlayTitle: "overlay-title",
  overlayCopy: "overlay-copy",
  deltaStat: "delta-stat",
  fpsStat: "fps-stat",
  commandStat: "command-stat",
  textStat: "text-stat",
  pointStat: "point-stat",
  importStat: "import-stat",
  exportList: "export-list",
  importList: "import-list",
  diagnostics: "diagnostics-log",
} as const;

export type StageRole = (typeof STAGE_ROLES)[keyof typeof STAGE_ROLES];

export function roleSelector(role: StageRole): string {
  return `[data-role="${role}"]`;
}
