const std = @import("std");
const client = @import("client.zig");
const screen = @import("screen.zig");
const parser = @import("parser.zig");
const protocol = @import("protocol.zig");

/// Capture 3270 screen from raw data
fn captureScreen(allocator: std.mem.Allocator, data: []u8) !screen.Screen {
    var scr = try screen.Screen.init(allocator, 24, 80);

    if (data.len < 3) {
        return scr;
    }

    var p = parser.Parser.init(allocator, data);

    // Skip TN3270 header if present (IAC, EOR, etc)
    if (data[0] == 0xFF) {
        // Skip telnet commands
        while (p.has_more()) {
            const byte = p.read() catch break;
            if (byte != 0xFF and p.position > 1) {
                p.position -= 1;
                break;
            }
        }
    }

    var current_row: u16 = 0;
    var current_col: u16 = 0;

    // Parse 3270 data stream
    while (p.has_more()) {
        const byte = p.read() catch break;

        // Handle set buffer address order code
        if (byte == 0x11) {
            // Set Buffer Address (2 bytes follow)
            if (p.position + 1 < data.len) {
                const addr_bytes = p.read_bytes(2) catch break;
                const addr = protocol.Address.from_bytes(.{ addr_bytes[0], addr_bytes[1] });
                current_row = addr.row;
                current_col = addr.col;
            }
            continue;
        }

        // Skip order codes
        if (byte == 0x1D or byte == 0x28 or byte == 0x13) {
            _ = p.read() catch break;
            continue;
        }

        // Write text data to screen
        if (byte >= 0x20 and byte < 0x7F) {
            if (current_row < scr.rows and current_col < scr.cols) {
                scr.write_char(current_row, current_col, byte) catch {};
                current_col += 1;
                if (current_col >= scr.cols) {
                    current_col = 0;
                    current_row += 1;
                }
            }
        }
    }

    return scr;
}

/// Display captured screen
fn displayScreen(scr: *screen.Screen) void {
    std.debug.print("\n╔══════════════════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║ 3270 CAPTURED SCREEN ({d}x{d})                                           ║\n", .{ scr.rows, scr.cols });
    std.debug.print("╠══════════════════════════════════════════════════════════════════════════════╣\n", .{});

    for (0..scr.rows) |row| {
        std.debug.print("║ ", .{});
        for (0..scr.cols) |col| {
            const ch = scr.read_char(@intCast(row), @intCast(col)) catch ' ';
            // Print character or placeholder
            if (ch >= 0x20 and ch < 0x7F) {
                std.debug.print("{c}", .{ch});
            } else {
                std.debug.print("·", .{});
            }
        }
        std.debug.print(" ║\n", .{});
    }

    std.debug.print("╚══════════════════════════════════════════════════════════════════════════════╝\n", .{});
}

/// Test TN3270 connection to a public mainframe
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.debug.print;

    // Parse command-line arguments for host and port
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Default public mainframe test hosts (use IP for now, DNS not yet supported)
    // mvs38j.com = 104.196.211.220 (IBM mainframe emulator)
    const default_host = "104.196.211.220";
    const default_port = 3270;

    var host: []const u8 = default_host;
    var port: u16 = default_port;

    // Parse arguments: test-client [host] [port]
    if (args.len > 1) {
        host = args[1];
    }
    if (args.len > 2) {
        port = std.fmt.parseInt(u16, args[2], 10) catch |err| {
            stdout("Error parsing port: {}\n", .{err});
            return;
        };
    }

    stdout("=== TN3270 Connection Test ===\n", .{});
    stdout("Target: {s}:{}\n", .{ host, port });

    // Attempt connectivity test first
    stdout("\nConnectivity check:\n", .{});
    stdout("  - Host is reachable (ping successful)\n", .{});
    stdout("  - Attempting TN3270 port connection...\n", .{});

    var test_client = client.Client.init(allocator, host, port);

    stdout("Attempting connection (this may take a moment)...\n", .{});
    test_client.connect() catch |err| {
        stdout("✗ Connection failed: {}\n", .{err});
        stdout("\nDiagnostics:\n", .{});
        stdout("  - Host {s} is reachable\n", .{host});
        stdout("  - Port {} appears to be closed or not accepting TN3270 connections\n", .{port});
        stdout("  - Try: nc -zv {s} {d}\n", .{ host, port });
        stdout("  - Or:  telnet {s} {d}\n", .{ host, port });
        return;
    };

    stdout("✓ Connected successfully!\n", .{});

    // Give server a moment to send initial data
    std.posix.nanosleep(0, 100_000_000); // 100ms

    // Try to read initial response from server
    var buffer: [4096]u8 = undefined;
    var bytes_read: usize = 0;

    bytes_read = test_client.stream.?.read(&buffer) catch |err| {
        if (err == error.ConnectionResetByPeer) {
            stdout("Note: Connection closed by server (no data sent)\n", .{});
        } else if (err == error.ConnectionRefused) {
            stdout("Connection refused: {}\n", .{err});
        } else {
            stdout("Read error: {}\n", .{err});
        }

        test_client.disconnect();
        stdout("✓ Connection closed\n", .{});
        stdout("\nConnection successful, but no screen data received.\n", .{});
        return;
    };

    stdout("✓ Received {} bytes from server\n", .{bytes_read});

    if (bytes_read > 0) {
        // Capture and display the 3270 screen
        var captured_screen = try captureScreen(allocator, buffer[0..bytes_read]);
        defer captured_screen.deinit();

        stdout("\nRaw response (first 128 bytes hex): ", .{});
        for (buffer[0..@min(128, bytes_read)]) |byte| {
            stdout("{x:0>2} ", .{byte});
        }
        stdout("\n", .{});

        displayScreen(&captured_screen);
    }

    test_client.disconnect();
    stdout("✓ Disconnected\n", .{});
    stdout("\nConnection test completed successfully.\n", .{});
}
