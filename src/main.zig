const std = @import("std");
const screen = @import("screen.zig");
const parser = @import("parser.zig");
const input = @import("input.zig");
const renderer = @import("renderer.zig");
const protocol = @import("protocol.zig");
const command = @import("command.zig");
const stream_parser = @import("stream_parser.zig");
const terminal = @import("terminal.zig");
const field = @import("field.zig");
const executor = @import("executor.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize modules
    var scr = try screen.Screen.init(allocator, 24, 80);
    defer scr.deinit();

    var input_handler = input.InputHandler.init(allocator);
    defer input_handler.deinit();

    var term = terminal.Terminal.init(allocator, &scr);

    var field_mgr = field.FieldManager.init(allocator);
    defer field_mgr.deinit();

    std.debug.print("=== 3270 Emulator ===\n", .{});
    std.debug.print("Screen: {}x{}\n", .{ scr.rows, scr.cols });
    std.debug.print("Modules: Screen, Parser, Input, Terminal, Field Manager\n", .{});

    // Demo: create a field and write text
    _ = try field_mgr.add_field(0, 20, .{});
    try term.write_string("IBM 3270 Terminal");

    try term.render();
}

test {
    _ = @import("screen.zig");
    _ = @import("protocol.zig");
    _ = @import("parser.zig");
    _ = @import("input.zig");
    _ = @import("renderer.zig");
    _ = @import("command.zig");
    _ = @import("stream_parser.zig");
    _ = @import("terminal.zig");
    _ = @import("field.zig");
    _ = @import("executor.zig");
}
