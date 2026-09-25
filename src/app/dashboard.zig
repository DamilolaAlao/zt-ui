const std = @import("std");
const commands = @import("../gfx/commands.zig");
const ui_runtime = @import("../ui/ui.zig");
const state_mod = @import("state.zig");
const audio_panel = @import("audio_sequence_panel.zig");
const dino_panel = @import("dino_panel.zig");
const panels = @import("panels.zig");
const charts = @import("charts.zig");

pub fn draw(ui: *ui_runtime.UI, state: *state_mod.DashboardState, viewport: commands.Rect) !void {
    const frame = panels.resolve(viewport, state.sidebar_open);

    try drawSidebar(ui, state, frame.sidebar);
    try drawHeader(ui, state, frame.header);
    try drawMetrics(ui, state, frame.metrics);

    try dino_panel.draw(ui, &state.dino, frame.dino);

    try audio_panel.draw(ui, &state.audio, frame.audio);

    try ui.beginPanel("Pipeline Throughput", frame.chart);
    const chart_rect = ui.takeRemaining();
    try charts.draw(ui, state, chart_rect);
    ui.endPanel();

    try ui.beginPanel("Workflow Activity", frame.logs);
    try drawLogs(ui, state);
    ui.endPanel();
}

fn drawSidebar(ui: *ui_runtime.UI, state: *state_mod.DashboardState, rect: commands.Rect) !void {
    try ui.beginPanel("Field Systems", rect);
    try ui.text("Agentic Dino ported from devrel into Zig WASM");
    try ui.text("Space/Up flap · click aim · A autopilot · R retry");
    try ui.text("Local vision motor; command-buffered Canvas2D");

    if (try ui.button(if (state.dino.running and !state.dino.dead) "Dino running" else "Start dino")) {
        state.dino.flap(true);
    }
    if (try ui.button(if (state.dino.autopilot) "Autopilot: ON" else "Autopilot: OFF")) {
        state.dino.autopilot = !state.dino.autopilot;
    }
    if (try ui.button("Retry run")) {
        state.dino.resetRun();
    }
    if (try ui.button(if (state.sidebar_open) "Collapse sidebar" else "Expand sidebar")) {
        state.sidebar_open = !state.sidebar_open;
    }
    if (try ui.button(if (state.debug_overlay) "Hide debug overlay" else "Show debug overlay")) {
        state.debug_overlay = !state.debug_overlay;
    }
    if (try ui.button(if (state.layout_bounds) "Hide guide grid" else "Show guide grid")) {
        state.layout_bounds = !state.layout_bounds;
    }
    if (try ui.button(if (state.streaming_paused) "Resume feed" else "Pause feed")) {
        state.streaming_paused = !state.streaming_paused;
    }
    if (try ui.button("Reset benchmarks")) {
        state.resetBenchmarks();
    }

    ui.endPanel();
}

fn drawHeader(ui: *ui_runtime.UI, state: *state_mod.DashboardState, rect: commands.Rect) !void {
    try ui.beginPanel("zt-ui · Agentic Dino Console", rect);
    try ui.text("devrel Flappy/dino physics in Zig — plain data, immediate-mode draw, WASM host.");

    var score_buf: [80]u8 = undefined;
    const score_line = try std.fmt.bufPrint(
        &score_buf,
        "Dino HI {d} · score {d} · pipes {d} · {s}",
        .{
            @as(u32, @intFromFloat(state.dino.hi)),
            @as(u32, @intFromFloat(state.dino.score)),
            state.dino.pipes_cleared,
            if (state.dino.autopilot) "autopilot" else "manual",
        },
    );
    try ui.text(score_line);

    try ui.text(if (state.streaming_paused) "Feed state: paused" else "Feed state: live");
    ui.endPanel();
}

fn drawMetrics(ui: *ui_runtime.UI, state: *state_mod.DashboardState, rects: [3]commands.Rect) !void {
    var score_buf: [24]u8 = undefined;
    const score = try std.fmt.bufPrint(&score_buf, "{d}", .{@as(u32, @intFromFloat(state.dino.score))});

    var pipes_buf: [24]u8 = undefined;
    const pipes = try std.fmt.bufPrint(&pipes_buf, "{d}", .{state.dino.pipes_cleared});

    var speed_buf: [32]u8 = undefined;
    const speed = try std.fmt.bufPrint(&speed_buf, "{d:.1}x", .{state.dino.speed / 2.8});

    try ui.metricAt("Dino score", score, rects[0], ui.theme.colors.accent);
    try ui.metricAt("Pipes cleared", pipes, rects[1], ui.theme.colors.success);
    try ui.metricAt("Scroll speed", speed, rects[2], ui.theme.colors.warning);
}

fn drawLogs(ui: *ui_runtime.UI, state: *state_mod.DashboardState) !void {
    const row_height = ui.theme.text_line_height + 18;
    const content_height = @as(f32, @floatFromInt(state.logs.len)) * row_height + 8;
    const content = try ui.beginScrollArea("execution_log_scroll", 170, content_height, &state.log_scroll);

    var cursor_y = content.y + 8;
    for (state.logs, 0..) |entry, index| {
        const row = commands.Rect.init(content.x + 2, cursor_y, content.w - 4, row_height - 4);
        const fill = if ((index % 2) == 0) ui.theme.colors.log_row else ui.theme.colors.log_row_alt;
        try ui.renderer.pushRect(row, fill);
        try ui.renderer.pushStrokeRect(row, ui.theme.colors.panel_border, 1.0);

        var buf: [160]u8 = undefined;
        const line = try std.fmt.bufPrint(&buf, "{s} · {s} · {s}", .{ entry.agent, entry.stage, entry.detail });
        try ui.labelAt(line, row.insetXY(10, 10), ui.theme.colors.text);
        cursor_y += row_height;
    }

    try ui.endScrollArea();
}
