pub fn rgba(r: u8, g: u8, b: u8, a: u8) u32 {
    return @as(u32, r) |
        (@as(u32, g) << 8) |
        (@as(u32, b) << 16) |
        (@as(u32, a) << 24);
}

pub fn withAlpha(color: u32, alpha: u8) u32 {
    return (color & 0x00ff_ffff) | (@as(u32, alpha) << 24);
}
