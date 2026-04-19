pub const FrameClock = struct {
    frame_index: u64 = 0,
    delta_ms: f32 = 16.666,
    delta_seconds: f32 = 0.016_666,
    elapsed_seconds: f32 = 0,

    pub fn beginFrame(self: *FrameClock, dt_ms: f32) void {
        self.frame_index += 1;
        self.delta_ms = if (dt_ms > 0.01) dt_ms else 16.666;
        self.delta_seconds = self.delta_ms / 1000.0;
        self.elapsed_seconds += self.delta_seconds;
    }
};
