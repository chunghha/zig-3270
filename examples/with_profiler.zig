/// Example 2: With Profiler
/// Connect to a mainframe and collect performance metrics
///
/// Usage:
///   zig build && ./zig-cache/bin/zig-3270-example-profiler --host mainframe.example.com
///
/// This example demonstrates:
/// - Using the profiler for memory and timing analysis
/// - Tracking allocations
/// - Measuring operation duration
/// - Generating performance reports

const std = @import("std");
const root = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Parse arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var host: ?[]const u8 = null;
    var port: u16 = 23;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            i += 1;
            host = args[i];
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch 23;
        } else if (std.mem.eql(u8, args[i], "--help")) {
            try printUsage(stdout);
            return;
        }
    }

    if (host == null) {
        try stdout.print("Error: --host is required\n\n", .{});
        try printUsage(stdout);
        return;
    }

    const host_name = host.?;

    try stdout.print("=== zig-3270 Performance Profiler Example ===\n\n", .{});

    // Initialize profiler
    var profiler = root.profiler.Profiler.init(allocator);
    defer profiler.deinit();

    // Track initialization
    {
        var scope = profiler.scope("initialization");
        defer scope.end();

        try stdout.print("Initializing connection to {s}:{}\n", .{ host_name, port });

        // Record allocations
        profiler.record_alloc(@sizeOf(root.client.TelnetConnection));
    }

    var conn = try root.client.TelnetConnection.init(allocator);
    defer conn.deinit();

    // Track connection
    {
        var scope = profiler.scope("connect");
        defer scope.end();

        conn.connect(host_name, port) catch |err| {
            try stdout.print("Error connecting: {}\n", .{err});
            return;
        };
    }

    try stdout.print("✓ Connected\n\n", .{});
    defer conn.close();

    // Track reading response
    const response = blk: {
        var scope = profiler.scope("read_response");
        defer scope.end();

        break :blk try conn.read_response(5000);
    };
    defer allocator.free(response);

    profiler.record_alloc(response.len);

    try stdout.print("✓ Received {} bytes\n\n", .{response.len});

    // Print profiler reports
    try stdout.print("=== Memory Report ===\n", .{});
    try profiler.print_memory_report(stdout);

    try stdout.print("\n=== Timing Report ===\n", .{});
    try profiler.print_timing_report(stdout);

    try stdout.print("\n✓ Profiling complete\n", .{});
}

fn printUsage(stdout: std.fs.File.Writer) !void {
    try stdout.print("Usage: with_profiler [OPTIONS]\n\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("  --host HOST        Hostname or IP address (required)\n", .{});
    try stdout.print("  --port PORT        TCP port (default: 23)\n", .{});
    try stdout.print("  --help             Show this help message\n\n", .{});
    try stdout.print("Example:\n", .{});
    try stdout.print("  with_profiler --host mainframe.example.com\n", .{});
}
