# Public Release Checklist

Use this checklist before publishing `zt-ui` as a public repository.

## Release Tag Pattern

- Release tags must follow `vYYYY.M.D`.
- Example: `v2026.4.9`.
- The GitHub release workflow rejects tags that do not match that pattern.

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

## Packaging And Publishing

- Pushing a tag such as `v2026.4.9` triggers `.github/workflows/release.yml`.
- The workflow runs the Zig test suite, builds the release bundle, and publishes a GitHub Release named after the tag.
- Release assets include:
  - `zt-ui-vYYYY.M.D-web.tar.gz`
  - `zt-ui-vYYYY.M.D-web.zip`
  - `zt-ui-vYYYY.M.D-linux-amd64.tar.gz`
  - `checksums.txt`
- The Linux archive contains the packaged `zt-ui-serve` binary plus the `web/` runtime assets for direct extraction and local serving.
- The same workflow publishes a multi-arch container image to GitHub Container Registry:
  - `ghcr.io/<owner>/<repo>:vYYYY.M.D`
  - `ghcr.io/<owner>/<repo>:latest`
- The container publish step emits SBOM and provenance metadata through the Docker GitHub Actions pipeline.

## Public Readiness

- Make sure screenshots, names, metrics, and sample logs are intentionally fictional or generic.
- Keep README language aligned with the actual product surface.
- Avoid promising features that do not exist yet.
