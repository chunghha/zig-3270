/// Example 4: Screen Capture
/// Connect to a mainframe, capture the screen, and export it
///
/// Usage:
///   zig build && ./zig-cache/bin/zig-3270-example-capture --host mainframe.example.com --output screen.txt
///
/// This example demonstrates:
/// - Capturing screen state
/// - Parsing screen content
/// - Exporting to file
/// - Inspecting screen using StateInspector

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
    var output_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--host") and i + 1 < args.len) {
            i += 1;
            host = args[i];
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            port = std.fmt.parseInt(u16, args[i], 10) catch 23;
        } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            i += 1;
            output_file = args[i];
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

    try stdout.print("=== zig-3270 Screen Capture Example ===\n\n", .{});
    try stdout.print("Connecting to {s}:{}\n", .{ host_name, port });

    var conn = try root.client.TelnetConnection.init(allocator);
    defer conn.deinit();

    conn.connect(host_name, port) catch |err| {
        try stdout.print("Error connecting: {}\n", .{err});
        return;
    };

    try stdout.print("✓ Connected\n\n", .{});
    defer conn.close();

    // Read screen
    try stdout.print("Capturing screen...\n", .{});
    const screen_data = try conn.read_response(5000);
    defer allocator.free(screen_data);

    try stdout.print("✓ Screen captured ({} bytes)\n\n", .{screen_data.len});

    // Create an emulator to parse the screen
    var emulator = try root.emulator.Emulator.init(allocator, 24, 80);
    defer emulator.deinit();

    // Try to process as command
    if (screen_data.len > 0) {
        const cmd_code_byte = screen_data[0];
        if (isValidCommandCode(cmd_code_byte)) {
            const cmd = root.command.Command{
                .code = parseCommandCode(cmd_code_byte),
                .data = if (screen_data.len > 1)
                    screen_data[1..]
                else
                    &.{},
            };

            try emulator.process_command(cmd);
            try stdout.print("✓ Screen processed\n\n", .{});
        }
    }

    // Create state inspector and dump state
    var inspector = root.state_inspector.StateInspector.init(allocator);

    const screen_dump = try inspector.dump_screen_state(&emulator.screen_buffer);
    defer allocator.free(screen_dump);

    const field_dump = try inspector.dump_field_state(&emulator.field_manager);
    defer allocator.free(field_dump);

    // Print to console
    try stdout.print("=== Screen Dump ===\n\n", .{});
    try stdout.print("{s}\n", .{screen_dump});

    try stdout.print("\n=== Fields ===\n\n", .{});
    try stdout.print("{s}\n", .{field_dump});

    // Export to file if specified
    if (output_file) |file_path| {
        var file = try std.fs.cwd().createFile(file_path, .{});
        defer file.close();

        var file_writer = file.writer();

        try file_writer.print("=== zig-3270 Screen Capture ===\n\n", .{});
        try file_writer.print("Host: {s}:{}\n", .{ host_name, port });
        try file_writer.print("Captured at: ", .{});

        // Get current time
        const now = std.time.milliTimestamp();
        const timestamp = @divFloor(now, 1000);
        try file_writer.print("{d}\n\n", .{timestamp});

        try file_writer.print("{s}\n", .{screen_dump});
        try file_writer.print("\n{s}\n", .{field_dump});

        try stdout.print("✓ Screen exported to {s}\n", .{file_path});
    }

    try stdout.print("\n✓ Screen capture complete\n", .{});
}

fn isValidCommandCode(byte: u8) bool {
    return switch (byte) {
        0x01, 0x02, 0x05, 0x06, 0x0D => true,
        else => false,
    };
}

fn parseCommandCode(byte: u8) root.protocol.CommandCode {
    return switch (byte) {
        0x01 => .write,
        0x02 => .read_buffer,
        0x05 => .erase_write,
        0x06 => .read_modified,
        0x0D => .erase_write_alt,
        else => .write,
    };
}

fn printUsage(stdout: std.fs.File.Writer) !void {
    try stdout.print("Usage: screen_capture [OPTIONS]\n\n", .{});
    try stdout.print("Options:\n", .{});
    try stdout.print("  --host HOST        Hostname or IP address (required)\n", .{});
    try stdout.print("  --port PORT        TCP port (default: 23)\n", .{});
    try stdout.print("  --output FILE      Save screen to file\n", .{});
    try stdout.print("  --help             Show this help message\n\n", .{});
    try stdout.print("Example:\n", .{});
    try stdout.print("  screen_capture --host mainframe.example.com --output screen.txt\n", .{});
}
