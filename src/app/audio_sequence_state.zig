const std = @import("std");
const audio_events = @import("../platform/audio_events.zig");

pub const ValidationError = error{
    DuplicateSegmentId,
    InvalidSegmentRange,
    DurationMismatch,
    MissingAssistantPayload,
    MissingUserPayload,
    MissingToolName,
    MissingInterruptionTarget,
    InvalidVoiceSpeed,
    InvalidVoicePitch,
    InvalidVoiceGain,
};

pub const AudioSequenceState = enum {
    idle,
    listening,
    transcribing,
    thinking,
    speaking,
    interrupted,
    completed,
    error_,
};

pub const AudioSegmentKind = enum {
    user_speech,
    assistant_speech,
    silence,
    sound_effect,
    background_audio,
    tool_call,
    interruption,
};

pub const AudioSegmentStatus = enum {
    pending,
    streaming,
    completed,
    cancelled,
    failed,
};

pub const VoiceStyle = enum {
    neutral,
    friendly,
    formal,
    calm,
    excited,
    serious,
};

pub const VoiceEmotion = enum {
    neutral,
    happy,
    sad,
    concerned,
    energetic,
};

pub const VoiceSpec = struct {
    voice_id: []const u8,
    provider: ?[]const u8 = null,
    style: VoiceStyle = .neutral,
    emotion: VoiceEmotion = .neutral,
    speed: f32 = 1.0,
    pitch_semitones: f32 = 0.0,
    gain_db: f32 = 0.0,

    pub fn validate(self: VoiceSpec) ValidationError!void {
        if (self.speed < 0.5 or self.speed > 2.0) return ValidationError.InvalidVoiceSpeed;
        if (self.pitch_semitones < -12.0 or self.pitch_semitones > 12.0) return ValidationError.InvalidVoicePitch;
        if (self.gain_db < -24.0 or self.gain_db > 12.0) return ValidationError.InvalidVoiceGain;
    }
};

pub const ToolCallStatus = enum {
    pending,
    running,
    completed,
    failed,
};

pub const ToolCallSpec = struct {
    tool_name: []const u8,
    input_json: []const u8,
    output_json: ?[]const u8 = null,
    status: ToolCallStatus = .pending,
    latency_ms: ?u64 = null,
};

pub const InterruptionReason = enum {
    user_barge_in,
    playback_cancelled,
    timeout,
    system_cancelled,
};

pub const InterruptionSpec = struct {
    target_segment_id: []const u8,
    at_ms: u64,
    reason: InterruptionReason,
};

pub const AudioSequenceMetrics = struct {
    input_audio_ms: u64 = 0,
    assistant_audio_ms: u64 = 0,
    transcription_latency_ms: ?u64 = null,
    first_token_latency_ms: ?u64 = null,
    first_audio_latency_ms: ?u64 = null,
    total_response_latency_ms: ?u64 = null,
    interruption_count: u32 = 0,
    tool_call_count: u32 = 0,
    error_count: u32 = 0,
};

pub const AudioSegment = struct {
    id: []const u8,
    kind: AudioSegmentKind,
    start_ms: u64 = 0,
    end_ms: ?u64 = null,
    duration_ms: ?u64 = null,
    text: ?[]const u8 = null,
    transcript: ?[]const u8 = null,
    audio_uri: ?[]const u8 = null,
    confidence: ?f32 = null,
    voice: ?VoiceSpec = null,
    tool_call: ?ToolCallSpec = null,
    interruption: ?InterruptionSpec = null,
    status: AudioSegmentStatus = .pending,

    pub fn displayText(self: AudioSegment) []const u8 {
        if (self.transcript) |value| return value;
        if (self.text) |value| return value;
        if (self.tool_call) |value| return value.tool_name;
        if (self.interruption) |_| return "Interruption";
        return "Waiting for audio payload";
    }

    pub fn resolvedDurationMs(self: AudioSegment) ?u64 {
        if (self.duration_ms) |value| return value;
        if (self.end_ms) |end_ms| {
            if (end_ms < self.start_ms) return null;
            return end_ms - self.start_ms;
        }
        return null;
    }
};

