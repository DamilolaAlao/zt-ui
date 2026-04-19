pub const Snapshot = struct {
    fps: f32 = 0,
    frame_ms: f32 = 0,
    command_count: usize = 0,
    text_bytes: usize = 0,
    point_count: usize = 0,
    hovered_id: u32 = 0,
    active_id: u32 = 0,
};

pub const FrameProfiler = struct {
    last: Snapshot = .{},

    pub fn finish(
        self: *FrameProfiler,
        frame_ms: f32,
        command_count: usize,
        text_bytes: usize,
        point_count: usize,
        hovered_id: u32,
        active_id: u32,
    ) void {
        self.last = .{
            .fps = if (frame_ms > 0.01) 1000.0 / frame_ms else 0,
            .frame_ms = frame_ms,
            .command_count = command_count,
            .text_bytes = text_bytes,
            .point_count = point_count,
            .hovered_id = hovered_id,
            .active_id = active_id,
        };
    }
};
