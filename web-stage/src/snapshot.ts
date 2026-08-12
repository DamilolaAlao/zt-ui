import type { RuntimeSnapshot, ZtRuntimeExports } from "./contracts";

const decoder = new TextDecoder();

export function readRuntimeSnapshot(
  exports: ZtRuntimeExports,
  memory: WebAssembly.Memory,
): RuntimeSnapshot | null {
  if (typeof exports.getSnapshotPtr !== "function" || typeof exports.getSnapshotLen !== "function") {
    return null;
  }

  const length = Number(exports.getSnapshotLen());
  if (length <= 0) return null;

  const pointer = Number(exports.getSnapshotPtr());
  if (pointer <= 0) return null;

  try {
    const bytes = new Uint8Array(memory.buffer, pointer, length);
    const text = decoder.decode(bytes);
    return JSON.parse(text) as RuntimeSnapshot;
  } catch {
    return null;
  }
}
