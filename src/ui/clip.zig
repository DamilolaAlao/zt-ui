pub fn clampScroll(offset: *f32, delta_y: f32, max_offset: f32) void {
    const next = offset.* - delta_y;
    if (next < 0) {
        offset.* = 0;
    } else if (next > max_offset) {
        offset.* = max_offset;
    } else {
        offset.* = next;
    }
}
