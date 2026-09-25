const std = @import("std");
const color = @import("../gfx/color.zig");
const commands = @import("../gfx/commands.zig");
const ui_runtime = @import("../ui/ui.zig");
const audio_state = @import("audio_sequence_state.zig");

pub fn draw(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    try ui.beginPanel("LLM Audio Sequence", rect);
    const metrics_rect = ui.takeBlock(76);
    const timeline_rect = ui.takeBlock(132);
    const bottom_rect = ui.takeRemaining();

    try drawSummary(ui, state, metrics_rect);
    try drawTimeline(ui, state, timeline_rect);
    try drawTranscriptAndInspector(ui, state, bottom_rect);
    ui.endPanel();
}

fn drawSummary(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    const sequence = state.activeSequence();
    var cards: [4]commands.Rect = undefined;
    splitHorizontal(rect, 10, cards[0..]);

    var cursor_buf: [48]u8 = undefined;
    const cursor = try std.fmt.bufPrint(&cursor_buf, "{d:.1}s", .{@as(f32, @floatFromInt(state.playback_position_ms)) / 1000.0});

    var first_audio_buf: [48]u8 = undefined;
    const first_audio = formatDurationMs(&first_audio_buf, sequence.metrics.first_audio_latency_ms);

    var total_latency_buf: [48]u8 = undefined;
    const total_latency = formatDurationMs(&total_latency_buf, sequence.metrics.total_response_latency_ms);

    var tool_calls_buf: [48]u8 = undefined;
    const tool_calls = try std.fmt.bufPrint(&tool_calls_buf, "{d} call{s}", .{
        sequence.metrics.tool_call_count,
        if (sequence.metrics.tool_call_count == 1) "" else "s",
    });

    try drawMetricCard(ui, cards[0], "Sequence state", @tagName(sequence.state), ui.theme.colors.accent);
    try drawMetricCard(ui, cards[1], "Playback cursor", cursor, ui.theme.colors.success);
    try drawMetricCard(ui, cards[2], "First audio", first_audio, ui.theme.colors.warning);
    try drawMetricCard(ui, cards[3], "Tool calls", tool_calls, ui.theme.colors.danger);

    const footer = commands.Rect.init(rect.x + 6, rect.bottom() - 16, rect.w - 12, 12);
    var footer_buf: [96]u8 = undefined;
    const footer_text = try std.fmt.bufPrint(
        &footer_buf,
        "{s}  •  latency {s}  •  mic {s}",
        .{ state.modeLabel(), total_latency, state.permissionLabel() },
    );
    try ui.labelAt(footer_text, footer, ui.theme.colors.muted);
}

