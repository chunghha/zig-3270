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
