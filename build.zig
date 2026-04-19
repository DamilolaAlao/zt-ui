const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const host_target = b.standardTargetOptions(.{});

    const root_module = b.addModule("zt_ui", .{
        .root_source_file = b.path("src/main.zig"),
        .target = host_target,
    });

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the shared Zig tests");
    test_step.dependOn(&run_tests.step);

    const server = b.addExecutable(.{
        .name = "zt-ui-serve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dev/server.zig"),
            .target = host_target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(server);

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_module = b.createModule(.{
        .root_source_file = b.path("src/platform/wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zt_ui", .module = root_module },
        },
    });

    const wasm = b.addExecutable(.{
        .name = "app",
        .root_module = wasm_module,
    });
    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.export_memory = true;
    wasm.initial_memory = 524_288;
    wasm.max_memory = 4_194_304;
    wasm.stack_size = 65_536;

    b.installArtifact(wasm);

    const sync_wasm = b.addUpdateSourceFiles();
    sync_wasm.addCopyFileToSource(wasm.getEmittedBin(), "web/app.wasm");
    b.getInstallStep().dependOn(&sync_wasm.step);

    const wasm_step = b.step("wasm", "Build web/app.wasm for the browser shell");
    wasm_step.dependOn(&sync_wasm.step);

    const run_server = b.addRunArtifact(server);
    run_server.step.dependOn(&sync_wasm.step);
    if (b.args) |args| {
        run_server.addArgs(args);
    }

    const serve_step = b.step("serve", "Build web/app.wasm and serve web/ with the Zig dev server");
    serve_step.dependOn(&run_server.step);
}
