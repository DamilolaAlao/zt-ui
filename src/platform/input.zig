const std = @import("std");
const commands = @import("../gfx/commands.zig");

pub const MouseButton = enum(u32) {
    left = 0,
    middle = 1,
    right = 2,
};

pub const ButtonState = struct {
    down: bool = false,
    pressed: bool = false,
    released: bool = false,
};

pub const InputState = struct {
    viewport: commands.Rect = commands.Rect.init(0, 0, 1280, 720),
    mouse_pos: commands.Vec2 = commands.Vec2.init(0, 0),
    mouse_delta: commands.Vec2 = commands.Vec2.init(0, 0),
    wheel_delta: commands.Vec2 = commands.Vec2.init(0, 0),
    buttons: [3]ButtonState = [_]ButtonState{ .{}, .{}, .{} },
    keys: [256]ButtonState = [_]ButtonState{.{}} ** 256,

    pub fn init() InputState {
        return .{};
    }

    pub fn setViewport(self: *InputState, viewport: commands.Rect) void {
        self.viewport = viewport;
    }

    pub fn pointerMove(self: *InputState, x: f32, y: f32) void {
        const next = commands.Vec2.init(x, y);
        self.mouse_delta = commands.Vec2.init(next.x - self.mouse_pos.x, next.y - self.mouse_pos.y);
        self.mouse_pos = next;
    }

    pub fn pointerButton(self: *InputState, raw_button: u32, down: bool) void {
        if (raw_button >= self.buttons.len) return;
        var button = &self.buttons[raw_button];
        if (button.down == down) return;
        button.pressed = down;
        button.released = !down;
        button.down = down;
    }

    pub fn pointerWheel(self: *InputState, delta_x: f32, delta_y: f32) void {
        self.wheel_delta.x += delta_x;
        self.wheel_delta.y += delta_y;
    }

    pub fn keyEvent(self: *InputState, code: u32, down: bool) void {
        if (code >= self.keys.len) return;
        var key = &self.keys[code];
        if (key.down == down) return;
        key.pressed = down;
        key.released = !down;
        key.down = down;
    }

    pub fn hoveredRect(self: *const InputState, rect: commands.Rect) bool {
        return rect.contains(self.mouse_pos);
    }

    pub fn mousePosition(self: *const InputState) commands.Vec2 {
        return self.mouse_pos;
    }

    pub fn mouseMoved(self: *const InputState) commands.Vec2 {
        return self.mouse_delta;
    }

    pub fn mouseDown(self: *const InputState, button: MouseButton) bool {
        return self.buttons[@intFromEnum(button)].down;
    }

    pub fn mousePressed(self: *const InputState, button: MouseButton) bool {
        return self.buttons[@intFromEnum(button)].pressed;
    }

    pub fn mouseReleased(self: *const InputState, button: MouseButton) bool {
        return self.buttons[@intFromEnum(button)].released;
    }

    pub fn keyPressed(self: *const InputState, code: u32) bool {
        return code < self.keys.len and self.keys[code].pressed;
    }

    pub fn endFrame(self: *InputState) void {
        self.mouse_delta = commands.Vec2.init(0, 0);
        self.wheel_delta = commands.Vec2.init(0, 0);
        for (&self.buttons) |*button| {
            button.pressed = false;
            button.released = false;
        }
        for (&self.keys) |*key| {
            key.pressed = false;
            key.released = false;
        }
    }
};

test "pointer input tracks position and clicks" {
    var input = InputState.init();
    input.pointerMove(30, 42);
    input.pointerButton(0, true);

    try std.testing.expectEqual(@as(f32, 30), input.mousePosition().x);
    try std.testing.expect(input.mousePressed(.left));
    try std.testing.expect(input.mouseDown(.left));
}
