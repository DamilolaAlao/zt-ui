# Testing

The project follows a test-first posture for seams that are easy to break and hard to debug by feel alone.

## What To Protect

- stable widget id generation,
- input transitions across frames,
- layout and clipping behavior,
- renderer payload lengths and pointer access,
- app-state transitions that drive visible UI behavior.

## Core Commands

```sh
zig build test
zig build
zig build serve
```

`zig build serve` rebuilds `web/app.wasm` first and then serves the browser host from `http://127.0.0.1:8080`.

## Expected Workflow

1. Add or adjust a test before changing a behavior rule.
2. Run `zig build test`.
3. Run `zig build`.
4. Run `zig build serve` if the change affects rendering, input, layout, or exported ABI.
5. Verify the browser host in the browser.

## Browser Verification Checklist

- The canvas initializes without runtime errors.
- Metrics update once the module is loaded.
- The overlay toggles with <kbd>`</kbd>.
- The guide grid toggles with <kbd>G</kbd>.
- Scroll, hover, and button interactions remain stable.

## When A Test Is Required

Add a test when you:

- change widget identity rules,
- alter input edge transitions,
- modify renderer buffer ownership or lengths,
- update scrolling behavior,
- change state evolution that feeds the dashboard.
