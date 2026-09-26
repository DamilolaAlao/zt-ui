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
  - `zt-ui-vYYYY.M.D-macos.zip`
  - `zt-ui-vYYYY.M.D-macos-mlx.zip.part-*`
  - `checksums.txt`
- The Linux archive contains the packaged `zt-ui-serve` binary plus the `web/` runtime assets for direct extraction and local serving.
- The macOS zip contains `zt-ui Desktop.app`, a universal (Apple Silicon and Intel) bundle for macOS 13+. The release job signs it with the Developer ID certificate in `APPLE_CERTIFICATE_P12` / `APPLE_SIGNING_IDENTITY`, then notarizes it with `APPLE_API_KEY`, `APPLE_API_KEY_ID`, and `APPLE_API_ISSUER`. Set `APPLE_CERTIFICATE_PASSWORD` when the `.p12` has a password.
- The macOS MLX build is an Apple Silicon-only `zt-ui LFM2.5.app` with [`LiquidAI/LFM2.5-2.6B-MLX-bf16`](https://huggingface.co/LiquidAI/LFM2.5-2.6B-MLX-bf16) embedded. Before the GitHub split, the workflow uploads the full zip to [Tigris](https://www.tigrisdata.com/docs/sdks/s3/) at `s3://$TIGRIS_BUCKET/zt-ui/vYYYY.M.D/zt-ui-vYYYY.M.D-macos-mlx.zip` (`https://t3.storage.dev`). The object inherits the bucket access policy. When that bucket is public, the file is also at `https://$TIGRIS_BUCKET.t3.tigrisfiles.io/...`. Set the `TIGRIS_BUCKET` repository variable and the `TIGRIS_ACCESS_KEY_ID` / `TIGRIS_SECRET_ACCESS_KEY` secrets. GitHub release assets must be under 2 GiB, so a split copy is also published. Reassemble with `cat zt-ui-vYYYY.M.D-macos-mlx.zip.part-* > zt-ui-vYYYY.M.D-macos-mlx.zip`.
- The same workflow publishes a multi-arch container image to GitHub Container Registry:
  - `ghcr.io/<owner>/<repo>:vYYYY.M.D`
  - `ghcr.io/<owner>/<repo>:latest`
- The container publish step emits SBOM and provenance metadata through the Docker GitHub Actions pipeline.

## Public Readiness

- Make sure screenshots, names, metrics, and sample logs are intentionally fictional or generic.
- Keep README language aligned with the actual product surface.
- Avoid promising features that do not exist yet.
