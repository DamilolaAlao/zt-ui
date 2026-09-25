const std = @import("std");
const audio_events = @import("audio_events.zig");

const Scratch = struct {
    buf: []u8,
    len: usize = 0,

    fn copy(self: *Scratch, bytes: []const u8) error{InvalidAudioEvent}![]const u8 {
        if (self.len + bytes.len > self.buf.len) return error.InvalidAudioEvent;
        const start = self.len;
        @memcpy(self.buf[start .. start + bytes.len], bytes);
        self.len += bytes.len;
        return self.buf[start..self.len];
    }
};

const Fields = struct {
    type_name: ?[]const u8 = null,
    sequence_id: ?[]const u8 = null,
    segment_id: ?[]const u8 = null,
    state: ?[]const u8 = null,
    kind: ?[]const u8 = null,
    text: ?[]const u8 = null,
    tool_name: ?[]const u8 = null,
    status: ?[]const u8 = null,
    target_segment_id: ?[]const u8 = null,
    reason: ?[]const u8 = null,
    code: ?[]const u8 = null,
    message: ?[]const u8 = null,
    audio_base64: ?[]const u8 = null,
    is_final: bool = false,
    start_ms: ?u64 = null,
    end_ms: ?u64 = null,
    at_ms: ?u64 = null,
    completed_at_ms: ?u64 = null,
    latency_ms: ?u64 = null,
    byte_len: ?u32 = null,
    level_normalized: ?f32 = null,
    peak_normalized: ?f32 = null,
};

pub fn parse(json: []const u8, scratch_buf: []u8) error{InvalidAudioEvent}!audio_events.AudioEvent {
    var scratch = Scratch{ .buf = scratch_buf };
    var fields = Fields{};
    try walk(json, &scratch, &fields);
    return try eventFromFields(fields);
}

fn walk(json: []const u8, scratch: *Scratch, fields: *Fields) error{InvalidAudioEvent}!void {
    var i = skipWs(json, 0);
    if (i >= json.len or json[i] != '{') return error.InvalidAudioEvent;
    i += 1;

    while (i < json.len) {
        i = skipWs(json, i);
        if (i < json.len and json[i] == '}') return;
        if (i >= json.len or json[i] != '"') return error.InvalidAudioEvent;

        var key_buf: [64]u8 = undefined;
        const key = try readString(json, &i, key_buf[0..]);
        i = skipWs(json, i);
        if (i >= json.len or json[i] != ':') return error.InvalidAudioEvent;
        i += 1;
        i = skipWs(json, i);
        try readField(json, &i, scratch, fields, key);

        i = skipWs(json, i);
        if (i < json.len and json[i] == ',') {
            i += 1;
            continue;
        }
        if (i < json.len and json[i] == '}') return;
        return error.InvalidAudioEvent;
    }
    return error.InvalidAudioEvent;
}

