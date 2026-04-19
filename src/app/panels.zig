const commands = @import("../gfx/commands.zig");
const layout = @import("../ui/layout.zig");

pub const FrameLayout = struct {
    sidebar: commands.Rect,
    header: commands.Rect,
    metrics: [3]commands.Rect,
    chart: commands.Rect,
    logs: commands.Rect,
};

pub fn resolve(viewport: commands.Rect, sidebar_open: bool) FrameLayout {
    const margin: f32 = 20;
    const gap: f32 = 18;
    const sidebar_width: f32 = if (sidebar_open) 240 else 96;
    const sidebar = commands.Rect.init(margin, margin, sidebar_width, viewport.h - margin * 2);

    const content_x = sidebar.right() + gap;
    const content_w = if (viewport.w > content_x + margin) viewport.w - content_x - margin else 320;
    const header = commands.Rect.init(content_x, margin, content_w, 92);

    var metrics: [3]commands.Rect = undefined;
    layout.splitEqual(
        commands.Rect.init(content_x, header.bottom() + gap, content_w, 88),
        .horizontal,
        metrics.len,
        gap,
        metrics[0..],
    );

    const chart_top = metrics[0].bottom() + gap;
    const available = if (viewport.bottom() > chart_top + margin) viewport.bottom() - chart_top - margin else 300;
    const chart_height = available * 0.58;
    const chart = commands.Rect.init(content_x, chart_top, content_w, chart_height);
    const logs = commands.Rect.init(content_x, chart.bottom() + gap, content_w, available - chart_height - gap);

    return .{
        .sidebar = sidebar,
        .header = header,
        .metrics = metrics,
        .chart = chart,
        .logs = logs,
    };
}
