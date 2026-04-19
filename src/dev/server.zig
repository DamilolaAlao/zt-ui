const std = @import("std");

pub const default_port: u16 = 8080;
pub const default_host: []const u8 = "127.0.0.1";
pub const web_root = "web";
pub const health_check_path = "healthz";
const request_buffer_size = 8 * 1024;
const stream_buffer_size = 4 * 1024;

pub const RequestTargetError = error{
    InvalidPath,
    PathTooLong,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const port = try resolvePort(args, allocator);

    const host_env = std.process.getEnvVarOwned(allocator, "ZT_UI_HOST") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (host_env) |value| allocator.free(value);
    const host = if (host_env) |value| value else default_host;

    const address = try std.net.Address.parseIp(host, port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.log.info("serving {s} on http://{s}:{d}", .{ web_root, host, port });

    var web_dir = try std.fs.cwd().openDir(web_root, .{});
    defer web_dir.close();

    while (true) {
        var connection = try server.accept();
        defer connection.stream.close();

        serveConnection(connection.stream, &web_dir) catch |err| {
            std.log.err("request failed: {}", .{err});
        };
    }
}

fn resolvePort(args: []const []const u8, allocator: std.mem.Allocator) !u16 {
    if (args.len >= 2) return parsePortValue(args[1]);

    const port_env = std.process.getEnvVarOwned(allocator, "ZT_UI_PORT") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (port_env) |value| allocator.free(value);

    if (port_env) |value| return parsePortValue(value);
    return default_port;
}

fn parsePortValue(raw: []const u8) !u16 {
    const port = try std.fmt.parseInt(u16, raw, 10);
    if (port == 0) return error.InvalidPort;
    return port;
}

fn serveConnection(stream: std.net.Stream, web_dir: *std.fs.Dir) !void {
    var request_buf: [request_buffer_size]u8 = undefined;
    const request = readRequest(stream, &request_buf) catch |err| switch (err) {
        error.RequestTooLarge => return writeTextResponse(stream, "431 Request Header Fields Too Large", "Request headers exceeded the supported size.\n"),
        else => return err,
    };
    if (request.len == 0) return;

    const line_end = std.mem.indexOf(u8, request, "\r\n") orelse
        std.mem.indexOfScalar(u8, request, '\n') orelse
        return writeTextResponse(stream, "400 Bad Request", "Malformed request line.\n");
    const line = request[0..line_end];

    var parts = std.mem.tokenizeScalar(u8, line, ' ');
    const method = parts.next() orelse
        return writeTextResponse(stream, "400 Bad Request", "Missing request method.\n");
    const target = parts.next() orelse
        return writeTextResponse(stream, "400 Bad Request", "Missing request target.\n");

    const is_get = std.mem.eql(u8, method, "GET");
    const is_head = std.mem.eql(u8, method, "HEAD");
    if (!is_get and !is_head) {
        return writeTextResponse(stream, "405 Method Not Allowed", "Only GET and HEAD are supported.\n");
    }

    var normalized_buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = normalizeRequestTarget(target, &normalized_buf) catch {
        return writeTextResponse(stream, "400 Bad Request", "Invalid request target.\n");
    };

    std.log.info("{s} /{s}", .{ method, normalized });

    if (std.mem.eql(u8, normalized, health_check_path)) {
        return writeTextResponse(stream, "200 OK", "ok\n");
    }

    var file = web_dir.openFile(normalized, .{}) catch |err| switch (err) {
        error.FileNotFound => return writeTextResponse(stream, "404 Not Found", "Resource not found.\n"),
        else => return err,
    };
    defer file.close();

    const stat = try file.stat();
    try writeHeader(stream, "200 OK", contentTypeForPath(normalized), stat.size);
    if (is_head) return;

    var file_buf: [stream_buffer_size]u8 = undefined;
    while (true) {
        const read = try file.read(&file_buf);
        if (read == 0) break;
        try stream.writeAll(file_buf[0..read]);
    }
}

fn readRequest(stream: std.net.Stream, buffer: []u8) ![]const u8 {
    var used: usize = 0;
    while (used < buffer.len) {
        const read = try stream.read(buffer[used..]);
        if (read == 0) break;
        used += read;

        if (std.mem.indexOf(u8, buffer[0..used], "\r\n\r\n") != null or
            std.mem.indexOf(u8, buffer[0..used], "\n\n") != null)
        {
            break;
        }
    }

    if (used == buffer.len and
        std.mem.indexOf(u8, buffer, "\r\n\r\n") == null and
        std.mem.indexOf(u8, buffer, "\n\n") == null)
    {
        return error.RequestTooLarge;
    }

    return buffer[0..used];
}

fn writeHeader(stream: std.net.Stream, status: []const u8, content_type: []const u8, content_length: u64) !void {
    var header_buf: [1024]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\nContent-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n",
        .{ status, content_type, content_length },
    );
    try stream.writeAll(header);
}

