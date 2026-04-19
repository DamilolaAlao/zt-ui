const std = @import("std");
const commands = @import("commands.zig");

pub const max_commands = 2048;
pub const max_text_bytes = 48 * 1024;
pub const max_points = 4096;

pub const FrameArena = struct {
    commands_buf: [max_commands]commands.Command = undefined,
    commands_len: usize = 0,
    text_buf: [max_text_bytes]u8 = undefined,
    text_len: usize = 0,
    points_buf: [max_points]commands.Vec2 = undefined,
    points_len: usize = 0,

    pub fn reset(self: *FrameArena) void {
        self.commands_len = 0;
        self.text_len = 0;
        self.points_len = 0;
    }

    pub fn appendCommand(self: *FrameArena, command: commands.Command) !void {
        if (self.commands_len >= self.commands_buf.len) return error.OutOfMemory;
        self.commands_buf[self.commands_len] = command;
        self.commands_len += 1;
    }

    pub fn appendText(self: *FrameArena, bytes: []const u8) !u32 {
        if (self.text_len + bytes.len > self.text_buf.len) return error.OutOfMemory;
        const offset = self.text_len;
        @memcpy(self.text_buf[offset .. offset + bytes.len], bytes);
        self.text_len += bytes.len;
        return @intCast(offset);
    }

    pub fn appendPoints(self: *FrameArena, points: []const commands.Vec2) !u32 {
        if (self.points_len + points.len > self.points_buf.len) return error.OutOfMemory;
        const offset = self.points_len;
        @memcpy(self.points_buf[offset .. offset + points.len], points);
        self.points_len += points.len;
        return @intCast(offset);
    }

    pub fn commandSlice(self: *const FrameArena) []const commands.Command {
        return self.commands_buf[0..self.commands_len];
    }

    pub fn textSlice(self: *const FrameArena) []const u8 {
        return self.text_buf[0..self.text_len];
    }

    pub fn pointSlice(self: *const FrameArena) []const commands.Vec2 {
        return self.points_buf[0..self.points_len];
    }
};

pub const Renderer = struct {
    viewport: commands.Rect = commands.Rect.init(0, 0, 0, 0),
    frame: FrameArena = .{},

    pub fn init() Renderer {
        return .{};
    }

    pub fn beginFrame(self: *Renderer, viewport: commands.Rect, clear_color: u32) void {
        self.viewport = viewport;
        self.frame.reset();
        self.clear(clear_color) catch unreachable;
    }

    pub fn clear(self: *Renderer, color: u32) !void {
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.clear),
            .color = color,
            .x = self.viewport.x,
            .y = self.viewport.y,
            .w = self.viewport.w,
            .h = self.viewport.h,
        });
    }

    pub fn pushRect(self: *Renderer, rect: commands.Rect, color: u32) !void {
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.rect),
            .color = color,
            .x = rect.x,
            .y = rect.y,
            .w = rect.w,
            .h = rect.h,
        });
    }

    pub fn pushStrokeRect(self: *Renderer, rect: commands.Rect, color: u32, thickness: f32) !void {
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.stroke_rect),
            .color = color,
            .x = rect.x,
            .y = rect.y,
            .w = rect.w,
            .h = rect.h,
            .p0 = thickness,
        });
    }

    pub fn pushText(self: *Renderer, position: commands.Vec2, text: []const u8, color: u32, font_size: f32) !void {
        const offset = try self.frame.appendText(text);
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.text),
            .flags = @intCast(text.len),
            .color = color,
            .data0 = offset,
            .x = position.x,
            .y = position.y,
            .p0 = font_size,
        });
    }

    pub fn pushClip(self: *Renderer, rect: commands.Rect) !void {
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.clip_push),
            .x = rect.x,
            .y = rect.y,
            .w = rect.w,
            .h = rect.h,
        });
    }

    pub fn popClip(self: *Renderer) !void {
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.clip_pop),
        });
    }

    pub fn pushPolyline(self: *Renderer, points: []const commands.Vec2, color: u32, stroke_width: f32) !void {
        const offset = try self.frame.appendPoints(points);
        try self.frame.appendCommand(.{
            .tag = @intFromEnum(commands.CommandTag.polyline),
            .flags = @intCast(points.len),
            .color = color,
            .data0 = offset,
            .p0 = stroke_width,
        });
    }

    pub fn commandsPtr(self: *const Renderer) [*]const commands.Command {
        return self.frame.commands_buf[0..].ptr;
    }

    pub fn commandCount(self: *const Renderer) usize {
        return self.frame.commands_len;
    }

    pub fn textPtr(self: *const Renderer) [*]const u8 {
        return self.frame.text_buf[0..].ptr;
    }

    pub fn textLen(self: *const Renderer) usize {
        return self.frame.text_len;
    }

    pub fn pointsPtr(self: *const Renderer) [*]const commands.Vec2 {
        return self.frame.points_buf[0..].ptr;
    }

    pub fn pointLen(self: *const Renderer) usize {
        return self.frame.points_len;
    }
};

test "renderer records commands and payload slices" {
    var renderer = Renderer.init();
    renderer.beginFrame(commands.Rect.init(0, 0, 400, 240), 0);
    try renderer.pushText(commands.Vec2.init(20, 20), "hello", 0xff, 14);

    try std.testing.expect(renderer.commandCount() >= 2);
    try std.testing.expectEqual(@as(usize, 5), renderer.textLen());
}
