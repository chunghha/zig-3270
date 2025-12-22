/// Example 1: Simple Connect
/// Connect to a TN3270 mainframe and display the initial screen
///
/// Usage:
///   zig build && ./zig-cache/bin/zig-3270-example-simple --host mainframe.example.com --port 23
///
/// This example demonstrates:
/// - Creating a TelnetConnection
/// - Connecting to a mainframe
/// - Reading and displaying the initial screen
/// - Graceful disconnection

const std = @import("std");
const root = @import("zig3270");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    // Parse command-line arguments
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
            port = std.fmt.parseInt(u16, args[i], 10) catch {
                try stdout.print("Invalid port: {s}\n", .{args[i]});
                return;
            };
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

    try stdout.print("=== zig-3270 Simple Connect Example ===\n\n", .{});
    try stdout.print("Connecting to {s}:{}\n", .{ host_name, port });

    // Create connection
    var conn = try root.client.TelnetConnection.init(allocator);
    defer conn.deinit();

    // Connect to mainframe
    conn.connect(host_name, port) catch |err| {
        try stdout.print("Error connecting to {s}:{}: {}\n", .{ host_name, port, err });
        return;
    };
    try stdout.print("✓ Connected successfully\n\n", .{});
    defer conn.close();

    // Read initial screen
    try stdout.print("Reading initial screen...\n", .{});
    const response = conn.read_response(5000) catch |err| {
        try stdout.print("Error reading response: {}\n", .{err});
        return;
    };
    defer allocator.free(response);

    try stdout.print("✓ Received {} bytes\n\n", .{response.len});

    // Display the raw data as hex
    try stdout.print("Raw data (hex):\n", .{});
    for (response, 0..) |byte, idx| {
        if (idx % 16 == 0) {
            try stdout.print("{x:04}: ", .{idx});
        }
        try stdout.print("{x:02} ", .{byte});
        if ((idx + 1) % 16 == 0) {
            try stdout.print("\n", .{});
        }
    }
    if (response.len % 16 != 0) {
        try stdout.print("\n", .{});
    }

    // Display as ASCII (where printable)
    try stdout.print("\nRaw data (ASCII):\n", .{});
    for (response) |byte| {
        if (byte >= 32 and byte < 127) {
            try stdout.print("{c}", .{@as(u8, byte)});
        } else {
            try stdout.print(".", .{});
        }
    }
    try stdout.print("\n", .{});

    try stdout.print("\n✓ Connection closed\n", .{});
}

fn printUsage(stdout: std.fs.File.Writer) !void {
    try stdout.print("Usage: simple_connect [OPTIONS]\n\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("  --host HOST        Hostname or IP address (required)\n", .{});
    try stdout.print("  --port PORT        TCP port (default: 23)\n", .{});
    try stdout.print("  --help             Show this help message\n\n", .{});
    try stdout.print("Example:\n", .{});
    try stdout.print("  simple_connect --host mainframe.example.com --port 23\n", .{});
}