fn writeTextResponse(stream: std.net.Stream, status: []const u8, body: []const u8) !void {
    try writeHeader(stream, status, "text/plain; charset=utf-8", body.len);
    try stream.writeAll(body);
}

pub fn normalizeRequestTarget(raw_target: []const u8, buffer: []u8) RequestTargetError![]const u8 {
    const trimmed = raw_target[0 .. std.mem.indexOfAny(u8, raw_target, "?#") orelse raw_target.len];
    const ends_with_slash = trimmed.len == 0 or trimmed[trimmed.len - 1] == '/';

    var out_len: usize = 0;
    var segments = std.mem.splitScalar(u8, trimmed, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) return error.InvalidPath;
        if (std.mem.indexOfScalar(u8, segment, '\\') != null) return error.InvalidPath;

        if (out_len != 0) {
            if (out_len + 1 > buffer.len) return error.PathTooLong;
            buffer[out_len] = '/';
            out_len += 1;
        }
        if (out_len + segment.len > buffer.len) return error.PathTooLong;
        @memcpy(buffer[out_len .. out_len + segment.len], segment);
        out_len += segment.len;
    }

    if (out_len == 0 or ends_with_slash) {
        const suffix = if (out_len == 0) "index.html" else "/index.html";
        if (out_len + suffix.len > buffer.len) return error.PathTooLong;
        @memcpy(buffer[out_len .. out_len + suffix.len], suffix);
        out_len += suffix.len;
    }

    return buffer[0..out_len];
}

pub fn contentTypeForPath(path: []const u8) []const u8 {
    const extension = std.fs.path.extension(path);
    if (std.mem.eql(u8, extension, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, extension, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, extension, ".js")) return "text/javascript; charset=utf-8";
    if (std.mem.eql(u8, extension, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, extension, ".svg")) return "image/svg+xml";
    if (std.mem.eql(u8, extension, ".wasm")) return "application/wasm";
    return "application/octet-stream";
}

test "normalize request target defaults root to index" {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = try normalizeRequestTarget("/", &buf);
    try std.testing.expectEqualStrings("index.html", normalized);
}

test "normalize request target keeps health check path stable" {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = try normalizeRequestTarget("/healthz", &buf);
    try std.testing.expectEqualStrings(health_check_path, normalized);
}

test "normalize request target strips query and keeps nested files" {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = try normalizeRequestTarget("/assets/app.js?v=1", &buf);
    try std.testing.expectEqualStrings("assets/app.js", normalized);
}

test "normalize request target maps directory targets to index" {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = try normalizeRequestTarget("/docs/", &buf);
    try std.testing.expectEqualStrings("docs/index.html", normalized);
}

test "normalize request target rejects traversal" {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    try std.testing.expectError(error.InvalidPath, normalizeRequestTarget("/../secret.txt", &buf));
}

test "content type covers wasm and javascript" {
    try std.testing.expectEqualStrings("application/wasm", contentTypeForPath("app.wasm"));
    try std.testing.expectEqualStrings("text/javascript; charset=utf-8", contentTypeForPath("boot.js"));
}

test "parse port value rejects zero" {
    try std.testing.expectError(error.InvalidPort, parsePortValue("0"));
}

test "parse port value accepts valid port" {
    try std.testing.expectEqual(@as(u16, 8080), try parsePortValue("8080"));
}
