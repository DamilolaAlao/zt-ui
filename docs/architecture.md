# Architecture

`zt-ui` is organized around a strict runtime boundary:

```text
JS platform
  ↓
Zig app runtime (WASM)
  ↓
Render backend
  ↓
Frame arena + command list
  ↓
UI layer
  ↓
App code
```

## Layer Responsibilities

`web/`

- Zero-dep Canvas2D boot — `boot.js` wires WASM → pixels with no framework tax.

`web-stage/` (`@zt-ui/stage`)

- Portable stage seam: mount, input fan-in, Canvas2D paint, contracts.
- Drop into Astro, Next.js, or vanilla — chrome is swappable, the seam is not.

`web-astro/`

- Astro chrome surface over `@zt-ui/stage` — demo host, not a private bridge fork.

`src/dev`

- Owns the local Zig development server used to serve `web/` without external tooling.
- Should stay small, predictable, and testable rather than turning into deployment infrastructure.

`src/platform`

- Defines the browser-facing ABI.
- Stores input snapshots and frame timing in plain data.

`src/gfx`

- Owns the command records, text payloads, point buffers, and renderer frame lifecycle.
- Should stay free of widget logic.

`src/ui`

- Owns widget ids, interaction rules, stack layout, clipping, and theme values.
- Emits commands through the renderer instead of drawing directly.

`src/app`

- Owns the concrete reference dashboard.
- Should absorb product-specific behavior before generic extraction happens.

`src/debug`

- Owns overlay rendering and profiling output.
- Must remain optional and cheap enough to keep enabled during development.

## Rules Worth Preserving

- App state stays plain data.
- Input is queried, not subscribed.
- Widgets emit commands; they do not own a retained tree.
- Stable widget ids are mandatory for interaction.
- Reuse follows proven repetition, not speculation.

## Extraction Policy

If a primitive appears only once, keep it in `src/app`.

Move code into `src/ui` only when:

- the interaction rule repeats,
- the layout behavior repeats, or
- the renderer contract would otherwise diverge across callers.
