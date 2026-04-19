const commands = @import("../gfx/commands.zig");
const color = @import("../gfx/color.zig");
const Renderer = @import("../gfx/renderer.zig").Renderer;
const Theme = @import("theme.zig").Theme;

pub const ButtonStyle = struct {
    hovered: bool = false,
    held: bool = false,
};

pub fn panelFrame(renderer: *Renderer, theme: *const Theme, title: []const u8, rect: commands.Rect) !commands.Rect {
    try renderer.pushRect(rect, theme.colors.panel);
    try renderer.pushStrokeRect(rect, theme.colors.panel_border, 1.0);

    const title_rect = rect.cutTop(theme.panel_title_height);
    try renderer.pushText(
        commands.Vec2.init(title_rect.x + theme.padding, title_rect.y + 12),
        title,
        theme.colors.panel_title,
        15,
    );

    return rect.dropTop(theme.panel_title_height).insetXY(theme.padding, theme.padding);
}

pub fn label(renderer: *Renderer, theme: *const Theme, text: []const u8, rect: commands.Rect, tint: u32) !void {
    _ = theme;
    try renderer.pushText(commands.Vec2.init(rect.x, rect.y), text, tint, 14);
}

pub fn button(renderer: *Renderer, theme: *const Theme, label_text: []const u8, rect: commands.Rect, style: ButtonStyle) !void {
    const fill = if (style.held)
        theme.colors.accent_soft
    else if (style.hovered)
        color.withAlpha(theme.colors.accent, 44)
    else
        color.withAlpha(theme.colors.panel_border, 24);

    const stroke = if (style.hovered) theme.colors.accent else theme.colors.panel_border;
    try renderer.pushRect(rect, fill);
    try renderer.pushStrokeRect(rect, stroke, 1.0);
    try renderer.pushText(
        commands.Vec2.init(rect.x + 12, rect.y + 12),
        label_text,
        theme.colors.text,
        14,
    );
}

pub fn metric(
    renderer: *Renderer,
    theme: *const Theme,
    label_text: []const u8,
    value_text: []const u8,
    rect: commands.Rect,
    accent: u32,
) !void {
    try renderer.pushRect(rect, theme.colors.panel);
    try renderer.pushStrokeRect(rect, accent, 1.0);
    try renderer.pushText(commands.Vec2.init(rect.x + 14, rect.y + 14), label_text, theme.colors.muted, 13);
    try renderer.pushText(commands.Vec2.init(rect.x + 14, rect.y + 40), value_text, theme.colors.text, 22);
}