pub const AudioSequence = struct {
    id: []const u8,
    version: []const u8 = "1.0",
    session_id: ?[]const u8 = null,
    conversation_id: ?[]const u8 = null,
    language: []const u8 = "en-US",
    sample_rate_hz: u32 = 24_000,
    channels: u8 = 1,
    state: AudioSequenceState = .idle,
    started_at_ms: u64 = 0,
    updated_at_ms: u64 = 0,
    segments: []AudioSegment,
    metrics: AudioSequenceMetrics = .{},

    pub fn totalDurationMs(self: AudioSequence) u64 {
        var max_ms = self.updated_at_ms;
        for (self.segments) |segment| {
            max_ms = @max(max_ms, segment.start_ms);
            if (segment.end_ms) |end_ms| {
                max_ms = @max(max_ms, end_ms);
            }
        }
        return max_ms;
    }

    pub fn currentSegment(self: *const AudioSequence, position_ms: u64) ?*const AudioSegment {
        for (self.segments) |*segment| {
            if (position_ms < segment.start_ms) continue;
            if (segment.end_ms) |end_ms| {
                if (position_ms <= end_ms) return segment;
            } else {
                return segment;
            }
        }
        return null;
    }

    pub fn findSegment(self: *const AudioSequence, id: []const u8) ?*const AudioSegment {
        for (self.segments) |*segment| {
            if (std.mem.eql(u8, segment.id, id)) return segment;
        }
        return null;
    }

    pub fn validate(self: *const AudioSequence) ValidationError!void {
        for (self.segments, 0..) |segment, index| {
            var compare_index = index + 1;
            while (compare_index < self.segments.len) : (compare_index += 1) {
                if (std.mem.eql(u8, segment.id, self.segments[compare_index].id)) {
                    return ValidationError.DuplicateSegmentId;
                }
            }

            if (segment.end_ms) |end_ms| {
                if (end_ms < segment.start_ms) return ValidationError.InvalidSegmentRange;
                if (segment.duration_ms) |duration_ms| {
                    if (duration_ms != end_ms - segment.start_ms) return ValidationError.DurationMismatch;
                }
            }

            if (segment.voice) |voice| {
                try voice.validate();
            }

            switch (segment.kind) {
                .assistant_speech => {
                    if (segment.text == null and segment.audio_uri == null) {
                        return ValidationError.MissingAssistantPayload;
                    }
                },
                .user_speech => {
                    if (segment.transcript == null and segment.audio_uri == null) {
                        return ValidationError.MissingUserPayload;
                    }
                },
                .tool_call => {
                    const tool_call = segment.tool_call orelse return ValidationError.MissingToolName;
                    if (tool_call.tool_name.len == 0) return ValidationError.MissingToolName;
                },
                .interruption => {
                    const interruption = segment.interruption orelse return ValidationError.MissingInterruptionTarget;
                    if (self.findSegment(interruption.target_segment_id) == null) {
                        return ValidationError.MissingInterruptionTarget;
                    }
                },
                else => {},
            }
        }
    }
};

const max_segments = 12;
const max_string_bytes = 4096;
const live_sequence_id = "seq_live_001";

