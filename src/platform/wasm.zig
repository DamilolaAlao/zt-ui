const AppRuntime = @import("zt_ui").AppRuntime;

var runtime: AppRuntime = undefined;
var runtime_ready = false;

fn getRuntime() *AppRuntime {
    if (!runtime_ready) {
        runtime.init();
        runtime_ready = true;
    }
    return &runtime;
}

export fn initRuntime(width: f32, height: f32) void {
    var app = getRuntime();
    app.resize(width, height);
}

export fn resize(width: f32, height: f32) void {
    getRuntime().resize(width, height);
}

export fn beginFrame(dt_ms: f32) void {
    getRuntime().frame(dt_ms) catch unreachable;
}

export fn pointerMove(x: f32, y: f32) void {
    getRuntime().input.pointerMove(x, y);
}

export fn pointerButton(button: u32, down: bool) void {
    getRuntime().input.pointerButton(button, down);
}

export fn pointerWheel(delta_x: f32, delta_y: f32) void {
    getRuntime().input.pointerWheel(delta_x, delta_y);
}

export fn keyEvent(code: u32, down: bool) void {
    getRuntime().input.keyEvent(code, down);
}

export fn getCommandsPtr() usize {
    return @intFromPtr(getRuntime().renderer.commandsPtr());
}

export fn getCommandsLen() usize {
    return getRuntime().renderer.commandCount();
}

export fn getTextPtr() usize {
    return @intFromPtr(getRuntime().renderer.textPtr());
}

export fn getTextLen() usize {
    return getRuntime().renderer.textLen();
}

export fn getPointsPtr() usize {
    return @intFromPtr(getRuntime().renderer.pointsPtr());
}

export fn getPointsLen() usize {
    return getRuntime().renderer.pointLen();
}
