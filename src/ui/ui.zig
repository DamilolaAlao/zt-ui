const std = @import("std");
const commands = @import("../gfx/commands.zig");
const Renderer = @import("../gfx/renderer.zig").Renderer;
const input_mod = @import("../platform/input.zig");
const id_mod = @import("id.zig");
const layout_mod = @import("layout.zig");
const theme_mod = @import("theme.zig");
const widgets = @import("widgets.zig");
const clip = @import("clip.zig");

pub const Interaction = struct {
    hovered: bool,
    pressed: bool,
    held: bool,
    released: bool,
    clicked: bool,
};

pub const UI = struct {
    renderer: *Renderer,
    input: *input_mod.InputState,
    theme: theme_mod.Theme = theme_mod.Theme.operations(),
    viewport: commands.Rect = commands.Rect.init(0, 0, 1280, 720),
    hot_id: id_mod.WidgetId = 0,
    active_id: id_mod.WidgetId = 0,
    focused_id: id_mod.WidgetId = 0,
    show_layout_bounds: bool = false,
    layout_stack: [16]layout_mod.Stack = undefined,
    layout_len: usize = 0,
    id_stack: [16]id_mod.WidgetId = [_]id_mod.WidgetId{0} ** 16,
    id_len: usize = 1,
    clip_depth: usize = 0,

    pub fn init(renderer: *Renderer, input: *input_mod.InputState) UI {
        var ui = UI{
            .renderer = renderer,
            .input = input,
        };
        ui.id_stack[0] = id_mod.root_seed;
        return ui;
    }

    pub fn beginFrame(self: *UI, viewport: commands.Rect, show_layout_bounds: bool) void {
        self.viewport = viewport;
        self.hot_id = 0;
        self.show_layout_bounds = show_layout_bounds;
        self.layout_len = 0;
        self.id_len = 1;
        self.id_stack[0] = id_mod.root_seed;
        self.clip_depth = 0;
    }

    pub fn endFrame(self: *UI) void {
        while (self.clip_depth > 0) : (self.clip_depth -= 1) {
            self.renderer.popClip() catch unreachable;
        }

        if (self.input.mouseReleased(.left)) {
            self.active_id = 0;
        }
    }

    pub fn id(self: *UI, label: []const u8) id_mod.WidgetId {
        return id_mod.hash(self.id_stack[self.id_len - 1], label);
    }

    pub fn pushId(self: *UI, label: []const u8) void {
        if (self.id_len >= self.id_stack.len) return;
        self.id_stack[self.id_len] = self.id(label);
        self.id_len += 1;
    }

    pub fn popId(self: *UI) void {
        if (self.id_len > 1) self.id_len -= 1;
    }

    pub fn interact(self: *UI, widget_id: id_mod.WidgetId, rect: commands.Rect) Interaction {
        const hovered = self.input.hoveredRect(rect);
        if (hovered) self.hot_id = widget_id;

        const pressed = hovered and self.input.mousePressed(.left);
        if (pressed) self.active_id = widget_id;

        const held = self.active_id == widget_id and self.input.mouseDown(.left);
        const released = self.active_id == widget_id and self.input.mouseReleased(.left);
        return .{
            .hovered = hovered,
            .pressed = pressed,
            .held = held,
            .released = released,
            .clicked = released and hovered,
        };
    }

    pub fn beginPanel(self: *UI, title: []const u8, rect: commands.Rect) !void {
        self.pushId(title);
        const content = try widgets.panelFrame(self.renderer, &self.theme, title, rect);
        if (self.layout_len < self.layout_stack.len) {
            self.layout_stack[self.layout_len] = layout_mod.Stack.init(content, .vertical, 0, self.theme.gap);
            self.layout_len += 1;
        }
    }

    pub fn endPanel(self: *UI) void {
        if (self.layout_len > 0) self.layout_len -= 1;
        self.popId();
    }

    pub fn takeBlock(self: *UI, height: f32) commands.Rect {
        if (self.layout_len == 0) return commands.Rect.init(0, 0, 0, 0);
        const rect = self.layout_stack[self.layout_len - 1].next(height);
        if (self.show_layout_bounds) {
            self.renderer.pushStrokeRect(rect, self.theme.colors.accent, 1.0) catch unreachable;
        }
        return rect;
    }

    pub fn takeRemaining(self: *UI) commands.Rect {
        if (self.layout_len == 0) return commands.Rect.init(0, 0, 0, 0);
        const rect = self.layout_stack[self.layout_len - 1].takeRemaining();
        if (self.show_layout_bounds) {
            self.renderer.pushStrokeRect(rect, self.theme.colors.warning, 1.0) catch unreachable;
        }
        return rect;
    }

    pub fn text(self: *UI, text_bytes: []const u8) !void {
        const rect = self.takeBlock(self.theme.text_line_height);
        try widgets.label(self.renderer, &self.theme, text_bytes, rect, self.theme.colors.text);
    }

    pub fn button(self: *UI, label_text: []const u8) !bool {
        const rect = self.takeBlock(self.theme.button_height);
        return self.buttonAt(label_text, rect);
    }

    pub fn buttonAt(self: *UI, label_text: []const u8, rect: commands.Rect) !bool {
        const widget_id = self.id(label_text);
        const interaction = self.interact(widget_id, rect);
        try widgets.button(self.renderer, &self.theme, label_text, rect, .{
            .hovered = interaction.hovered,
            .held = interaction.held,
        });
        return interaction.clicked;
    }

    pub fn metricAt(
        self: *UI,
        label_text: []const u8,
        value_text: []const u8,
        rect: commands.Rect,
        accent: u32,
    ) !void {
        try widgets.metric(self.renderer, &self.theme, label_text, value_text, rect, accent);
    }

    pub fn labelAt(self: *UI, text_bytes: []const u8, rect: commands.Rect, tint: u32) !void {
        try widgets.label(self.renderer, &self.theme, text_bytes, rect, tint);
    }

    pub fn beginScrollArea(
        self: *UI,
        label_text: []const u8,
        height: f32,
        content_height: f32,
        offset: *f32,
    ) !commands.Rect {
        const shell = self.takeBlock(height);
        const widget_id = self.id(label_text);
        const interaction = self.interact(widget_id, shell);
        if (interaction.hovered and self.input.wheel_delta.y != 0) {
            const max_offset = if (content_height > shell.h) content_height - shell.h else 0;
            clip.clampScroll(offset, self.input.wheel_delta.y * 22, max_offset);
        }

        try self.renderer.pushClip(shell);
        self.clip_depth += 1;
        return commands.Rect.init(shell.x, shell.y - offset.*, shell.w, content_height);
    }

    pub fn endScrollArea(self: *UI) !void {
        if (self.clip_depth == 0) return;
        self.clip_depth -= 1;
        try self.renderer.popClip();
    }
};
