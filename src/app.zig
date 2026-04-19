const std = @import("std");
const commands = @import("gfx/commands.zig");
const Renderer = @import("gfx/renderer.zig").Renderer;
const InputState = @import("platform/input.zig").InputState;
const FrameClock = @import("platform/time.zig").FrameClock;
const ui_runtime = @import("ui/ui.zig");
const state_mod = @import("app/state.zig");
const dashboard = @import("app/dashboard.zig");
const overlay = @import("debug/overlay.zig");
const profiler = @import("debug/profiler.zig");

pub const AppRuntime = struct {
    viewport: commands.Rect = commands.Rect.init(0, 0, 1280, 720),
    input: InputState = InputState.init(),
    clock: FrameClock = .{},
    renderer: Renderer = Renderer.init(),
    ui: ui_runtime.UI = undefined,
    state: state_mod.DashboardState = state_mod.DashboardState.init(),
    overlay: overlay.OverlayState = .{},
    profiler: profiler.FrameProfiler = .{},

    pub fn init(self: *AppRuntime) void {
        self.viewport = commands.Rect.init(0, 0, 1280, 720);
        self.input = InputState.init();
        self.clock = .{};

        self.renderer = undefined;
        self.renderer.viewport = commands.Rect.init(0, 0, 0, 0);
        self.renderer.frame.commands_len = 0;
        self.renderer.frame.text_len = 0;
        self.renderer.frame.points_len = 0;

        self.state = state_mod.DashboardState.init();
        self.overlay = .{};
        self.profiler = .{};
        self.ui = ui_runtime.UI.init(&self.renderer, &self.input);
    }

    pub fn resize(self: *AppRuntime, width: f32, height: f32) void {
        self.viewport = commands.Rect.init(0, 0, width, height);
        self.input.setViewport(self.viewport);
    }

    pub fn frame(self: *AppRuntime, dt_ms: f32) !void {
        self.clock.beginFrame(dt_ms);

        if (self.input.keyPressed(192)) {
            self.overlay.visible = !self.overlay.visible;
        }
        if (self.input.keyPressed(71)) {
            self.overlay.show_layout_bounds = !self.overlay.show_layout_bounds;
            self.state.layout_bounds = self.overlay.show_layout_bounds;
        }

        self.state.tick(self.clock.delta_seconds);
        self.overlay.visible = self.state.debug_overlay;
        self.overlay.show_layout_bounds = self.state.layout_bounds;

        self.renderer.beginFrame(self.viewport, self.ui.theme.colors.canvas);
        self.ui.beginFrame(self.viewport, self.overlay.show_layout_bounds);
        try dashboard.draw(&self.ui, &self.state, self.viewport);
        self.ui.endFrame();

        self.profiler.finish(
            self.clock.delta_ms,
            self.renderer.commandCount(),
            self.renderer.textLen(),
            self.renderer.pointLen(),
            self.ui.hot_id,
            self.ui.active_id,
        );

        try overlay.draw(
            &self.renderer,
            &self.ui.theme,
            &self.overlay,
            &self.profiler.last,
            self.viewport,
        );

        self.input.endFrame();
    }
};

test "runtime initializes in place and produces a frame" {
    var runtime: AppRuntime = undefined;
    runtime.init();
    runtime.resize(800, 480);
    try runtime.frame(16.666);

    try std.testing.expect(runtime.renderer.commandCount() > 0);
}