const completed_demo_segments = [_]AudioSegment{
    .{
        .id = "u1",
        .kind = .user_speech,
        .start_ms = 0,
        .end_ms = 1_800,
        .duration_ms = 1_800,
        .transcript = "Show me the latest error spike.",
        .confidence = 0.96,
        .status = .completed,
    },
    .{
        .id = "tool1",
        .kind = .tool_call,
        .start_ms = 1_900,
        .end_ms = 2_600,
        .duration_ms = 700,
        .tool_call = .{
            .tool_name = "metrics.query",
            .input_json = "{\"metric\":\"errors\",\"window\":\"15m\"}",
            .output_json = "{\"cluster\":\"api-gateway\",\"spike_start\":\"-6m\"}",
            .status = .completed,
            .latency_ms = 700,
        },
        .status = .completed,
    },
    .{
        .id = "a1",
        .kind = .assistant_speech,
        .start_ms = 2_800,
        .end_ms = 7_400,
        .duration_ms = 4_600,
        .text = "There was an error spike starting six minutes ago, concentrated in the API gateway.",
        .voice = .{
            .voice_id = "ops_default",
            .style = .calm,
            .emotion = .neutral,
        },
        .status = .completed,
    },
};

const TimedAudioEvent = struct {
    at_ms: u64,
    event: audio_events.AudioEvent,
};

const replay_events = [_]TimedAudioEvent{
    .{ .at_ms = 0, .event = .{ .permission_changed = .{ .sequence_id = live_sequence_id, .state = .granted } } },
    .{ .at_ms = 0, .event = .{ .segment_started = .{ .sequence_id = live_sequence_id, .segment_id = "u1", .kind = .user_speech, .start_ms = 0 } } },
    .{ .at_ms = 120, .event = .{ .input_level = .{ .sequence_id = live_sequence_id, .level_normalized = 0.34, .peak_normalized = 0.52, .at_ms = 120 } } },
    .{ .at_ms = 420, .event = .{ .transcript_delta = .{ .sequence_id = live_sequence_id, .segment_id = "u1", .text = "Show me the latest ", .is_final = false } } },
    .{ .at_ms = 940, .event = .{ .input_level = .{ .sequence_id = live_sequence_id, .level_normalized = 0.61, .peak_normalized = 0.77, .at_ms = 940 } } },
    .{ .at_ms = 1_140, .event = .{ .transcript_delta = .{ .sequence_id = live_sequence_id, .segment_id = "u1", .text = "error spike.", .is_final = true } } },
    .{ .at_ms = 1_800, .event = .{ .segment_completed = .{ .sequence_id = live_sequence_id, .segment_id = "u1", .end_ms = 1_800 } } },
    .{ .at_ms = 1_900, .event = .{ .segment_started = .{ .sequence_id = live_sequence_id, .segment_id = "tool1", .kind = .tool_call, .start_ms = 1_900 } } },
    .{ .at_ms = 2_000, .event = .{ .tool_call = .{ .sequence_id = live_sequence_id, .segment_id = "tool1", .tool_name = "metrics.query", .status = .running, .latency_ms = null } } },
    .{ .at_ms = 2_600, .event = .{ .tool_call = .{ .sequence_id = live_sequence_id, .segment_id = "tool1", .tool_name = "metrics.query", .status = .completed, .latency_ms = 700 } } },
    .{ .at_ms = 2_600, .event = .{ .segment_completed = .{ .sequence_id = live_sequence_id, .segment_id = "tool1", .end_ms = 2_600 } } },
    .{ .at_ms = 2_800, .event = .{ .segment_started = .{ .sequence_id = live_sequence_id, .segment_id = "a1", .kind = .assistant_speech, .start_ms = 2_800 } } },
    .{ .at_ms = 3_200, .event = .{ .transcript_delta = .{ .sequence_id = live_sequence_id, .segment_id = "a1", .text = "There was an error spike ", .is_final = false } } },
    .{ .at_ms = 4_700, .event = .{ .transcript_delta = .{ .sequence_id = live_sequence_id, .segment_id = "a1", .text = "starting six minutes ago, ", .is_final = false } } },
    .{ .at_ms = 6_100, .event = .{ .transcript_delta = .{ .sequence_id = live_sequence_id, .segment_id = "a1", .text = "concentrated in the API gateway.", .is_final = true } } },
    .{ .at_ms = 7_400, .event = .{ .segment_completed = .{ .sequence_id = live_sequence_id, .segment_id = "a1", .end_ms = 7_400 } } },
    .{ .at_ms = 9_200, .event = .{ .sequence_completed = .{ .sequence_id = live_sequence_id, .completed_at_ms = 9_200 } } },
};

