/**
 * Normalized AudioEvent helpers matching `src/platform/audio_events.zig`.
 * The Zig runtime owns sequence state; this host only produces the seam payloads.
 */

export function nowMs(originMs) {
  return Date.now() - originMs;
}

export function makeSequenceId() {
  return `seq_${Date.now().toString(36)}`;
}

export function permissionChanged(sequenceId, state = "granted") {
  return {
    type: "permission_changed",
    sequence_id: sequenceId,
    state,
  };
}

export function segmentStarted(sequenceId, segmentId, kind, startMs) {
  return {
    type: "segment_started",
    sequence_id: sequenceId,
    segment_id: segmentId,
    kind,
    start_ms: startMs,
  };
}

export function transcriptDelta(sequenceId, segmentId, text, isFinal = false) {
  return {
    type: "transcript_delta",
    sequence_id: sequenceId,
    segment_id: segmentId,
    text,
    is_final: isFinal,
  };
}

export function segmentCompleted(sequenceId, segmentId, endMs) {
  return {
    type: "segment_completed",
    sequence_id: sequenceId,
    segment_id: segmentId,
    end_ms: endMs,
  };
}

export function toolCall(sequenceId, segmentId, toolName, status, latencyMs = null) {
  return {
    type: "tool_call",
    sequence_id: sequenceId,
    segment_id: segmentId,
    tool_name: toolName,
    status,
    latency_ms: latencyMs,
  };
}

export function sequenceCompleted(sequenceId, completedAtMs) {
  return {
    type: "sequence_completed",
    sequence_id: sequenceId,
    completed_at_ms: completedAtMs,
  };
}

export function errorEvent(code, message, atMs, sequenceId = null, segmentId = null) {
  return {
    type: "error_",
    sequence_id: sequenceId,
    segment_id: segmentId,
    code,
    message,
    at_ms: atMs,
  };
}

/** Collapse SSE token chunks into coarse transcript deltas for the panel. */
export function chunkText(buffer, next, minChars = 24) {
  const combined = buffer + next;
  if (combined.length < minChars) {
    return { emit: null, rest: combined };
  }
  return { emit: combined, rest: "" };
}
