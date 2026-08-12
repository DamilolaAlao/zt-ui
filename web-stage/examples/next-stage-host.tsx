/**
 * Reference Next.js client host for `@zt-ui/stage`.
 * Copy into an App Router project as a Client Component.
 *
 * Prerequisites:
 * - `zig build wasm` → copy `web/app.wasm` to `public/wasm/app.wasm`
 * - depend on `@zt-ui/stage` (file:../web-stage in this monorepo)
 */
"use client";

import { useEffect, useRef } from "react";
import { mountStage, type MountedStage } from "@zt-ui/stage";

export function ZtStageHost({
  wasmUrl = "/wasm/app.wasm",
  className,
}: {
  wasmUrl?: string;
  className?: string;
}) {
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;

    let stage: MountedStage | undefined;
    let cancelled = false;

    void mountStage(root, {
      wasmUrl,
      hostLabel: "Next.js host",
    }).then((mounted) => {
      if (cancelled) {
        mounted.destroy();
        return;
      }
      stage = mounted;
    });

    return () => {
      cancelled = true;
      stage?.destroy();
    };
  }, [wasmUrl]);

  return (
    <div ref={rootRef} className={className} data-zt-stage-root>
      <canvas
        data-role="dashboard-canvas"
        tabIndex={0}
        aria-label="Zig immediate mode stage canvas"
        style={{ display: "block", width: "100%", height: "100%", minHeight: 480 }}
      />
    </div>
  );
}