const replay_end_ms = replay_events[replay_events.len - 1].at_ms;

pub fn demoSequence(segments: []AudioSegment) AudioSequence {
    return .{
        .id = "seq_ops_001",
        .version = "1.0",
        .language = "en-US",
        .sample_rate_hz = 24_000,
        .channels = 1,
        .state = .completed,
        .started_at_ms = 0,
        .updated_at_ms = 9_200,
        .segments = segments,
        .metrics = .{
            .input_audio_ms = 1_800,
            .assistant_audio_ms = 4_600,
            .transcription_latency_ms = 420,
            .first_token_latency_ms = 1_160,
            .first_audio_latency_ms = 2_800,
            .total_response_latency_ms = 7_400,
            .tool_call_count = 1,
        },
    };
}

pub const AudioDemoMode = enum {
    completed_demo,
    live_replay,
};

pub const AudioDemoState = struct {
    active_sequence_index: usize = 0,
    sequences: [1]AudioSequence = undefined,
    playback_position_ms: u64 = 0,
    is_playing: bool = true,
    selected_segment_id: ?[]const u8 = null,
    show_debug_json: bool = false,
    mode: AudioDemoMode = .completed_demo,
    permission_state: audio_events.AudioPermissionState = .unknown,
    input_level_normalized: f32 = 0.0,
    peak_input_level: f32 = 0.0,
    replay_event_index: usize = 0,
    segment_count: usize = 0,
    segment_storage: [max_segments]AudioSegment = undefined,
    string_storage: [max_string_bytes]u8 = undefined,
    string_len: usize = 0,

    pub fn init(self: *AudioDemoState) void {
        self.* = std.mem.zeroInit(AudioDemoState, .{});
        self.is_playing = true;
        self.loadCompletedDemo();
    }

    pub fn tick(self: *AudioDemoState, dt: f32, paused: bool) void {
        if (paused or !self.is_playing) return;

        const delta_ms = @as(u64, @intFromFloat(@max(0.0, dt * 1000.0)));
        if (delta_ms == 0) return;

        switch (self.mode) {
            .completed_demo => self.tickCompletedDemo(delta_ms),
            .live_replay => self.tickReplay(delta_ms),
        }
    }

    pub fn reset(self: *AudioDemoState) void {
        self.init();
    }

    pub fn startReplay(self: *AudioDemoState) void {
        self.mode = .live_replay;
        self.permission_state = .prompt;
        self.input_level_normalized = 0;
        self.peak_input_level = 0;
        self.playback_position_ms = 0;
        self.replay_event_index = 0;
        self.segment_count = 0;
        self.string_len = 0;
        self.selected_segment_id = null;
        self.is_playing = true;

        self.sequences[0] = .{
            .id = live_sequence_id,
            .version = "1.0",
            .language = "en-US",
            .sample_rate_hz = 24_000,
            .channels = 1,
            .state = .idle,
            .started_at_ms = 0,
            .updated_at_ms = 0,
            .segments = self.segment_storage[0..0],
            .metrics = .{},
        };
    }

    pub fn toggleReplayMode(self: *AudioDemoState) void {
        switch (self.mode) {
            .completed_demo => self.startReplay(),
            .live_replay => self.loadCompletedDemo(),
        }
    }

    pub fn activeSequence(self: *const AudioDemoState) *const AudioSequence {
        return &self.sequences[self.active_sequence_index];
    }

    pub fn currentSegment(self: *const AudioDemoState) ?*const AudioSegment {
        return self.activeSequence().currentSegment(self.playback_position_ms);
    }

    pub fn selectedSegment(self: *const AudioDemoState) ?*const AudioSegment {
        const segment_id = self.selected_segment_id orelse return null;
        return self.activeSequence().findSegment(segment_id);
    }

    pub fn inspectorSegment(self: *const AudioDemoState) ?*const AudioSegment {
        return self.selectedSegment() orelse self.currentSegment();
    }

    pub fn selectSegment(self: *AudioDemoState, segment_id: []const u8) void {
        self.selected_segment_id = segment_id;
    }

    pub fn clearSelection(self: *AudioDemoState) void {
        self.selected_segment_id = null;
    }

    pub fn togglePlayback(self: *AudioDemoState) void {
        self.is_playing = !self.is_playing;
    }

    pub fn modeLabel(self: *const AudioDemoState) []const u8 {
        return switch (self.mode) {
            .completed_demo => "completed demo",
            .live_replay => "live replay",
        };
    }

    pub fn permissionLabel(self: *const AudioDemoState) []const u8 {
        return @tagName(self.permission_state);
    }

    pub fn applyEvent(self: *AudioDemoState, event: audio_events.AudioEvent) void {
        switch (event) {
            .permission_changed => |payload| {
                if (payload.sequence_id) |sequence_id| {
                    if (!self.matchesActiveSequence(sequence_id)) return;
                }
                self.permission_state = payload.state;
            },
            .input_level => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                self.input_level_normalized = payload.level_normalized;
                self.peak_input_level = @max(self.peak_input_level, payload.peak_normalized orelse payload.level_normalized);
                self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, payload.at_ms);
            },
            .segment_started => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                const kind = segmentKindFromEvent(payload.kind);
                const status: AudioSegmentStatus = if (kind == .tool_call) .pending else .streaming;
                if (self.ensureSegment(payload.segment_id, kind, payload.start_ms, status)) |segment| {
                    segment.start_ms = payload.start_ms;
                    segment.status = status;
                    self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, payload.start_ms);
                    self.updateStateForSegmentStart(kind, payload.start_ms);
                }
            },
            .transcript_delta => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                const segment = self.findSegmentMutable(payload.segment_id) orelse return;
                switch (segment.kind) {
                    .assistant_speech => segment.text = self.appendString(segment.text, payload.text),
                    .user_speech => segment.transcript = self.appendString(segment.transcript, payload.text),
                    else => {},
                }
                segment.status = .streaming;
                self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, self.playback_position_ms);
            },
            .audio_delta => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                if (self.findSegmentMutable(payload.segment_id)) |segment| {
                    if (segment.audio_uri == null) {
                        segment.audio_uri = "stream://audio-delta";
                    }
                }
            },
            .tool_call => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                if (self.ensureSegment(payload.segment_id, .tool_call, self.activeSequence().updated_at_ms, .pending)) |segment| {
                    if (segment.tool_call == null) {
                        segment.tool_call = .{
                            .tool_name = self.copyString(payload.tool_name),
                            .input_json = "{}",
                            .status = toolStatusFromEvent(payload.status),
                            .latency_ms = payload.latency_ms,
                        };
                        self.activeSequenceMutable().metrics.tool_call_count += 1;
                    } else if (segment.tool_call) |*tool_call| {
                        tool_call.tool_name = self.copyString(payload.tool_name);
                        tool_call.status = toolStatusFromEvent(payload.status);
                        tool_call.latency_ms = payload.latency_ms;
                    }
                    segment.status = switch (payload.status) {
                        .completed => .completed,
                        .failed => .failed,
                        else => .streaming,
                    };
                    self.activeSequenceMutable().state = .thinking;
                }
            },
            .interruption => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;

                var id_buf: [32]u8 = undefined;
                const id_text = std.fmt.bufPrint(&id_buf, "interrupt_{d}", .{self.activeSequence().metrics.interruption_count + 1}) catch "interrupt";
                if (self.ensureSegment(id_text, .interruption, payload.at_ms, .completed)) |segment| {
                    segment.end_ms = payload.at_ms;
                    segment.duration_ms = 0;
                    segment.interruption = .{
                        .target_segment_id = self.copyString(payload.target_segment_id),
                        .at_ms = payload.at_ms,
                        .reason = interruptionReasonFromEvent(payload.reason),
                    };
                    self.activeSequenceMutable().metrics.interruption_count += 1;
                    self.activeSequenceMutable().state = .interrupted;
                    self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, payload.at_ms);
                }
            },
            .segment_completed => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                const segment = self.findSegmentMutable(payload.segment_id) orelse return;
                segment.end_ms = payload.end_ms;
                segment.duration_ms = payload.end_ms - segment.start_ms;
                segment.status = .completed;
                self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, payload.end_ms);

                switch (segment.kind) {
                    .user_speech => {
                        self.activeSequenceMutable().metrics.input_audio_ms = segment.duration_ms orelse 0;
                        if (self.activeSequence().metrics.transcription_latency_ms == null and segment.transcript != null) {
                            self.activeSequenceMutable().metrics.transcription_latency_ms = 420;
                        }
                        self.activeSequenceMutable().state = .transcribing;
                    },
                    .assistant_speech => {
                        self.activeSequenceMutable().metrics.assistant_audio_ms = segment.duration_ms orelse 0;
                    },
                    .tool_call => {
                        self.activeSequenceMutable().state = .thinking;
                    },
                    else => {},
                }
            },
            .sequence_completed => |payload| {
                if (!self.matchesActiveSequence(payload.sequence_id)) return;
                self.activeSequenceMutable().state = .completed;
                self.activeSequenceMutable().updated_at_ms = payload.completed_at_ms;
                self.activeSequenceMutable().metrics.total_response_latency_ms = payload.completed_at_ms;
            },
            .error_ => |payload| {
                if (payload.sequence_id) |sequence_id| {
                    if (!self.matchesActiveSequence(sequence_id)) return;
                }
                self.activeSequenceMutable().state = .error_;
                self.activeSequenceMutable().metrics.error_count += 1;
                self.activeSequenceMutable().updated_at_ms = @max(self.activeSequence().updated_at_ms, payload.at_ms);
            },
        }
    }

    fn tickCompletedDemo(self: *AudioDemoState, delta_ms: u64) void {
        const total_ms = self.activeSequence().totalDurationMs();
        if (total_ms == 0) return;

        const loop_ms = total_ms + 1_200;
        self.playback_position_ms = (self.playback_position_ms + delta_ms) % loop_ms;
    }

    fn tickReplay(self: *AudioDemoState, delta_ms: u64) void {
        const replay_limit = replay_end_ms + 1_200;
        self.playback_position_ms = @min(self.playback_position_ms + delta_ms, replay_limit);

        while (self.replay_event_index < replay_events.len and replay_events[self.replay_event_index].at_ms <= self.playback_position_ms) {
            self.applyEvent(replay_events[self.replay_event_index].event);
            self.replay_event_index += 1;
        }

        if (self.replay_event_index >= replay_events.len and self.playback_position_ms >= replay_limit) {
            self.is_playing = false;
        }
    }

    fn loadCompletedDemo(self: *AudioDemoState) void {
        self.mode = .completed_demo;
        self.permission_state = .granted;
        self.input_level_normalized = 0.0;
        self.peak_input_level = 0.0;
        self.playback_position_ms = 0;
        self.replay_event_index = 0;
        self.segment_count = completed_demo_segments.len;
        self.string_len = 0;
        self.selected_segment_id = null;
        self.is_playing = true;

        for (completed_demo_segments, 0..) |segment, index| {
            self.segment_storage[index] = segment;
        }

        self.sequences[0] = demoSequence(self.segment_storage[0..self.segment_count]);
    }

    fn activeSequenceMutable(self: *AudioDemoState) *AudioSequence {
        return &self.sequences[self.active_sequence_index];
    }

    fn matchesActiveSequence(self: *const AudioDemoState, sequence_id: []const u8) bool {
        return std.mem.eql(u8, self.activeSequence().id, sequence_id);
    }

    fn findSegmentMutable(self: *AudioDemoState, segment_id: []const u8) ?*AudioSegment {
        for (self.activeSequenceMutable().segments) |*segment| {
            if (std.mem.eql(u8, segment.id, segment_id)) return segment;
        }
        return null;
    }

    fn ensureSegment(
        self: *AudioDemoState,
        segment_id: []const u8,
        kind: AudioSegmentKind,
        start_ms: u64,
        status: AudioSegmentStatus,
    ) ?*AudioSegment {
        if (self.findSegmentMutable(segment_id)) |segment| {
            segment.kind = kind;
            segment.start_ms = start_ms;
            segment.status = status;
            return segment;
        }

        if (self.segment_count >= self.segment_storage.len) return null;

        const index = self.segment_count;
        self.segment_storage[index] = .{
            .id = self.copyString(segment_id),
            .kind = kind,
            .start_ms = start_ms,
            .status = status,
        };
        self.segment_count += 1;
        self.activeSequenceMutable().segments = self.segment_storage[0..self.segment_count];
        return &self.segment_storage[index];
    }

    fn copyString(self: *AudioDemoState, bytes: []const u8) []const u8 {
        if (bytes.len == 0) return "";
        if (self.string_len >= self.string_storage.len) return "";

        const available = self.string_storage.len - self.string_len;
        const copy_len = @min(bytes.len, available);
        if (copy_len == 0) return "";

        const start = self.string_len;
        @memcpy(self.string_storage[start .. start + copy_len], bytes[0..copy_len]);
        self.string_len += copy_len;
        return self.string_storage[start .. start + copy_len];
    }

    fn appendString(self: *AudioDemoState, current: ?[]const u8, suffix: []const u8) []const u8 {
        if (current == null) return self.copyString(suffix);
        if (suffix.len == 0) return current.?;
        if (self.string_len >= self.string_storage.len) return current.?;

        const prefix = current.?;
        const available = self.string_storage.len - self.string_len;
        const total_len = @min(prefix.len + suffix.len, available);
        if (total_len == 0) return current.?;

        const start = self.string_len;
        const prefix_len = @min(prefix.len, total_len);
        @memcpy(self.string_storage[start .. start + prefix_len], prefix[0..prefix_len]);
        if (total_len > prefix_len) {
            const suffix_len = total_len - prefix_len;
            @memcpy(
                self.string_storage[start + prefix_len .. start + prefix_len + suffix_len],
                suffix[0..suffix_len],
            );
        }
        self.string_len += total_len;
        return self.string_storage[start .. start + total_len];
    }

    fn updateStateForSegmentStart(self: *AudioDemoState, kind: AudioSegmentKind, start_ms: u64) void {
        switch (kind) {
            .user_speech => self.activeSequenceMutable().state = .listening,
            .tool_call => self.activeSequenceMutable().state = .thinking,
            .assistant_speech => {
                self.activeSequenceMutable().state = .speaking;
                if (self.activeSequence().metrics.first_audio_latency_ms == null) {
                    self.activeSequenceMutable().metrics.first_audio_latency_ms = start_ms;
                }
            },
            else => {},
        }
    }
};

