# Public Release Checklist

Use this checklist before publishing `zt-ui` as a public repository.

## Repository Hygiene

- Confirm `.gitignore` excludes build outputs and local editor noise.
- Keep generated artifacts such as `web/app.wasm`, `zig-out/`, and `.zig-cache/` out of version control.
- Remove temporary notes, scratch files, and local-only experiments before tagging or publishing.

## Policy Surface

- Verify `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and `CONTRIBUTING.md` are present.
- Configure the repository host's private vulnerability reporting feature if available.
- Replace any placeholder moderation or reporting routes with real maintainer-owned channels when they exist.

## Technical Checks

- Run `zig build test`.
- Run `zig build`.
- Run `zig build serve` and verify the local Zig dev server starts cleanly.
- Verify the browser host starts cleanly and loads the generated wasm module.
- Confirm the exported ABI and README instructions still match the code.

## Public Readiness

- Make sure screenshots, names, metrics, and sample logs are intentionally fictional or generic.
- Keep README language aligned with the actual product surface.
- Avoid promising features that do not exist yet.
