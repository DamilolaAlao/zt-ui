# Stage Seam (`web-stage/`)

`@zt-ui/stage` lives in `web-stage/` — the portable browser seam for Zig/WASM. One mount API, any host chrome.

## Ownership

```text
Host chrome (Astro | Next.js | vanilla | …)
  ↓ mountStage(root, options)
@zt-ui/stage  (web-stage/)
  ↓ input + beginFrame
Zig WASM (app.wasm)
  ↓ command / text / point buffers
Canvas2D paint
```

| Layer | Owns |
| --- | --- |
| Host | Layout, docs, DOM telemetry, routing — the surfaces that want a framework |
| `@zt-ui/stage` | WASM boot, input fan-in, frame loop, Canvas2D paint — the hot path |
| Zig | State, widgets, command emission — the stage itself |

**Rule:** Chrome is swappable. The stage seam is not.

## Hosts

| Host | Path | Role |
| --- | --- | --- |
| Zero-dep reference | `web/` | Bare-metal Canvas2D boot — `boot.js` wires WASM → pixels with no framework tax |
| Stage seam | `web-stage/` | `@zt-ui/stage` — the portable seam: mount, input, paint, contracts |
| Astro surface | `web-astro/` | Luminous chrome host — same stage API, swap-in for Next or vanilla |

## Layout

```text
web-stage/
  package.json          # @zt-ui/stage
  src/
    index.ts
    contracts.ts
    roles.ts
    mount.ts
    runtime.ts
    renderer.ts
    snapshot.ts
  examples/
    next-stage-host.tsx
    vanilla-mount.ts
web-astro/              # Astro chrome surface over @zt-ui/stage
web/                    # zero-dep Canvas2D reference boot
```

## Runtime contract

Same Zig surface every host uses:

- `initRuntime` / `resize` / `beginFrame`
- `pointerMove` / `pointerButton` / `pointerWheel` / `keyEvent`
- `getCommandsPtr/Len` / `getTextPtr/Len` / `getPointsPtr/Len` / `memory`
- optional `getSnapshotPtr/Len`

## Mount API

```ts
import { mountStage, STAGE_ROLES } from "@zt-ui/stage";

const stage = await mountStage(root, {
  wasmUrl: "/wasm/app.wasm",
  hostLabel: "Astro host", // or "Next.js host", etc.
  onFrame: (stats) => {},
  onStatus: (status) => {},
  onSnapshot: (snap) => {},
});

stage.destroy();
```

Only a canvas is required (`data-role="dashboard-canvas"`). Missing chrome roles are optional. If no canvas exists under the root, the seam creates one.

## Astro host

```sh
zig build wasm
cd web-astro && npm install && npm run dev
```

Astro depends on `@zt-ui/stage` via `file:../web-stage` and imports `mountStage` from that package — it does not embed a private stage copy.

## Next.js host

Copy `web-stage/examples/next-stage-host.tsx`, place `app.wasm` at `public/wasm/app.wasm`, mount from a Client Component in `useEffect`.

## Vanilla host

The original `web/` boot path remains the reference static host. New embeds can use `web-stage/examples/vanilla-mount.ts` against `@zt-ui/stage`.

## Design rule

- Do not reimplement Zig widgets as framework components.
- Keep dense, high-frequency UI on the canvas stage.
- Put forms, docs, nav, and a11y-heavy surfaces in the host chrome.