fn segmentKindFromEvent(kind: audio_events.AudioEventSegmentKind) AudioSegmentKind {
    return switch (kind) {
        .user_speech => .user_speech,
        .assistant_speech => .assistant_speech,
        .silence => .silence,
        .sound_effect => .sound_effect,
        .background_audio => .background_audio,
        .tool_call => .tool_call,
        .interruption => .interruption,
    };
}

fn toolStatusFromEvent(status: audio_events.AudioToolCallStatus) ToolCallStatus {
    return switch (status) {
        .pending => .pending,
        .running => .running,
        .completed => .completed,
        .failed => .failed,
    };
}

fn interruptionReasonFromEvent(reason: audio_events.AudioInterruptionReason) InterruptionReason {
    return switch (reason) {
        .user_barge_in => .user_barge_in,
        .playback_cancelled => .playback_cancelled,
        .timeout => .timeout,
        .system_cancelled => .system_cancelled,
    };
}

test "completed demo sequence validates" {
    var state: AudioDemoState = undefined;
    state.init();
    try state.activeSequence().validate();
}

test "voice spec enforces allowed ranges" {
    try std.testing.expectError(ValidationError.InvalidVoiceSpeed, (VoiceSpec{
        .voice_id = "voice",
        .speed = 3.0,
    }).validate());
}

