const std = @import("std");
const screen = @import("screen.zig");

/// Renderer using libxghostty
pub const Renderer = struct {
    allocator: std.mem.Allocator,
    screen: *screen.Screen,

    /// Initialize renderer with a screen buffer
    pub fn init(allocator: std.mem.Allocator, scr: *screen.Screen) Renderer {
        return Renderer{
            .allocator = allocator,
            .screen = scr,
        };
    }

    /// Render screen contents to stdout (placeholder for libxghostty)
    pub fn render(self: *Renderer) !void {
        std.debug.print("\x1B[2J\x1B[H", .{});

        for (0..self.screen.rows) |row| {
            for (0..self.screen.cols) |col| {
                const char = self.screen.buffer[row][col];
                std.debug.print("{c}", .{char});
            }
            std.debug.print("\n", .{});
        }
    }

    /// Clear the rendered display
    pub fn clear(self: *Renderer) void {
        self.screen.clear();
    }

    /// Set a cell at position (row, col) with a character
    pub fn set_cell(self: *Renderer, row: u16, col: u16, char: u8) !void {
        try self.screen.write_char(row, col, char);
    }
};

test "renderer initialization" {
    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    const rend = Renderer.init(std.testing.allocator, &scr);
    try std.testing.expectEqual(@as(u16, 24), rend.screen.rows);
}

test "renderer set cell" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 3);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);
    try rend.set_cell(0, 0, 'X');

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'X'), char);
}

test "renderer clear" {
    var scr = try screen.Screen.init(std.testing.allocator, 2, 2);
    defer scr.deinit();

    var rend = Renderer.init(std.testing.allocator, &scr);
    try rend.set_cell(0, 0, 'Y');
    rend.clear();

    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, ' '), char);
}
