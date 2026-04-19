const std = @import("std");
const commands = @import("../gfx/commands.zig");
const ui_runtime = @import("../ui/ui.zig");
const state_mod = @import("state.zig");

pub fn draw(ui: *ui_runtime.UI, state: *state_mod.DashboardState, rect: commands.Rect) !void {
    const plot = rect.insetXY(12, 12);
    const widget_id = ui.id("throughput_plot");
    const interaction = ui.interact(widget_id, plot);

    if (interaction.hovered and ui.input.wheel_delta.y != 0) {
        const next_zoom = state.chart_zoom + (-ui.input.wheel_delta.y * 0.08);
        state.chart_zoom = std.math.clamp(next_zoom, 1.0, 6.0);
    }

    if (interaction.held and plot.w > 0) {
        const delta = ui.input.mouseMoved().x / plot.w;
        state.chart_pan = std.math.clamp(state.chart_pan - delta, 0.0, 1.0);
    }

    try ui.renderer.pushRect(plot, ui.theme.colors.chart_bg);
    try ui.renderer.pushStrokeRect(plot, ui.theme.colors.panel_border, 1.0);

    const visible = @max(18, @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(state.samples.len)) / state.chart_zoom))));
    const max_start = state.samples.len - visible;
    const start = @min(max_start, @as(usize, @intFromFloat(state.chart_pan * @as(f32, @floatFromInt(max_start)))));
    const end = start + visible;

    var min_value = state.samples[start];
    var max_value = state.samples[start];
    for (state.samples[start..end]) |sample| {
        min_value = @min(min_value, sample);
        max_value = @max(max_value, sample);
    }

    const span = if (max_value - min_value < 0.001) 1.0 else max_value - min_value;
    var points: [state_mod.sample_count]commands.Vec2 = undefined;
    var point_count: usize = 0;
    for (state.samples[start..end], 0..) |sample, index| {
        const denom = @as(f32, @floatFromInt(@max(1, visible - 1)));
        const t = @as(f32, @floatFromInt(index)) / denom;
        const normalized = (sample - min_value) / span;
        points[point_count] = commands.Vec2.init(
            plot.x + t * plot.w,
            plot.bottom() - normalized * plot.h,
        );
        point_count += 1;
    }
    try ui.renderer.pushPolyline(points[0..point_count], ui.theme.colors.chart_line, 2.0);

    if (interaction.hovered and plot.w > 0) {
        const ratio = std.math.clamp((ui.input.mousePosition().x - plot.x) / plot.w, 0.0, 1.0);
        const hovered_index = start + @as(usize, @intFromFloat(ratio * @as(f32, @floatFromInt(visible - 1))));
        const sample = state.samples[hovered_index];

        const tooltip = commands.Rect.init(plot.x + 12, plot.y + 12, 152, 44);
        try ui.renderer.pushRect(tooltip, ui.theme.colors.overlay_bg);
        try ui.renderer.pushStrokeRect(tooltip, ui.theme.colors.panel_border, 1.0);

        var label_buf: [64]u8 = undefined;
        const label = try std.fmt.bufPrint(&label_buf, "throughput {d:.0} / hr", .{sample});
        try ui.renderer.pushText(commands.Vec2.init(tooltip.x + 10, tooltip.y + 14), label, ui.theme.colors.text, 13);
    }
}