test "completed demo playback cursor advances and wraps" {
    var state: AudioDemoState = undefined;
    state.init();

    state.tick(0.5, false);
    try std.testing.expect(state.playback_position_ms > 0);

    state.playback_position_ms = state.activeSequence().totalDurationMs() + 1_100;
    state.tick(0.2, false);
    try std.testing.expect(state.playback_position_ms < 500);
}

test "live replay assembles a validated sequence from normalized events" {
    var state: AudioDemoState = undefined;
    state.init();
    state.startReplay();

    for (replay_events) |entry| {
        state.applyEvent(entry.event);
    }

    const sequence = state.activeSequence();
    try std.testing.expectEqual(AudioSequenceState.completed, sequence.state);
    try sequence.validate();

    const user_segment = sequence.findSegment("u1").?;
    try std.testing.expectEqualStrings("Show me the latest error spike.", user_segment.transcript.?);

    const assistant_segment = sequence.findSegment("a1").?;
    try std.testing.expectEqualStrings(
        "There was an error spike starting six minutes ago, concentrated in the API gateway.",
        assistant_segment.text.?,
    );

    try std.testing.expectEqual(@as(u32, 1), sequence.metrics.tool_call_count);
    try std.testing.expectEqual(@as(?u64, 2_800), sequence.metrics.first_audio_latency_ms);
}

