const std = @import("std");
const commands = @import("../gfx/commands.zig");
const Renderer = @import("../gfx/renderer.zig").Renderer;
const Theme = @import("../ui/theme.zig").Theme;
const profiler = @import("profiler.zig");

pub const OverlayState = struct {
    visible: bool = true,
    show_layout_bounds: bool = false,
};

pub fn draw(
    renderer: *Renderer,
    theme: *const Theme,
    state: *const OverlayState,
    stats: *const profiler.Snapshot,
    viewport: commands.Rect,
) !void {
    if (!state.visible) return;

    const panel = commands.Rect.init(viewport.right() - 232, 18, 214, 108);
    try renderer.pushRect(panel, theme.colors.overlay_bg);
    try renderer.pushStrokeRect(panel, theme.colors.panel_border, 1.0);

    var fps_buf: [48]u8 = undefined;
    const fps_line = try std.fmt.bufPrint(&fps_buf, "fps {d:.1} | {d:.2} ms", .{ stats.fps, stats.frame_ms });

    var cmd_buf: [48]u8 = undefined;
    const cmd_line = try std.fmt.bufPrint(&cmd_buf, "cmds {d} | text {d}", .{ stats.command_count, stats.text_bytes });

    var point_buf: [48]u8 = undefined;
    const point_line = try std.fmt.bufPrint(&point_buf, "points {d}", .{stats.point_count});

    var hover_buf: [64]u8 = undefined;
    const hover_line = try std.fmt.bufPrint(&hover_buf, "hot {x} | active {x}", .{ stats.hovered_id, stats.active_id });

    const layout_line = if (state.show_layout_bounds) "guide grid on" else "guide grid off";

    try renderer.pushText(commands.Vec2.init(panel.x + 12, panel.y + 14), fps_line, theme.colors.text, 12);
    try renderer.pushText(commands.Vec2.init(panel.x + 12, panel.y + 34), cmd_line, theme.colors.text, 12);
    try renderer.pushText(commands.Vec2.init(panel.x + 12, panel.y + 54), point_line, theme.colors.text, 12);
    try renderer.pushText(commands.Vec2.init(panel.x + 12, panel.y + 74), hover_line, theme.colors.muted, 12);
    try renderer.pushText(commands.Vec2.init(panel.x + 12, panel.y + 92), layout_line, theme.colors.accent, 12);
}
