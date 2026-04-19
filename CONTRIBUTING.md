# Contributing

`zt-ui` is meant to stay useful as a public reference implementation, so contributions should make the architecture clearer, sturdier, or more demonstrably capable.

## Working Agreement

- Prefer plain data over hidden state or retained trees.
- Keep rendering command-buffered; widgets should emit commands, not draw directly.
- Reach for the specific dashboard use case first. Only extract reusable primitives after repetition is obvious.
- Add or update tests when hardening input, layout, ids, renderer payloads, or state transitions.
- Keep browser-hosted WASM as the primary development path unless there is a strong reason not to.
- Avoid flashy or novelty-heavy UI changes. The reference app should feel serious, polished, and credible.
- Treat the WASM export surface and command ABI as public contract, even if the project is still early.

## Typical Workflow

1. Run `zig build test`.
2. Run `zig build`.
3. Run `zig build serve` and verify the browser host.
4. Update docs when the public shape of the repo changes.
5. Keep generated build artifacts out of Git unless the project policy changes.

## Pull Requests

- Keep PRs focused on one architectural change, feature slice, or bug fix.
- Explain the runtime impact if you touch exported functions, command records, or browser decoding.
- Include screenshots or short notes when visible behavior changes.
- Update `docs/architecture.md` or `docs/testing.md` if the working model changes.

## Areas That Need Care

- Text rendering and future atlas work.
- Command ABI evolution between Zig and the browser renderer.
- Layout behavior and stable widget ids.
- The line-chart path, especially if generalized.

If you are unsure whether something belongs in `src/ui` or `src/app`, bias toward `src/app` until the abstraction pressure is real.