test "live replay tick applies scripted events and settles the cursor" {
    var state: AudioDemoState = undefined;
    state.init();
    state.startReplay();

    var steps: usize = 0;
    while (steps < 24 and state.is_playing) : (steps += 1) {
        state.tick(0.5, false);
    }

    try std.testing.expectEqual(AudioDemoMode.live_replay, state.mode);
    try std.testing.expectEqual(AudioSequenceState.completed, state.activeSequence().state);
    try std.testing.expect(!state.is_playing);
    try std.testing.expect(state.replay_event_index == replay_events.len);
    try std.testing.expect(state.playback_position_ms >= replay_end_ms);
}

test "interruption events append a marker and increment metrics" {
    var state: AudioDemoState = undefined;
    state.init();
    state.startReplay();
    state.applyEvent(.{
        .segment_started = .{
            .sequence_id = live_sequence_id,
            .segment_id = "a1",
            .kind = .assistant_speech,
            .start_ms = 2_800,
        },
    });
    state.applyEvent(.{
        .transcript_delta = .{
            .sequence_id = live_sequence_id,
            .segment_id = "a1",
            .text = "Interruptible reply",
            .is_final = false,
        },
    });
    state.applyEvent(.{
        .interruption = .{
            .sequence_id = live_sequence_id,
            .target_segment_id = "a1",
            .at_ms = 3_100,
            .reason = .user_barge_in,
        },
    });

    try std.testing.expectEqual(@as(u32, 1), state.activeSequence().metrics.interruption_count);
    try std.testing.expectEqual(AudioSequenceState.interrupted, state.activeSequence().state);

    const interruption_segment = state.activeSequence().segments[state.activeSequence().segments.len - 1];
    try std.testing.expectEqual(AudioSegmentKind.interruption, interruption_segment.kind);
    try std.testing.expectEqualStrings("a1", interruption_segment.interruption.?.target_segment_id);
}
