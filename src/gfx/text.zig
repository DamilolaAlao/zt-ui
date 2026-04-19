pub const FontSpec = struct {
    size: f32 = 14,
};

pub const TextRun = struct {
    bytes: []const u8,
    font: FontSpec = .{},
};
