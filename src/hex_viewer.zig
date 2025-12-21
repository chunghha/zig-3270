const std = @import("std");

/// HexViewer displays raw bytes in hexadecimal and ASCII representation
/// Format: hex bytes on the left, ASCII printable chars on the right
pub const HexViewer = struct {
    allocator: std.mem.Allocator,
    bytes_per_line: usize = 16,

    /// Initialize hex viewer with custom or default bytes per line
    pub fn init(allocator: std.mem.Allocator, bytes_per_line: usize) HexViewer {
        return HexViewer{
            .allocator = allocator,
            .bytes_per_line = if (bytes_per_line > 0) bytes_per_line else 16,
        };
    }

    /// Format a slice of bytes into hex viewer output
    /// Caller owns the returned string and must free it
    pub fn format(self: HexViewer, data: []const u8) ![]const u8 {
        var output = std.ArrayList(u8).initCapacity(self.allocator, data.len * 4) catch std.ArrayList(u8){
            .items = &.{},
            .capacity = 0,
        };
        defer output.deinit(self.allocator);

        var offset: usize = 0;
        while (offset < data.len) {
            const chunk_size = @min(self.bytes_per_line, data.len - offset);
            const chunk = data[offset .. offset + chunk_size];

            // Format offset
            var buf: [1024]u8 = undefined;
            const offset_str = try std.fmt.bufPrint(&buf, "{X:0>8}  ", .{offset});
            try output.appendSlice(self.allocator, offset_str);

            // Format hex bytes
            for (0..self.bytes_per_line) |i| {
                if (i < chunk.len) {
                    const hex_str = try std.fmt.bufPrint(&buf, "{X:0>2} ", .{chunk[i]});
                    try output.appendSlice(self.allocator, hex_str);
                } else {
                    try output.appendSlice(self.allocator, "   ");
                }
            }

            try output.appendSlice(self.allocator, " |");

            // Format ASCII representation
            for (chunk) |byte| {
                const char: u8 = if (is_printable(byte)) byte else '.';
                try output.append(self.allocator, char);
            }

            try output.appendSlice(self.allocator, "|\n");

            offset += chunk_size;
        }

        return try output.toOwnedSlice(self.allocator);
    }

    /// Check if a byte is a printable ASCII character
    fn is_printable(byte: u8) bool {
        return byte >= 32 and byte <= 126;
    }

    /// Print hex viewer output to stdout
    pub fn print(self: HexViewer, data: []const u8) !void {
        const output = try self.format(data);
        defer self.allocator.free(output);
        std.debug.print("{s}", .{output});
    }
};

test "hex_viewer initialization" {
    const viewer = HexViewer.init(std.testing.allocator, 16);
    try std.testing.expectEqual(@as(usize, 16), viewer.bytes_per_line);
}

test "hex_viewer single line" {
    var viewer = HexViewer.init(std.testing.allocator, 16);
    const data = "Hello";
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "48 65 6C 6C 6F"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "Hello"));
}

test "hex_viewer multiple lines" {
    var viewer = HexViewer.init(std.testing.allocator, 4);
    const data = "ABCDEFGH";
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "41 42 43 44"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "45 46 47 48"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "ABCD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "EFGH"));
}

test "hex_viewer with non-printable bytes" {
    var viewer = HexViewer.init(std.testing.allocator, 16);
    const data = &[_]u8{ 0x00, 0x41, 0x1F, 0x42, 0x7F };
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "00 41 1F 42 7F"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "|.A.B.|"));
}

test "hex_viewer empty data" {
    var viewer = HexViewer.init(std.testing.allocator, 16);
    const data = "";
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    try std.testing.expectEqualSlices(u8, "", output);
}

test "hex_viewer custom bytes per line" {
    var viewer = HexViewer.init(std.testing.allocator, 8);
    const data = "0123456789ABCDEF";
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    var lines = std.mem.splitSequence(u8, output, "\n");
    var line_count: usize = 0;
    while (lines.next()) |line| {
        if (line.len > 0) {
            line_count += 1;
        }
    }

    try std.testing.expectEqual(@as(usize, 2), line_count);
}

