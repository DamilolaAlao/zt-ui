const std = @import("std");
const commands = @import("../gfx/commands.zig");
const ui_runtime = @import("../ui/ui.zig");
const state_mod = @import("state.zig");
const panels = @import("panels.zig");
const charts = @import("charts.zig");

pub fn draw(ui: *ui_runtime.UI, state: *state_mod.DashboardState, viewport: commands.Rect) !void {
    const frame = panels.resolve(viewport, state.sidebar_open);

    try drawSidebar(ui, state, frame.sidebar);
    try drawHeader(ui, state, frame.header);
    try drawMetrics(ui, state, frame.metrics);

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
    try ui.text("Workflow benchmarks and throughput panels");
    try ui.text("Operational queues, charts, and live scroll regions");
    try ui.text("Test-first seams and explicit runtime boundaries");

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
    try ui.beginPanel("Workflow Benchmark Console", rect);
    try ui.text("Benchmarks, pipeline throughput, and workflow queues in one immediate-mode frame.");
    try ui.text("Canvas-backed JS today, explicit command buffers ready for a future WebGPU backend.");

    var benchmarks_buf: [64]u8 = undefined;
    const benchmarks = try std.fmt.bufPrint(&benchmarks_buf, "Benchmarks today: {d}", .{state.benchmarks_today});
    try ui.text(benchmarks);

    try ui.text(if (state.streaming_paused) "Feed state: paused" else "Feed state: live");
    ui.endPanel();
}

fn drawMetrics(ui: *ui_runtime.UI, state: *state_mod.DashboardState, rects: [3]commands.Rect) !void {
    var workflows_buf: [24]u8 = undefined;
    const workflows = try std.fmt.bufPrint(&workflows_buf, "{d}", .{state.active_workflows});

    var throughput_buf: [32]u8 = undefined;
    const throughput = try std.fmt.bufPrint(&throughput_buf, "{d:.0} / hr", .{state.pipeline_throughput_per_hour});

    var latency_buf: [32]u8 = undefined;
    const latency = try std.fmt.bufPrint(&latency_buf, "{d:.1} ms", .{state.benchmark_p95_ms});

    try ui.metricAt("Active workflows", workflows, rects[0], ui.theme.colors.accent);
    try ui.metricAt("Pipeline throughput", throughput, rects[1], ui.theme.colors.success);
    try ui.metricAt("Benchmark p95", latency, rects[2], ui.theme.colors.warning);
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
