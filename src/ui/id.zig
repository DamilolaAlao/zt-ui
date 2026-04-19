const std = @import("std");

pub const WidgetId = u32;
pub const root_seed: WidgetId = 0x811c9dc5;

pub fn hash(scope: WidgetId, label: []const u8) WidgetId {
    var value = scope ^ 0x9e37_79b9;
    for (label) |byte| {
        value ^= @as(WidgetId, byte);
        value *%= 16_777_619;
    }
    return if (value == 0) 1 else value;
}

test "hash is stable for the same scope and label" {
    try std.testing.expectEqual(hash(root_seed, "button"), hash(root_seed, "button"));
}
