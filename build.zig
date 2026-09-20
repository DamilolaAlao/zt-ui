// Standard target options allow the person running `zig build` to choose
// what target to build for. Here we do not override the defaults, which
// means any target is allowed, and the default is native. Other options
// for restricting supported target set are available.
// Define platforms for cross-compilation support
const platforms = b.standardTargetOptions(.{
    .platforms = ["linux", "windows", "darwin"],
});
const target = platforms.target;
const optimize = b.standardOptimizeOption(.{});
const mod = b.addModule("zt_ui", {
    .root_source_file = b.path("src/root.zig"),
    .target = target,
});
const server = b.build("zt_ui", {
    target,
    name = "zt_ui",
});
