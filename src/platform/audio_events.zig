const std = @import("std");

pub const AudioPermissionState = enum {
    unknown,
    prompt,
    granted,
    denied,
};

pub const AudioEventSegmentKind = enum {
    user_speech,
    assistant_speech,
    silence,
    sound_effect,
    background_audio,
    tool_call,
    interruption,
};

pub const AudioToolCallStatus = enum {
    pending,
    running,
    completed,
    failed,
};

pub const AudioInterruptionReason = enum {
    user_barge_in,
    playback_cancelled,
    timeout,
    system_cancelled,
};

pub const AudioPermissionEvent = struct {
    sequence_id: ?[]const u8 = null,
    state: AudioPermissionState,
};

pub const AudioInputLevelEvent = struct {
    sequence_id: []const u8,
    level_normalized: f32,
    peak_normalized: ?f32 = null,
    at_ms: u64,
};

pub const AudioSegmentStartedEvent = struct {
    sequence_id: []const u8,
    segment_id: []const u8,
    kind: AudioEventSegmentKind,
    start_ms: u64,
};

pub const TranscriptDeltaEvent = struct {
    sequence_id: []const u8,
    segment_id: []const u8,
    text: []const u8,
    is_final: bool = false,
};

pub const AudioDeltaEvent = struct {
    sequence_id: []const u8,
    segment_id: []const u8,
    audio_base64: ?[]const u8 = null,
    byte_len: ?u32 = null,
};

pub const ToolCallEvent = struct {
    sequence_id: []const u8,
    segment_id: []const u8,
    tool_name: []const u8,
    status: AudioToolCallStatus = .pending,
    latency_ms: ?u64 = null,
};

pub const InterruptionEvent = struct {
    sequence_id: []const u8,
    target_segment_id: []const u8,
    at_ms: u64,
    reason: AudioInterruptionReason,
};

pub const AudioSegmentCompletedEvent = struct {
    sequence_id: []const u8,
    segment_id: []const u8,
    end_ms: u64,
};

pub const SequenceCompletedEvent = struct {
    sequence_id: []const u8,
    completed_at_ms: u64,
};

pub const AudioErrorEvent = struct {
    sequence_id: ?[]const u8 = null,
    segment_id: ?[]const u8 = null,
    code: []const u8,
    message: []const u8,
    at_ms: u64,
};

pub const AudioEvent = union(enum) {
    permission_changed: AudioPermissionEvent,
    input_level: AudioInputLevelEvent,
    segment_started: AudioSegmentStartedEvent,
    transcript_delta: TranscriptDeltaEvent,
    audio_delta: AudioDeltaEvent,
    tool_call: ToolCallEvent,
    interruption: InterruptionEvent,
    segment_completed: AudioSegmentCompletedEvent,
    sequence_completed: SequenceCompletedEvent,
    error_: AudioErrorEvent,
};

test "audio event union carries normalized payloads" {
    const event: AudioEvent = .{
        .segment_started = .{
            .sequence_id = "seq_001",
            .segment_id = "a1",
            .kind = .assistant_speech,
            .start_ms = 1_200,
        },
    };

    switch (event) {
        .segment_started => |payload| {
            try std.testing.expectEqualStrings("seq_001", payload.sequence_id);
            try std.testing.expectEqual(.assistant_speech, payload.kind);
        },
        else => return error.UnexpectedEventTag,
    }
}