fn drawTimeline(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    const sequence = state.activeSequence();
    const total_ms = @max(sequence.totalDurationMs(), @as(u64, 1));
    const shell = rect.insetXY(2, 2);
    const inner = shell.insetXY(12, 12);
    const label_w: f32 = 82;
    const lane_gap: f32 = 8;
    const lane_height = if (inner.h > lane_gap * 2) (inner.h - lane_gap * 2) / 3.0 else 0;
    const plot = commands.Rect.init(inner.x + label_w, inner.y, inner.w - label_w, inner.h);

    try ui.renderer.pushRect(shell, ui.theme.colors.chart_bg);
    try ui.renderer.pushStrokeRect(shell, ui.theme.colors.panel_border, 1.0);

    const lane_names = [_][]const u8{ "User speech", "Tool call", "Assistant" };
    for (lane_names, 0..) |lane_name, lane_index| {
        const y = plot.y + @as(f32, @floatFromInt(lane_index)) * (lane_height + lane_gap);
        const lane_rect = commands.Rect.init(plot.x, y, plot.w, lane_height);
        try ui.renderer.pushRect(lane_rect, color.withAlpha(ui.theme.colors.panel, 164));
        try ui.renderer.pushStrokeRect(lane_rect, color.withAlpha(ui.theme.colors.panel_border, 72), 1.0);
        try ui.renderer.pushText(
            commands.Vec2.init(inner.x, lane_rect.y + 16),
            lane_name,
            ui.theme.colors.muted,
            13,
        );
    }

    try ui.renderer.pushClip(plot);
    defer ui.renderer.popClip() catch unreachable;

    ui.pushId("audio_timeline");
    defer ui.popId();

    for (sequence.segments) |segment| {
        const lane_index = laneFor(segment.kind) orelse continue;
        const y = plot.y + @as(f32, @floatFromInt(lane_index)) * (lane_height + lane_gap);
        const start_ms = @min(segment.start_ms, total_ms);
        const x = plot.x + (@as(f32, @floatFromInt(start_ms)) / @as(f32, @floatFromInt(total_ms))) * plot.w;
        const resolved_end = segment.end_ms orelse total_ms;
        const span_ms = if (resolved_end > segment.start_ms) resolved_end - segment.start_ms else 0;
        const segment_w = @max(
            10.0,
            (@as(f32, @floatFromInt(span_ms)) / @as(f32, @floatFromInt(total_ms))) * plot.w,
        );
        const segment_rect = commands.Rect.init(x, y + 7, segment_w, @max(0.0, lane_height - 14));
        const interaction = ui.interact(ui.id(segment.id), segment_rect);
        const selected = isSelected(state, segment.id);
        const fill = if (selected)
            segmentColor(ui, segment.kind)
        else if (interaction.hovered)
            color.withAlpha(segmentColor(ui, segment.kind), 196)
        else
            color.withAlpha(segmentColor(ui, segment.kind), 150);
        const stroke = if (selected or interaction.hovered) ui.theme.colors.text else ui.theme.colors.panel_border;

        if (interaction.clicked) {
            if (selected) {
                state.clearSelection();
            } else {
                state.selectSegment(segment.id);
            }
        }

        try ui.renderer.pushRect(segment_rect, fill);
        try ui.renderer.pushStrokeRect(segment_rect, stroke, 1.0);
        try ui.renderer.pushText(
            commands.Vec2.init(segment_rect.x + 8, segment_rect.y + 14),
            segment.id,
            ui.theme.colors.text,
            12,
        );
    }

    const cursor_ratio = std.math.clamp(
        @as(f32, @floatFromInt(@min(state.playback_position_ms, total_ms))) / @as(f32, @floatFromInt(total_ms)),
        0.0,
        1.0,
    );
    const cursor_x = plot.x + cursor_ratio * plot.w;
    const cursor_points = [_]commands.Vec2{
        commands.Vec2.init(cursor_x, plot.y),
        commands.Vec2.init(cursor_x, plot.bottom()),
    };
    try ui.renderer.pushPolyline(cursor_points[0..], ui.theme.colors.accent, 2.0);

    var axis_buf: [64]u8 = undefined;
    const axis_label = try std.fmt.bufPrint(&axis_buf, "0.0s                         {d:.1}s", .{@as(f32, @floatFromInt(total_ms)) / 1000.0});
    try ui.renderer.pushText(
        commands.Vec2.init(plot.x, plot.bottom() - 4),
        axis_label,
        ui.theme.colors.muted,
        12,
    );
}

fn drawTranscriptAndInspector(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    const transcript_w = rect.w * 0.58;
    const transcript_rect = commands.Rect.init(rect.x, rect.y, @max(0, transcript_w - 6), rect.h);
    const inspector_x = transcript_rect.right() + 12;
    const inspector_rect = commands.Rect.init(
        inspector_x,
        rect.y,
        if (rect.right() > inspector_x) rect.right() - inspector_x else 0,
        rect.h,
    );

    try drawTranscript(ui, state, transcript_rect);
    try drawInspector(ui, state, inspector_rect);
}

fn drawTranscript(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    const sequence = state.activeSequence();
    const shell = rect.insetXY(2, 2);
    const inner = shell.insetXY(12, 12);
    const row_gap: f32 = 10;
    const row_height: f32 = 56;

    try ui.renderer.pushRect(shell, color.withAlpha(ui.theme.colors.panel, 224));
    try ui.renderer.pushStrokeRect(shell, ui.theme.colors.panel_border, 1.0);
    try ui.renderer.pushText(commands.Vec2.init(inner.x, inner.y + 2), "Transcript", ui.theme.colors.panel_title, 14);

    try ui.renderer.pushClip(inner);
    defer ui.renderer.popClip() catch unreachable;

    ui.pushId("audio_transcript");
    defer ui.popId();

    if (sequence.segments.len == 0) {
        try ui.renderer.pushText(
            commands.Vec2.init(inner.x, inner.y + 28),
            "Waiting for normalized audio events.",
            ui.theme.colors.muted,
            14,
        );
        return;
    }

    var cursor_y = inner.y + 22;
    for (sequence.segments) |segment| {
        const row = commands.Rect.init(inner.x, cursor_y, inner.w, row_height);
        const selected = isSelected(state, segment.id);
        const fill = if (selected)
            color.withAlpha(segmentColor(ui, segment.kind), 208)
        else
            color.withAlpha(segmentColor(ui, segment.kind), 96);

        const accent_rect = switch (segment.kind) {
            .assistant_speech => commands.Rect.init(row.right() - 4, row.y, 4, row.h),
            else => commands.Rect.init(row.x, row.y, 4, row.h),
        };

        const interaction = ui.interact(ui.id(segment.id), row);
        if (interaction.clicked) {
            if (selected) {
                state.clearSelection();
            } else {
                state.selectSegment(segment.id);
            }
        }

        try ui.renderer.pushRect(row, fill);
        try ui.renderer.pushRect(accent_rect, segmentColor(ui, segment.kind));
        try ui.renderer.pushStrokeRect(
            row,
            if (selected or interaction.hovered) ui.theme.colors.text else color.withAlpha(ui.theme.colors.panel_border, 96),
            1.0,
        );
        try ui.renderer.pushText(
            commands.Vec2.init(row.x + 12, row.y + 14),
            @tagName(segment.kind),
            ui.theme.colors.muted,
            12,
        );
        try ui.renderer.pushText(
            commands.Vec2.init(row.x + 12, row.y + 32),
            segment.displayText(),
            ui.theme.colors.text,
            14,
        );

        cursor_y += row_height + row_gap;
    }
}

