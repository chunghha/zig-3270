const std = @import("std");

/// 3270 screen buffer management
pub const Screen = struct {
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    buffer: [][]u8,

    /// Initialize a screen buffer with the given dimensions
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Screen {
        var buffer = try allocator.alloc([]u8, rows);
        for (0..rows) |i| {
            buffer[i] = try allocator.alloc(u8, cols);
            @memset(buffer[i], ' ');
        }

        return Screen{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .buffer = buffer,
        };
    }

    /// Deallocate screen buffer
    pub fn deinit(self: *Screen) void {
        for (0..self.rows) |i| {
            self.allocator.free(self.buffer[i]);
        }
        self.allocator.free(self.buffer);
    }

    /// Clear entire screen (fill with spaces)
    pub fn clear(self: *Screen) void {
        for (0..self.rows) |i| {
            @memset(self.buffer[i], ' ');
        }
    }

    /// Write a character at position (row, col)
    pub fn write_char(self: *Screen, row: u16, col: u16, char: u8) !void {
        if (row >= self.rows or col >= self.cols) {
            return error.OutOfBounds;
        }
        self.buffer[row][col] = char;
    }

    /// Read a character at position (row, col)
    pub fn read_char(self: *Screen, row: u16, col: u16) !u8 {
        if (row >= self.rows or col >= self.cols) {
            return error.OutOfBounds;
        }
        return self.buffer[row][col];
    }
};

test "screen initialization" {
    var screen = try Screen.init(std.testing.allocator, 24, 80);
    defer screen.deinit();

    try std.testing.expectEqual(@as(u16, 24), screen.rows);
    try std.testing.expectEqual(@as(u16, 80), screen.cols);
}

test "screen buffer initialized with spaces" {
    var screen = try Screen.init(std.testing.allocator, 2, 3);
    defer screen.deinit();

    const char = try screen.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}

test "write and read character" {
    var screen = try Screen.init(std.testing.allocator, 2, 3);
    defer screen.deinit();

    try screen.write_char(0, 1, 'A');
    const char = try screen.read_char(0, 1);
    try std.testing.expectEqual(@as(u8, 'A'), char);
}

test "clear screen fills with spaces" {
    var screen = try Screen.init(std.testing.allocator, 2, 3);
    defer screen.deinit();

    try screen.write_char(0, 0, 'X');
    screen.clear();
    const char = try screen.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}

test "out of bounds access returns error" {
    var screen = try Screen.init(std.testing.allocator, 2, 3);
    defer screen.deinit();

    const result = screen.write_char(5, 5, 'A');
    try std.testing.expectError(error.OutOfBounds, result);
}
