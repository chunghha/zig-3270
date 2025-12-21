const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // libghostty-vt is an optional dependency that provides terminal emulation
    // using the real-world proven Ghostty terminal core. It's integrated via a
    // lazy dependency, so it only gets fetched/built if used.

    // Main module
    const main_module = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Try to add libghostty-vt as a dependency
    if (b.lazyDependency("libghostty_vt", .{
        .target = target,
        .optimize = optimize,
    })) |ghostty_dep| {
        main_module.addImport("ghostty_vt", ghostty_dep.module("ghostty-vt"));
    }

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zig-3270",
        .root_module = main_module,
    });

    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the 3270 emulator");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_module = b.addModule("test", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add libghostty-vt to test module as well
    if (b.lazyDependency("libghostty_vt", .{
        .target = target,
        .optimize = optimize,
    })) |ghostty_dep| {
        test_module.addImport("ghostty_vt", ghostty_dep.module("ghostty-vt"));
    }

    const test_exe = b.addTest(.{
        .root_module = test_module,
    });

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
