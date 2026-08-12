# `@zt-ui/stage` — stage seam

Drop Zig’s immediate-mode stage into any browser host.

**Chrome is yours. The seam is ours.**

```text
Host (Astro | Next.js | vanilla | …)
  ↓ mountStage(root)
@zt-ui/stage
  ↓ input + beginFrame
Zig WASM (app.wasm)
  ↓ command / text / point buffers
Canvas2D renderer
```

## Install (in-repo)

```sh
# from web-astro or another host package.json
npm install ../web-stage
```

```json
{
  "dependencies": {
    "@zt-ui/stage": "file:../web-stage"
  }
}
```

## API

```ts
import {
  mountStage,
  collectStageElements,
  STAGE_ROLES,
  type MountedStage,
  type MountOptions,
} from "@zt-ui/stage";

const stage = await mountStage(rootElement, {
  wasmUrl: "/wasm/app.wasm",
  hostLabel: "Next.js host",
  onFrame: (stats) => console.log(stats.fps),
  onSnapshot: (snap) => {},
  onStatus: (status) => {},
});

stage.destroy();
```

### Required DOM

Only a canvas is required. If missing, `mountStage` creates one under the root.

Optional chrome uses stable `data-role` values from `STAGE_ROLES` (telemetry, overlay, exports list, etc.).

### Zig contract

Unchanged: `initRuntime` / `resize` / `beginFrame`, pointer + key input, `getCommands*` / `getText*` / `getPoints*` / `memory`, optional `getSnapshot*`.

## Hosts in this repo

| Host | Path | Role |
| --- | --- | --- |
| Zero-dep reference | `web/` | Bare-metal Canvas2D boot — `boot.js` wires WASM → pixels with no framework tax |
| Stage seam | `web-stage/` | `@zt-ui/stage` — the portable seam: mount, input, paint, contracts |
| Astro surface | `web-astro/` | Luminous chrome host — same stage API, swap-in for Next or vanilla |

## Next.js

See `examples/next-stage-host.tsx`. Use a Client Component, mount in `useEffect`, put `app.wasm` at `public/wasm/app.wasm`.

## Build wasm

```sh
zig build wasm
```

Syncs into `web/app.wasm` and `web-astro/public/wasm/app.wasm`.