fn drawInspector(ui: *ui_runtime.UI, state: *audio_state.AudioDemoState, rect: commands.Rect) !void {
    const sequence = state.activeSequence();
    const segment = state.inspectorSegment();
    const shell = rect.insetXY(2, 2);
    const inner = shell.insetXY(12, 12);

    try ui.renderer.pushRect(shell, color.withAlpha(ui.theme.colors.panel, 224));
    try ui.renderer.pushStrokeRect(shell, ui.theme.colors.panel_border, 1.0);
    try ui.renderer.pushText(commands.Vec2.init(inner.x, inner.y + 2), "Inspector", ui.theme.colors.panel_title, 14);

    ui.pushId("audio_inspector");
    defer ui.popId();

    const button_row = commands.Rect.init(inner.x, inner.y + 22, inner.w, 30);
    var buttons: [2]commands.Rect = undefined;
    splitHorizontal(button_row, 8, buttons[0..]);

    if (try ui.buttonAt(if (state.is_playing) "Pause cursor" else "Resume cursor", buttons[0])) {
        state.togglePlayback();
    }
    if (try ui.buttonAt(if (state.selected_segment_id != null) "Clear selection" else "Follow cursor", buttons[1])) {
        state.clearSelection();
    }

    const debug_button = commands.Rect.init(inner.x, button_row.bottom() + 8, inner.w, 30);
    if (try ui.buttonAt(if (state.show_debug_json) "Hide debug fields" else "Show debug fields", debug_button)) {
        state.show_debug_json = !state.show_debug_json;
    }

    const replay_button = commands.Rect.init(inner.x, debug_button.bottom() + 8, inner.w, 30);
    if (try ui.buttonAt(
        if (state.mode == .completed_demo) "Replay streaming events" else "Show completed demo",
        replay_button,
    )) {
        state.toggleReplayMode();
    }

    const text_origin_y = replay_button.bottom() + 14;
    try ui.renderer.pushClip(commands.Rect.init(inner.x, text_origin_y, inner.w, inner.bottom() - text_origin_y));
    defer ui.renderer.popClip() catch unreachable;

    var line_y = text_origin_y;
    try pushInspectorLine(ui, inner.x, &line_y, "Sequence", sequence.id);
    try pushInspectorLine(ui, inner.x, &line_y, "Mode", state.modeLabel());
    try pushInspectorLine(ui, inner.x, &line_y, "Language", sequence.language);
    try pushInspectorLine(ui, inner.x, &line_y, "State", @tagName(sequence.state));

    var level_buf: [48]u8 = undefined;
    const input_level = try std.fmt.bufPrint(&level_buf, "{d:.2}", .{state.input_level_normalized});
    try pushInspectorLine(ui, inner.x, &line_y, "Input level", input_level);

    if (segment) |active_segment| {
        var range_buf: [64]u8 = undefined;
        const range = try std.fmt.bufPrint(
            &range_buf,
            "{d} ms → {d} ms",
            .{ active_segment.start_ms, active_segment.end_ms orelse active_segment.start_ms },
        );

        try pushInspectorLine(ui, inner.x, &line_y, "Segment id", active_segment.id);
        try pushInspectorLine(ui, inner.x, &line_y, "Kind", @tagName(active_segment.kind));
        try pushInspectorLine(ui, inner.x, &line_y, "Status", @tagName(active_segment.status));
        try pushInspectorLine(ui, inner.x, &line_y, "Range", range);

        if (active_segment.confidence) |confidence| {
            var confidence_buf: [48]u8 = undefined;
            const confidence_text = try std.fmt.bufPrint(&confidence_buf, "{d:.2}", .{confidence});
            try pushInspectorLine(ui, inner.x, &line_y, "Confidence", confidence_text);
        }
        if (active_segment.voice) |voice| {
            try pushInspectorLine(ui, inner.x, &line_y, "Voice", voice.voice_id);

            var voice_buf: [96]u8 = undefined;
            const voice_text = try std.fmt.bufPrint(
                &voice_buf,
                "{s} / {s}",
                .{ @tagName(voice.style), @tagName(voice.emotion) },
            );
            try pushInspectorLine(ui, inner.x, &line_y, "Style", voice_text);
        }
        if (active_segment.tool_call) |tool_call| {
            try pushInspectorLine(ui, inner.x, &line_y, "Tool", tool_call.tool_name);

            var latency_buf: [48]u8 = undefined;
            const latency = formatDurationMs(&latency_buf, tool_call.latency_ms);
            try pushInspectorLine(ui, inner.x, &line_y, "Tool latency", latency);
        }
        if (state.show_debug_json) {
            line_y += 6;
            try pushInspectorLine(ui, inner.x, &line_y, "\"segment\"", active_segment.id);
            try pushInspectorLine(ui, inner.x, &line_y, "\"kind\"", @tagName(active_segment.kind));
            try pushInspectorLine(ui, inner.x, &line_y, "\"text\"", active_segment.displayText());
        }
    } else {
        try pushInspectorLine(ui, inner.x, &line_y, "Segment", "No active segment at the current cursor");
    }
}