fn readField(
    json: []const u8,
    i: *usize,
    scratch: *Scratch,
    fields: *Fields,
    key: []const u8,
) error{InvalidAudioEvent}!void {
    if (std.mem.eql(u8, key, "type")) {
        fields.type_name = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "sequence_id")) {
        fields.sequence_id = try readOptionalString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "segment_id")) {
        fields.segment_id = try readOptionalString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "state")) {
        fields.state = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "kind")) {
        fields.kind = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "text")) {
        fields.text = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "tool_name")) {
        fields.tool_name = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "status")) {
        fields.status = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "target_segment_id")) {
        fields.target_segment_id = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "reason")) {
        fields.reason = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "code")) {
        fields.code = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "message")) {
        fields.message = try readOwnedString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "audio_base64")) {
        fields.audio_base64 = try readOptionalString(json, i, scratch);
    } else if (std.mem.eql(u8, key, "is_final")) {
        fields.is_final = try readBool(json, i);
    } else if (std.mem.eql(u8, key, "start_ms")) {
        fields.start_ms = try readU64(json, i);
    } else if (std.mem.eql(u8, key, "end_ms")) {
        fields.end_ms = try readU64(json, i);
    } else if (std.mem.eql(u8, key, "at_ms")) {
        fields.at_ms = try readU64(json, i);
    } else if (std.mem.eql(u8, key, "completed_at_ms")) {
        fields.completed_at_ms = try readU64(json, i);
    } else if (std.mem.eql(u8, key, "latency_ms")) {
        fields.latency_ms = try readOptionalU64(json, i);
    } else if (std.mem.eql(u8, key, "byte_len")) {
        const value = try readOptionalU64(json, i);
        fields.byte_len = if (value) |n| std.math.cast(u32, n) orelse return error.InvalidAudioEvent else null;
    } else if (std.mem.eql(u8, key, "level_normalized")) {
        fields.level_normalized = try readF32(json, i);
    } else if (std.mem.eql(u8, key, "peak_normalized")) {
        fields.peak_normalized = try readOptionalF32(json, i);
    } else {
        try skipValue(json, i);
    }
}

fn readString(json: []const u8, i: *usize, dest: []u8) error{InvalidAudioEvent}![]const u8 {
    if (i.* >= json.len or json[i.*] != '"') return error.InvalidAudioEvent;
    i.* += 1;
    var len: usize = 0;
    while (i.* < json.len) : (i.* += 1) {
        const ch = json[i.*];
        if (ch == '"') {
            i.* += 1;
            return dest[0..len];
        }
        if (ch == '\\') {
            i.* += 1;
            if (i.* >= json.len) return error.InvalidAudioEvent;
            const decoded = unescape(json[i.*]) orelse return error.InvalidAudioEvent;
            if (len >= dest.len) return error.InvalidAudioEvent;
            dest[len] = decoded;
            len += 1;
            continue;
        }
        if (len >= dest.len) return error.InvalidAudioEvent;
        dest[len] = ch;
        len += 1;
    }
    return error.InvalidAudioEvent;
}

fn readOwnedString(json: []const u8, i: *usize, scratch: *Scratch) error{InvalidAudioEvent}![]const u8 {
    var buf: [2048]u8 = undefined;
    const raw = try readString(json, i, buf[0..]);
    return scratch.copy(raw);
}

fn readOptionalString(json: []const u8, i: *usize, scratch: *Scratch) error{InvalidAudioEvent}!?[]const u8 {
    if (startsWith(json, i.*, "null")) {
        i.* += 4;
        return null;
    }
    return try readOwnedString(json, i, scratch);
}

fn readBool(json: []const u8, i: *usize) error{InvalidAudioEvent}!bool {
    if (startsWith(json, i.*, "true")) {
        i.* += 4;
        return true;
    }
    if (startsWith(json, i.*, "false")) {
        i.* += 5;
        return false;
    }
    return error.InvalidAudioEvent;
}

fn readU64(json: []const u8, i: *usize) error{InvalidAudioEvent}!u64 {
    const text = numberSlice(json, i) orelse return error.InvalidAudioEvent;
    if (std.fmt.parseInt(u64, text, 10)) |value| {
        return value;
    } else |_| {
        const as_float = std.fmt.parseFloat(f64, text) catch return error.InvalidAudioEvent;
        if (as_float < 0) return error.InvalidAudioEvent;
        return @intFromFloat(as_float);
    }
}

fn readOptionalU64(json: []const u8, i: *usize) error{InvalidAudioEvent}!?u64 {
    if (startsWith(json, i.*, "null")) {
        i.* += 4;
        return null;
    }
    return try readU64(json, i);
}

fn readF32(json: []const u8, i: *usize) error{InvalidAudioEvent}!f32 {
    const text = numberSlice(json, i) orelse return error.InvalidAudioEvent;
    const value = std.fmt.parseFloat(f32, text) catch return error.InvalidAudioEvent;
    return value;
}

