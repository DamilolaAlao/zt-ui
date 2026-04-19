const std = @import("std");
const commands = @import("../gfx/commands.zig");

pub const Axis = enum {
    vertical,
    horizontal,
};

pub const Stack = struct {
    bounds: commands.Rect,
    axis: Axis,
    cursor: f32 = 0,
    gap: f32 = 0,
    padding: f32 = 0,

    pub fn init(bounds: commands.Rect, axis: Axis, padding: f32, gap: f32) Stack {
        return .{
            .bounds = bounds,
            .axis = axis,
            .padding = padding,
            .gap = gap,
        };
    }

    fn content(self: *const Stack) commands.Rect {
        return self.bounds.insetAll(self.padding);
    }

    pub fn next(self: *Stack, size: f32) commands.Rect {
        const content_rect = self.content();
        switch (self.axis) {
            .vertical => {
                const height = if (content_rect.h > self.cursor) @min(size, content_rect.h - self.cursor) else 0;
                const rect = commands.Rect.init(content_rect.x, content_rect.y + self.cursor, content_rect.w, height);
                self.cursor += height + self.gap;
                return rect;
            },
            .horizontal => {
                const width = if (content_rect.w > self.cursor) @min(size, content_rect.w - self.cursor) else 0;
                const rect = commands.Rect.init(content_rect.x + self.cursor, content_rect.y, width, content_rect.h);
                self.cursor += width + self.gap;
                return rect;
            },
        }
    }

    pub fn takeRemaining(self: *Stack) commands.Rect {
        const content_rect = self.content();
        switch (self.axis) {
            .vertical => {
                const height = if (content_rect.h > self.cursor) content_rect.h - self.cursor else 0;
                self.cursor = content_rect.h;
                return commands.Rect.init(content_rect.x, content_rect.y + self.cursor - height, content_rect.w, height);
            },
            .horizontal => {
                const width = if (content_rect.w > self.cursor) content_rect.w - self.cursor else 0;
                self.cursor = content_rect.w;
                return commands.Rect.init(content_rect.x + self.cursor - width, content_rect.y, width, content_rect.h);
            },
        }
    }
};

pub fn splitEqual(bounds: commands.Rect, axis: Axis, count: usize, gap: f32, out: []commands.Rect) void {
    if (count == 0) return;

    const total_gap = gap * @as(f32, @floatFromInt(if (count > 0) count - 1 else 0));
    switch (axis) {
        .horizontal => {
            const width = if (bounds.w > total_gap) (bounds.w - total_gap) / @as(f32, @floatFromInt(count)) else 0;
            var cursor = bounds.x;
            for (out[0..count]) |*rect| {
                rect.* = commands.Rect.init(cursor, bounds.y, width, bounds.h);
                cursor += width + gap;
            }
        },
        .vertical => {
            const height = if (bounds.h > total_gap) (bounds.h - total_gap) / @as(f32, @floatFromInt(count)) else 0;
            var cursor = bounds.y;
            for (out[0..count]) |*rect| {
                rect.* = commands.Rect.init(bounds.x, cursor, bounds.w, height);
                cursor += height + gap;
            }
        },
    }
}

test "equal split creates three columns" {
    var rects: [3]commands.Rect = undefined;
    splitEqual(commands.Rect.init(0, 0, 300, 50), .horizontal, rects.len, 10, rects[0..]);
    try std.testing.expectEqual(@as(f32, 0), rects[0].x);
    try std.testing.expect(rects[1].x > rects[0].x);
}
