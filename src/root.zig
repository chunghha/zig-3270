//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const ebcdic = @import("ebcdic.zig");
pub const protocol_snooper = @import("protocol_snooper.zig");
pub const state_inspector = @import("state_inspector.zig");
pub const cli_profiler = @import("cli_profiler.zig");
pub const structured_fields = @import("structured_fields.zig");
pub const lu3_printer = @import("lu3_printer.zig");
pub const graphics_support = @import("graphics_support.zig");
pub const connection_monitor = @import("connection_monitor.zig");
pub const diag_tool = @import("diag_tool.zig");
pub const mainframe_test = @import("mainframe_test.zig");
pub const fuzzing = @import("fuzzing.zig");
pub const performance_regression = @import("performance_regression.zig");
pub const session_pool = @import("session_pool.zig");
pub const session_lifecycle = @import("session_lifecycle.zig");
pub const session_migration = @import("session_migration.zig");
pub const load_balancer = @import("load_balancer.zig");
pub const failover = @import("failover.zig");
pub const health_checker = @import("health_checker.zig");
pub const audit_log = @import("audit_log.zig");
pub const compliance = @import("compliance.zig");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