fn readOptionalF32(json: []const u8, i: *usize) error{InvalidAudioEvent}!?f32 {
    if (startsWith(json, i.*, "null")) {
        i.* += 4;
        return null;
    }
    return try readF32(json, i);
}

fn numberSlice(json: []const u8, i: *usize) ?[]const u8 {
    const start = i.*;
    if (start >= json.len) return null;
    if (json[start] == '-') i.* += 1;
    const digits = i.*;
    while (i.* < json.len) : (i.* += 1) {
        const ch = json[i.*];
        const ok = (ch >= '0' and ch <= '9') or ch == '.' or ch == 'e' or ch == 'E' or ch == '+' or ch == '-';
        if (!ok) break;
    }
    if (i.* == digits) return null;
    return json[start..i.*];
}

fn skipValue(json: []const u8, i: *usize) error{InvalidAudioEvent}!void {
    if (i.* >= json.len) return error.InvalidAudioEvent;
    const ch = json[i.*];
    if (ch == '"') {
        i.* += 1;
        while (i.* < json.len) {
            if (json[i.*] == '\\') {
                i.* += 2;
                continue;
            }
            if (json[i.*] == '"') {
                i.* += 1;
                return;
            }
            i.* += 1;
        }
        return error.InvalidAudioEvent;
    }
    if (ch == '{') return skipContainer(json, i, '{', '}');
    if (ch == '[') return skipContainer(json, i, '[', ']');
    if (startsWith(json, i.*, "null")) {
        i.* += 4;
        return;
    }
    if (startsWith(json, i.*, "true")) {
        i.* += 4;
        return;
    }
    if (startsWith(json, i.*, "false")) {
        i.* += 5;
        return;
    }
    if (numberSlice(json, i) == null) return error.InvalidAudioEvent;
}

fn skipContainer(json: []const u8, i: *usize, open: u8, close: u8) error{InvalidAudioEvent}!void {
    var depth: usize = 0;
    var in_string = false;
    while (i.* < json.len) : (i.* += 1) {
        const ch = json[i.*];
        if (in_string) {
            if (ch == '\\') {
                i.* += 1;
                continue;
            }
            if (ch == '"') in_string = false;
            continue;
        }
        if (ch == '"') {
            in_string = true;
            continue;
        }
        if (ch == open) depth += 1;
        if (ch == close) {
            depth -= 1;
            if (depth == 0) {
                i.* += 1;
                return;
            }
        }
    }
    return error.InvalidAudioEvent;
}

fn unescape(ch: u8) ?u8 {
    return switch (ch) {
        '"', '\\', '/' => ch,
        'b' => 0x08,
        'f' => 0x0c,
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        else => null,
    };
}

fn skipWs(json: []const u8, start: usize) usize {
    var i = start;
    while (i < json.len and (json[i] == ' ' or json[i] == '\n' or json[i] == '\r' or json[i] == '\t')) : (i += 1) {}
    return i;
}

fn startsWith(json: []const u8, index: usize, needle: []const u8) bool {
    if (index + needle.len > json.len) return false;
    return std.mem.eql(u8, json[index .. index + needle.len], needle);
}

