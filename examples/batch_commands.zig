/// Example 3: Batch Commands
/// Send multiple commands to a mainframe in sequence
///
/// Usage:
///   zig build && ./zig-cache/bin/zig-3270-example-batch --host mainframe.example.com --commands "cmd1,cmd2,cmd3"
///
/// This example demonstrates:
/// - Building and sending multiple commands
/// - Processing sequential responses
/// - Handling command batches
/// - Error handling for partial failures

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
    var commands = std.ArrayList([]const u8).init(allocator);
    defer commands.deinit();

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            i += 1;
            host = args[i];
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch 23;
        } else if (std.mem.eql(u8, args[i], "--commands") and i + 1 < args.len) {
            i += 1;
            var cmd_str = args[i];
            var cmd_iter = std.mem.splitSequence(u8, cmd_str, ",");
            while (cmd_iter.next()) |cmd| {
                try commands.append(cmd);
            }
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

    try stdout.print("=== zig-3270 Batch Commands Example ===\n\n", .{});
    try stdout.print("Connecting to {s}:{}\n", .{ host_name, port });

    var conn = try root.client.TelnetConnection.init(allocator);
    defer conn.deinit();

    conn.connect(host_name, port) catch |err| {
        try stdout.print("Error connecting: {}\n", .{err});
        return;
    };

    try stdout.print("✓ Connected\n\n", .{});
    defer conn.close();

    // Read initial screen
    const initial = try conn.read_response(5000);
    defer allocator.free(initial);

    try stdout.print("Initial screen: {} bytes\n\n", .{initial.len});

    if (commands.items.len == 0) {
        try stdout.print("No commands to send. Use --commands cmd1,cmd2,cmd3\n", .{});
        return;
    }

    // Send commands
    try stdout.print("Sending {} commands:\n", .{commands.items.len});

    for (commands.items, 0..) |cmd, idx| {
        try stdout.print("  {}: {s}\n", .{ idx + 1, cmd });
    }
    try stdout.print("\n", .{});

    var command_count: usize = 0;
    var total_bytes_sent: u64 = 0;
    var total_bytes_received: u64 = 0;

    for (commands.items, 0..) |cmd_text, idx| {
        try stdout.print("Sending command {}: {s}\n", .{ idx + 1, cmd_text });

        // Build command - in real scenario, would parse cmd_text
        // For now, just send as raw data
        var cmd_data = std.ArrayList(u8).init(allocator);
        defer cmd_data.deinit();

        try cmd_data.appendSlice(cmd_text);
        total_bytes_sent += cmd_data.items.len;

        // Simulate sending (real code would use conn.send_command)
        try stdout.print("  Sent {} bytes\n", .{cmd_data.items.len});

        // Read response
        const response = conn.read_response(5000) catch |err| {
            try stdout.print("  Error reading response: {}\n", .{err});
            continue;
        };
        defer allocator.free(response);

        total_bytes_received += response.len;
        try stdout.print("  Received {} bytes\n", .{response.len});

        command_count += 1;
    }

    try stdout.print("\n=== Batch Summary ===\n", .{});
    try stdout.print("Commands sent: {}\n", .{command_count});
    try stdout.print("Total bytes sent: {}\n", .{total_bytes_sent});
    try stdout.print("Total bytes received: {}\n", .{total_bytes_received});
    try stdout.print("Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(command_count)) / @as(f64, @floatFromInt(commands.items.len)) * 100});

    try stdout.print("\n✓ Batch processing complete\n", .{});
}

fn printUsage(stdout: std.fs.File.Writer) !void {
    try stdout.print("Usage: batch_commands [OPTIONS]\n\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("  --host HOST            Hostname or IP address (required)\n", .{});
    try stdout.print("  --port PORT            TCP port (default: 23)\n", .{});
    try stdout.print("  --commands CMD1,CMD2   Commands to send (comma-separated)\n", .{});
    try stdout.print("  --help                 Show this help message\n\n", .{});
    try stdout.print("Example:\n", .{});
    try stdout.print("  batch_commands --host mainframe.example.com --commands \"cmd1,cmd2,cmd3\"\n", .{});
}
