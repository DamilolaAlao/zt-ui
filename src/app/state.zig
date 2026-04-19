const std = @import("std");

pub const sample_count = 96;

pub const LogEntry = struct {
    agent: []const u8,
    stage: []const u8,
    detail: []const u8,
};

const default_logs = [_]LogEntry{
    .{ .agent = "scheduler", .stage = "queue", .detail = "Queued the next field workflow benchmark batch." },
    .{ .agent = "bridge", .stage = "sync", .detail = "Applied viewport and pointer updates from the browser host." },
    .{ .agent = "pipeline", .stage = "throughput", .detail = "Advanced rolling throughput samples for active workflows." },
    .{ .agent = "renderer", .stage = "flush", .detail = "Wrote rect, text, clip, and polyline commands." },
    .{ .agent = "review", .stage = "verify", .detail = "Checked widget identity scopes and scroll continuity." },
    .{ .agent = "overlay", .stage = "stats", .detail = "Published frame time, hover id, and command counts." },
};

pub const DashboardState = struct {
    sidebar_open: bool = true,
    debug_overlay: bool = true,
    layout_bounds: bool = false,
    streaming_paused: bool = false,
    chart_zoom: f32 = 1.0,
    chart_pan: f32 = 0.0,
    log_scroll: f32 = 0.0,
    elapsed: f32 = 0.0,
    stream_accumulator: f32 = 0.0,
    active_workflows: u32 = 12,
    benchmarks_today: u32 = 84,
    pipeline_throughput_per_hour: f32 = 148.0,
    benchmark_p95_ms: f32 = 112.0,
    samples: [sample_count]f32 = undefined,
    logs: [default_logs.len]LogEntry = default_logs,

    pub fn init() DashboardState {
        var state = DashboardState{};
        state.seedSamples();
        return state;
    }

    fn seedSamples(self: *DashboardState) void {
        for (&self.samples, 0..) |*sample, index| {
            const t = @as(f32, @floatFromInt(index)) / 8.5;
            sample.* = 148.0 + std.math.sin(t) * 16.0 + std.math.cos(t * 0.33) * 8.5;
        }
        self.pipeline_throughput_per_hour = self.samples[self.samples.len - 1];
        self.benchmark_p95_ms = 112.0;
    }

    pub fn tick(self: *DashboardState, dt: f32) void {
        self.elapsed += dt;
        if (self.streaming_paused) return;

        self.stream_accumulator += dt;
        if (self.stream_accumulator < 0.15) return;
        self.stream_accumulator = 0;

        var index: usize = 0;
        while (index + 1 < self.samples.len) : (index += 1) {
            self.samples[index] = self.samples[index + 1];
        }

        const wave = 152.0 +
            std.math.sin(self.elapsed * 1.55) * 18.0 +
            std.math.cos(self.elapsed * 0.58) * 8.0;
        self.samples[self.samples.len - 1] = wave;
        self.pipeline_throughput_per_hour = wave;
        self.benchmark_p95_ms = 96.0 +
            @abs(std.math.sin(self.elapsed * 0.92)) * 24.0 +
            @abs(std.math.cos(self.elapsed * 0.37)) * 10.0;
        self.benchmarks_today += 1;
        self.active_workflows = 9 + @as(u32, @intFromFloat(@abs(std.math.sin(self.elapsed * 0.74)) * 9.0));
    }

    pub fn resetBenchmarks(self: *DashboardState) void {
        self.chart_zoom = 1.0;
        self.chart_pan = 0.0;
        self.log_scroll = 0;
        self.active_workflows = 12;
        self.benchmarks_today = 84;
        self.seedSamples();
    }
};

test "tick advances the live sample window" {
    var state = DashboardState.init();
    const before = state.samples[state.samples.len - 1];
    state.tick(0.2);
    try std.testing.expect(before != state.samples[state.samples.len - 1]);
}