test "hex_viewer offset formatting" {
    var viewer = HexViewer.init(std.testing.allocator, 4);
    const data = "ABCDEFGHIJKL";
    const output = try viewer.format(data);
    defer std.testing.allocator.free(output);

    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "00000000"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "00000004"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "00000008"));
}

// Stress tests for large files

test "hex_viewer stress test: 10KB binary data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var viewer = HexViewer.init(allocator, 16);

    // Create 10KB of test data (0-255 pattern repeated)
    var data = try std.ArrayList(u8).initCapacity(allocator, 10240);
    defer data.deinit(allocator);

    var i: u16 = 0;
    while (i < 10240) : (i += 1) {
        try data.append(allocator, @as(u8, @truncate(i % 256)));
    }

    // Format should complete without error
    const output = try viewer.format(data.items);
    defer allocator.free(output);

    // Verify output contains expected content
    try std.testing.expect(output.len > 0);

    // Output should contain multiple lines (10KB / 16 bytes per line = 640 lines)
    var line_count: usize = 0;
    var lines = std.mem.splitSequence(u8, output, "\n");
    while (lines.next()) |_| {
        line_count += 1;
    }
    try std.testing.expect(line_count >= 640);
}

test "hex_viewer stress test: 100KB with all byte values" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var viewer = HexViewer.init(allocator, 32);

    // Create 100KB of data cycling through all byte values
    var data = try std.ArrayList(u8).initCapacity(allocator, 102400);
    defer data.deinit(allocator);

    var total: u32 = 0;
    while (total < 102400) : (total += 1) {
        try data.append(allocator, @as(u8, @truncate(total % 256)));
    }

    const output = try viewer.format(data.items);
    defer allocator.free(output);

    // Verify basic properties
    try std.testing.expect(output.len > 0);

    // Count bytes - 100KB of data should produce roughly 102400 / 32 = 3200 lines
    var line_count: usize = 0;
    var lines = std.mem.splitSequence(u8, output, "\n");
    while (lines.next()) |line| {
        if (line.len > 0) line_count += 1;
    }
    try std.testing.expect(line_count >= 3000);
}

test "hex_viewer stress test: various bytes per line configs with large data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create 5KB test data
    var data = try std.ArrayList(u8).initCapacity(allocator, 5120);
    defer data.deinit(allocator);

    var i: u16 = 0;
    while (i < 5120) : (i += 1) {
        try data.append(allocator, @as(u8, @truncate(i % 256)));
    }

    // Test with different bytes_per_line values
    const configs = [_]usize{ 4, 8, 16, 32, 64 };

    for (configs) |bytes_per_line| {
        var viewer = HexViewer.init(allocator, bytes_per_line);
        const output = try viewer.format(data.items);
        defer allocator.free(output);

        // Each configuration should produce valid output
        try std.testing.expect(output.len > 0);

        // Line count should be roughly 5120 / bytes_per_line
        var line_count: usize = 0;
        var lines = std.mem.splitSequence(u8, output, "\n");
        while (lines.next()) |line| {
            if (line.len > 0) line_count += 1;
        }

        const expected_lines = 5120 / bytes_per_line;
        try std.testing.expect(line_count >= expected_lines);
    }
}

test "hex_viewer stress test: edge case - single large binary block" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var viewer = HexViewer.init(allocator, 16);

    // Create data with all zeros, then all 0xFF, then random pattern
    var data = try std.ArrayList(u8).initCapacity(allocator, 3072);
    defer data.deinit(allocator);

    // 1KB of zeros
    var i: u16 = 0;
    while (i < 1024) : (i += 1) {
        try data.append(allocator, 0x00);
    }

    // 1KB of 0xFF
    i = 0;
    while (i < 1024) : (i += 1) {
        try data.append(allocator, 0xFF);
    }

    // 1KB of alternating pattern
    i = 0;
    while (i < 1024) : (i += 1) {
        try data.append(allocator, if (i % 2 == 0) 0xAA else 0x55);
    }

    const output = try viewer.format(data.items);
    defer allocator.free(output);

    try std.testing.expect(output.len > 0);

    // Verify expected patterns are in output
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "00 00 00"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "FF FF FF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, output, 1, "AA 55 AA"));
}
