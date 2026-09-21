const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zt_ui = b.addModule("zt_ui", .{
        .root_source_file = b.path("src/app.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "zt_ui",
        .root_module = zt_ui,
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = zt_ui,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
