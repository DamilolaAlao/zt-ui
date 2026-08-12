const commands = @import("../gfx/commands.zig");
const layout = @import("../ui/layout.zig");

pub const FrameLayout = struct {
    sidebar: commands.Rect,
    header: commands.Rect,
    metrics: [3]commands.Rect,
    dino: commands.Rect,
    audio: commands.Rect,
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
    const header = commands.Rect.init(content_x, margin, content_w, 78);

    var metrics: [3]commands.Rect = undefined;
    layout.splitEqual(
        commands.Rect.init(content_x, header.bottom() + gap, content_w, 72),
        .horizontal,
        metrics.len,
        gap,
        metrics[0..],
    );

    const main_top = metrics[0].bottom() + gap;
    const available = if (viewport.bottom() > main_top + margin) viewport.bottom() - main_top - margin else 300;
    const dino_height = available * 0.58;
    const dino = commands.Rect.init(content_x, main_top, content_w, dino_height);

    const bottom_top = dino.bottom() + gap;
    const bottom_h = if (available > dino_height + gap) available - dino_height - gap else 120;
    const audio_width = content_w * 0.55;
    const audio = commands.Rect.init(content_x, bottom_top, audio_width - gap * 0.5, bottom_h * 0.55);
    const chart = commands.Rect.init(audio.right() + gap, bottom_top, content_w - audio.w - gap, bottom_h * 0.55);
    const logs = commands.Rect.init(content_x, audio.bottom() + gap, content_w, bottom_h - audio.h - gap);

    return .{
        .sidebar = sidebar,
        .header = header,
        .metrics = metrics,
        .dino = dino,
        .audio = audio,
        .chart = chart,
        .logs = logs,
    };
}
