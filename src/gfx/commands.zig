const std = @import("std");

pub const Vec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
};

pub const Rect = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    pub fn init(x: f32, y: f32, w: f32, h: f32) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn right(self: Rect) f32 {
        return self.x + self.w;
    }

    pub fn bottom(self: Rect) f32 {
        return self.y + self.h;
    }

    pub fn insetAll(self: Rect, amount: f32) Rect {
        return self.insetXY(amount, amount);
    }

    pub fn insetXY(self: Rect, amount_x: f32, amount_y: f32) Rect {
        const next_w = if (self.w > amount_x * 2) self.w - amount_x * 2 else 0;
        const next_h = if (self.h > amount_y * 2) self.h - amount_y * 2 else 0;
        return .{
            .x = self.x + amount_x,
            .y = self.y + amount_y,
            .w = next_w,
            .h = next_h,
        };
    }

    pub fn cutTop(self: Rect, height: f32) Rect {
        return .{
            .x = self.x,
            .y = self.y,
            .w = self.w,
            .h = if (height < self.h) height else self.h,
        };
    }

    pub fn dropTop(self: Rect, height: f32) Rect {
        const used = if (height < self.h) height else self.h;
        return .{
            .x = self.x,
            .y = self.y + used,
            .w = self.w,
            .h = self.h - used,
        };
    }

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x >= self.x and
            point.x <= self.right() and
            point.y >= self.y and
            point.y <= self.bottom();
    }
};

pub const CommandTag = enum(u32) {
    clear = 0,
    rect = 1,
    stroke_rect = 2,
    text = 3,
    clip_push = 4,
    clip_pop = 5,
    polyline = 6,
};

pub const Command = extern struct {
    tag: u32 = @intFromEnum(CommandTag.clear),
    flags: u32 = 0,
    color: u32 = 0,
    data0: u32 = 0,
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,
    p0: f32 = 0,
    p1: f32 = 0,
    p2: f32 = 0,
    p3: f32 = 0,
};

comptime {
    std.debug.assert(@sizeOf(Command) == 48);
}

test "rect containment works" {
    const rect = Rect.init(10, 10, 100, 40);
    try std.testing.expect(rect.contains(Vec2.init(12, 25)));
    try std.testing.expect(!rect.contains(Vec2.init(200, 25)));
}
