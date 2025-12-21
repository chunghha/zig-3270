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

    // Visual test for libghostty-vt integration
    const ghostty_vt_visual_test_module = b.addModule("ghostty_vt_visual_test", .{
        .root_source_file = b.path("src/ghostty_vt_visual_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add libghostty-vt to visual test module
    if (b.lazyDependency("libghostty_vt", .{
        .target = target,
        .optimize = optimize,
    })) |ghostty_dep| {
        ghostty_vt_visual_test_module.addImport("ghostty_vt", ghostty_dep.module("ghostty-vt"));
    }

    const ghostty_vt_visual_test = b.addExecutable(.{
        .name = "ghostty-vt-visual-test",
        .root_module = ghostty_vt_visual_test_module,
    });

    // Client test program for TN3270 connection testing
    const client_test_module = b.addModule("client_test", .{
        .root_source_file = b.path("src/client_test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const client_test_exe = b.addExecutable(.{
        .name = "client-test",
        .root_module = client_test_module,
    });

    b.installArtifact(exe);
    b.installArtifact(ghostty_vt_visual_test);
    b.installArtifact(client_test_exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the 3270 emulator");
    run_step.dependOn(&run_cmd.step);

    // Visual test run step
    const run_ghostty_vt_test = b.addRunArtifact(ghostty_vt_visual_test);
    const ghostty_vt_test_step = b.step("test-ghostty", "Run libghostty-vt visual integration test");
    ghostty_vt_test_step.dependOn(&run_ghostty_vt_test.step);

    // Client test run step
    const run_client_test = b.addRunArtifact(client_test_exe);
    if (b.args) |args| {
        run_client_test.addArgs(args);
    }
    const client_test_step = b.step("test-connection", "Test TN3270 connection to mainframe");
    client_test_step.dependOn(&run_client_test.step);

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
