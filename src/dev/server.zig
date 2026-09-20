// ============================================================================
// zt-ui-serve - Main server entry point
// Handles HTTP serving and audio sequence panel rendering
// ============================================================================

const std = @import("std");
const Io = std.Io;
const Platform = std.platform;

pub const RequestTargetError = error{
    InvalidPath,
    PathTooLong,
};

pub fn main() !void {
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const port = try resolvePort(args, init.environ_map);
    const host = init.environ_map.get("ZT_UI_HOST") orelse default_host;

    var address = try Io.net.IpAddress.parse(host, port);
    var server = try address.listen(io, .{ .reuse_address = true });
    defer server.deinit(io);

    std.log.info("serving {s} on http://{s}:{d}", .{ web_root, host, port });
}
