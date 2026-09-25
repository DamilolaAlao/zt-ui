pub const AppRuntime = @import("app.zig").AppRuntime;

pub const platform = struct {
    pub const audio_events = @import("platform/audio_events.zig");
    pub const input = @import("platform/input.zig");
    pub const time = @import("platform/time.zig");
};

pub const gfx = struct {
    pub const atlas = @import("gfx/atlas.zig");
    pub const color = @import("gfx/color.zig");
    pub const commands = @import("gfx/commands.zig");
    pub const renderer = @import("gfx/renderer.zig");
    pub const text = @import("gfx/text.zig");
};

pub const ui = struct {
    pub const clip = @import("ui/clip.zig");
    pub const id = @import("ui/id.zig");
    pub const layout = @import("ui/layout.zig");
    pub const theme = @import("ui/theme.zig");
    pub const widgets = @import("ui/widgets.zig");
    pub const runtime = @import("ui/ui.zig");
};

pub const app = struct {
    pub const audio_sequence_panel = @import("app/audio_sequence_panel.zig");
    pub const audio_sequence_state = @import("app/audio_sequence_state.zig");
    pub const charts = @import("app/charts.zig");
    pub const dashboard = @import("app/dashboard.zig");
    pub const dino_panel = @import("app/dino_panel.zig");
    pub const dino_state = @import("app/dino_state.zig");
    pub const panels = @import("app/panels.zig");
    pub const state = @import("app/state.zig");
};

pub const debug = struct {
    pub const overlay = @import("debug/overlay.zig");
    pub const profiler = @import("debug/profiler.zig");
};

pub const dev = struct {
    pub const server = @import("dev/server.zig");
};

test {
    _ = @import("app.zig");
    _ = @import("dev/server.zig");
    _ = @import("platform/audio_events.zig");
    _ = @import("platform/audio_event_json.zig");
    _ = @import("platform/input.zig");
    _ = @import("platform/time.zig");
    _ = @import("gfx/renderer.zig");
    _ = @import("ui/ui.zig");
    _ = @import("app/audio_sequence_panel.zig");
    _ = @import("app/audio_sequence_state.zig");
    _ = @import("app/dashboard.zig");
    _ = @import("app/dino_panel.zig");
    _ = @import("app/dino_state.zig");
    _ = @import("debug/overlay.zig");
}
