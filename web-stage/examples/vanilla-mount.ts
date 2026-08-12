/**
 * Minimal vanilla host — drop into any static page after bundling `@zt-ui/stage`.
 */
import { mountStage } from "@zt-ui/stage";

const root = document.querySelector("[data-zt-stage-root]");
if (root instanceof HTMLElement) {
  void mountStage(root, {
    wasmUrl: "/wasm/app.wasm",
    hostLabel: "Vanilla host",
  });
}
