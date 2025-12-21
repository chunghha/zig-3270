const std = @import("std");
const screen = @import("screen.zig");
const field = @import("field.zig");
const terminal = @import("terminal.zig");
const executor = @import("executor.zig");
const renderer = @import("renderer.zig");

/// Domain layer facade
/// Consolidates: screen.zig, field.zig, terminal.zig, executor.zig, renderer.zig
/// Provides unified interface for domain model operations (screen updates, rendering, etc.)

// Re-export domain types for public API
pub const Screen = screen.Screen;
pub const FieldManager = field.FieldManager;
pub const Field = field.Field;
pub const Terminal = terminal.Terminal;
pub const Executor = executor.Executor;
pub const Renderer = renderer.Renderer;

test "domain layer imports" {
    // Verify all domain types are accessible
    _ = Screen;
    _ = FieldManager;
    _ = Field;
    _ = Terminal;
    _ = Executor;
    _ = Renderer;
}

test "domain layer screen basic" {
    var scr = try Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try std.testing.expectEqual(@as(u16, 24), scr.rows);
    try std.testing.expectEqual(@as(u16, 80), scr.cols);

    try scr.write_char(0, 0, 'A');
    const char = try scr.read_char(0, 0);
    try std.testing.expectEqual(@as(u8, 'A'), char);
}

test "domain layer field manager basic" {
    var fm = field.FieldManager.init(std.testing.allocator);
    defer fm.deinit();

    try std.testing.expectEqual(@as(usize, 0), fm.count());
}

test "domain layer terminal basic" {
    var scr = try Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    const term = Terminal.init(std.testing.allocator, &scr);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_col);
}
