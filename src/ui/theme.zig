const color = @import("../gfx/color.zig");

pub const Palette = struct {
    canvas: u32,
    panel: u32,
    panel_border: u32,
    panel_title: u32,
    text: u32,
    muted: u32,
    accent: u32,
    accent_soft: u32,
    success: u32,
    warning: u32,
    danger: u32,
    chart_bg: u32,
    chart_line: u32,
    overlay_bg: u32,
    log_row: u32,
    log_row_alt: u32,
};

pub const Theme = struct {
    colors: Palette,
    padding: f32 = 16,
    gap: f32 = 12,
    panel_title_height: f32 = 38,
    button_height: f32 = 38,
    text_line_height: f32 = 18,
    metric_height: f32 = 88,

    pub fn operations() Theme {
        return .{
            .colors = .{
                .canvas = color.rgba(18, 22, 15, 255),
                .panel = color.rgba(31, 37, 26, 244),
                .panel_border = color.rgba(166, 147, 108, 118),
                .panel_title = color.rgba(242, 238, 228, 255),
                .text = color.rgba(242, 238, 228, 255),
                .muted = color.rgba(184, 177, 155, 255),
                .accent = color.rgba(151, 171, 103, 255),
                .accent_soft = color.rgba(73, 87, 45, 224),
                .success = color.rgba(111, 167, 108, 255),
                .warning = color.rgba(204, 165, 98, 255),
                .danger = color.rgba(189, 117, 94, 255),
                .chart_bg = color.rgba(23, 27, 19, 245),
                .chart_line = color.rgba(163, 193, 109, 255),
                .overlay_bg = color.rgba(14, 17, 12, 235),
                .log_row = color.rgba(39, 46, 31, 214),
                .log_row_alt = color.rgba(32, 38, 26, 214),
            },
        };
    }
};