fn drawMetricCard(
    ui: *ui_runtime.UI,
    rect: commands.Rect,
    label_text: []const u8,
    value_text: []const u8,
    accent: u32,
) !void {
    const shell = rect.insetXY(1, 1);
    try ui.renderer.pushRect(shell, color.withAlpha(ui.theme.colors.panel, 230));
    try ui.renderer.pushStrokeRect(shell, accent, 1.0);
    try ui.renderer.pushText(commands.Vec2.init(shell.x + 12, shell.y + 14), label_text, ui.theme.colors.muted, 12);
    try ui.renderer.pushText(commands.Vec2.init(shell.x + 12, shell.y + 38), value_text, ui.theme.colors.text, 18);
}

fn pushInspectorLine(ui: *ui_runtime.UI, x: f32, line_y: *f32, label_text: []const u8, value_text: []const u8) !void {
    var line_buf: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&line_buf, "{s}: {s}", .{ label_text, value_text });
    try ui.renderer.pushText(commands.Vec2.init(x, line_y.*), line, ui.theme.colors.text, 13);
    line_y.* += 18;
}

fn formatDurationMs(buffer: []u8, value_ms: ?u64) []const u8 {
    const value = value_ms orelse return "n/a";
    return std.fmt.bufPrint(buffer, "{d} ms", .{value}) catch "n/a";
}

fn splitHorizontal(rect: commands.Rect, gap: f32, out: []commands.Rect) void {
    if (out.len == 0) return;

    const total_gap = gap * @as(f32, @floatFromInt(out.len - 1));
    const base_w = if (rect.w > total_gap)
        (rect.w - total_gap) / @as(f32, @floatFromInt(out.len))
    else
        0;

    var cursor_x = rect.x;
    for (out, 0..) |*slot, index| {
        const width = if (index + 1 == out.len) rect.right() - cursor_x else base_w;
        slot.* = commands.Rect.init(cursor_x, rect.y, width, rect.h);
        cursor_x += base_w + gap;
    }
}

fn segmentColor(ui: *ui_runtime.UI, kind: audio_state.AudioSegmentKind) u32 {
    return switch (kind) {
        .user_speech => ui.theme.colors.accent,
        .assistant_speech => ui.theme.colors.success,
        .tool_call => ui.theme.colors.warning,
        .interruption => ui.theme.colors.danger,
        .silence => color.withAlpha(ui.theme.colors.muted, 160),
        .sound_effect => ui.theme.colors.warning,
        .background_audio => color.withAlpha(ui.theme.colors.panel_border, 180),
    };
}

fn laneFor(kind: audio_state.AudioSegmentKind) ?usize {
    return switch (kind) {
        .user_speech => 0,
        .tool_call => 1,
        .assistant_speech => 2,
        else => null,
    };
}

fn isSelected(state: *const audio_state.AudioDemoState, segment_id: []const u8) bool {
    const selected = state.selected_segment_id orelse return false;
    return std.mem.eql(u8, selected, segment_id);
}