fn eventFromFields(self: Fields) error{InvalidAudioEvent}!audio_events.AudioEvent {
    const type_name = self.type_name orelse return error.InvalidAudioEvent;
    if (std.mem.eql(u8, type_name, "permission_changed")) {
        const state = std.meta.stringToEnum(audio_events.AudioPermissionState, self.state orelse return error.InvalidAudioEvent) orelse return error.InvalidAudioEvent;
        return .{ .permission_changed = .{ .sequence_id = self.sequence_id, .state = state } };
    }
    if (std.mem.eql(u8, type_name, "input_level")) {
        return .{ .input_level = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .level_normalized = self.level_normalized orelse return error.InvalidAudioEvent,
            .peak_normalized = self.peak_normalized,
            .at_ms = self.at_ms orelse return error.InvalidAudioEvent,
        } };
    }
    if (std.mem.eql(u8, type_name, "segment_started")) {
        const kind = std.meta.stringToEnum(audio_events.AudioEventSegmentKind, self.kind orelse return error.InvalidAudioEvent) orelse return error.InvalidAudioEvent;
        return .{ .segment_started = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .segment_id = self.segment_id orelse return error.InvalidAudioEvent,
            .kind = kind,
            .start_ms = self.start_ms orelse return error.InvalidAudioEvent,
        } };
    }
    if (std.mem.eql(u8, type_name, "transcript_delta")) {
        return .{ .transcript_delta = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .segment_id = self.segment_id orelse return error.InvalidAudioEvent,
            .text = self.text orelse return error.InvalidAudioEvent,
            .is_final = self.is_final,
        } };
    }
    if (std.mem.eql(u8, type_name, "audio_delta")) {
        return .{ .audio_delta = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .segment_id = self.segment_id orelse return error.InvalidAudioEvent,
            .audio_base64 = self.audio_base64,
            .byte_len = self.byte_len,
        } };
    }
    if (std.mem.eql(u8, type_name, "tool_call")) {
        const status = std.meta.stringToEnum(audio_events.AudioToolCallStatus, self.status orelse "pending") orelse return error.InvalidAudioEvent;
        return .{ .tool_call = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .segment_id = self.segment_id orelse return error.InvalidAudioEvent,
            .tool_name = self.tool_name orelse return error.InvalidAudioEvent,
            .status = status,
            .latency_ms = self.latency_ms,
        } };
    }
    if (std.mem.eql(u8, type_name, "interruption")) {
        const reason = std.meta.stringToEnum(audio_events.AudioInterruptionReason, self.reason orelse return error.InvalidAudioEvent) orelse return error.InvalidAudioEvent;
        return .{ .interruption = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .target_segment_id = self.target_segment_id orelse return error.InvalidAudioEvent,
            .at_ms = self.at_ms orelse return error.InvalidAudioEvent,
            .reason = reason,
        } };
    }
    if (std.mem.eql(u8, type_name, "segment_completed")) {
        return .{ .segment_completed = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .segment_id = self.segment_id orelse return error.InvalidAudioEvent,
            .end_ms = self.end_ms orelse return error.InvalidAudioEvent,
        } };
    }
    if (std.mem.eql(u8, type_name, "sequence_completed")) {
        return .{ .sequence_completed = .{
            .sequence_id = self.sequence_id orelse return error.InvalidAudioEvent,
            .completed_at_ms = self.completed_at_ms orelse return error.InvalidAudioEvent,
        } };
    }
    if (std.mem.eql(u8, type_name, "error_")) {
        return .{ .error_ = .{
            .sequence_id = self.sequence_id,
            .segment_id = self.segment_id,
            .code = self.code orelse return error.InvalidAudioEvent,
            .message = self.message orelse return error.InvalidAudioEvent,
            .at_ms = self.at_ms orelse return error.InvalidAudioEvent,
        } };
    }
    return error.InvalidAudioEvent;
}

test "bridge json keeps extra fields and null latency" {
    const json =
        \\{"type":"tool_call","sequence_id":"seq_live","segment_id":"tool1","tool_name":"metrics.query","status":"running","latency_ms":null,"_wall_ms":42}
    ;
    var scratch: [1024]u8 = undefined;
    const event = try parse(json, &scratch);
    switch (event) {
        .tool_call => |payload| {
            try std.testing.expectEqualStrings("seq_live", payload.sequence_id);
            try std.testing.expectEqualStrings("metrics.query", payload.tool_name);
            try std.testing.expectEqual(audio_events.AudioToolCallStatus.running, payload.status);
            try std.testing.expect(payload.latency_ms == null);
        },
        else => return error.UnexpectedEventTag,
    }
}
