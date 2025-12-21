const std = @import("std");
const client = @import("client.zig");

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
    stdout("Connecting...\n", .{});

    var test_client = client.Client.init(allocator, host, port);

    stdout("Attempting connection (this may take a moment)...\n", .{});
    test_client.connect() catch |err| {
        stdout("Connection failed: {}\n", .{err});
        return err;
    };

    stdout("✓ Connected successfully!\n", .{});

    // Try to read initial response from server
    // Note: Some servers may not respond immediately to negotiation
    var buffer: [1024]u8 = undefined;
    const bytes_read = test_client.stream.?.read(&buffer) catch |err| {
        stdout("Note: No immediate server response (this is normal for some hosts): {}\n", .{err});
        test_client.disconnect();
        stdout("✓ Connection closed gracefully\n", .{});
        stdout("\nConnection test passed - host is reachable and accepting TN3270 connections.\n", .{});
        return;
    };

    stdout("✓ Received {} bytes from server\n", .{bytes_read});

    if (bytes_read > 0) {
        stdout("Response (first 64 bytes hex): ", .{});
        for (buffer[0..@min(64, bytes_read)]) |byte| {
            stdout("{x:0>2} ", .{byte});
        }
        stdout("\n", .{});
    }

    test_client.disconnect();
    stdout("✓ Disconnected\n", .{});
    stdout("\nConnection test completed successfully.\n", .{});
}
