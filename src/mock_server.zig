const std = @import("std");

/// Simple mock 3270 server for testing
pub fn main() !void {
    const stdout = std.debug.print;

    // Create a 3270 screen response with sample data
    var response: [512]u8 = undefined;
    var idx: usize = 0;

    // Simple 3270 Write response with some text
    // Command: Write (0x01)
    response[idx] = 0x01;
    idx += 1;

    // WCC (Write Control Character) - enable keyboard
    response[idx] = 0xC2;
    idx += 1;

    // SBA (Set Buffer Address) - position 0,0
    response[idx] = 0x11;
    idx += 1;
    response[idx] = 0x00;
    idx += 1;
    response[idx] = 0x00;
    idx += 1;

    // Sample text: "WELCOME TO 3270 EMULATOR TEST"
    const text = "WELCOME TO 3270 EMULATOR TEST";
    @memcpy(response[idx .. idx + text.len], text);
    idx += text.len;

    // Add some spaces
    @memset(response[idx .. idx + 51], ' ');
    idx += 51;

    // SBA for line 2
    response[idx] = 0x11;
    idx += 1;
    response[idx] = 0x00;
    idx += 1;
    response[idx] = 0x50;
    idx += 1;

    // More text
    const text2 = "This is a test screen capture";
    @memcpy(response[idx .. idx + text2.len], text2);
    idx += text2.len;

    // Start server on port 3270
    const addr = try std.net.Address.parseIp("127.0.0.1", 3270);
    var server = try addr.listen(.{
        .reuse_address = true,
    });
    defer server.deinit();

    stdout("Mock 3270 Server listening on 127.0.0.1:3270\n", .{});
    stdout("Waiting for connections...\n", .{});
    stdout("(Press Ctrl+C to stop)\n", .{});

    var connection_count: u32 = 0;
    while (true) {
        const connection = try server.accept();
        defer connection.stream.close();

        connection_count += 1;
        stdout("\n[Connection #{}] Client connected\n", .{connection_count});

        // Send the response
        try connection.stream.writeAll(response[0..idx]);
        stdout("[Connection #{}] Sent {} bytes of 3270 screen data\n", .{ connection_count, idx });

        // Wait for client to read and disconnect
        std.posix.nanosleep(1, 0); // 1 second
    }
}
