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
const data_entry = @import("data_entry.zig");
const attributes = @import("attributes.zig");
const ghostty_vt_example = @import("ghostty_vt_example.zig");
const ghostty_vt_terminal = @import("ghostty_vt_terminal.zig");
const client_mod = @import("client.zig");

// Optional: libghostty-vt integration (only available if dependency is available)
const has_ghostty_vt = @import("builtin").zig_backend != .other;

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
    std.debug.print("Modules: Screen, Parser, Input, Terminal, Field Manager, Client\n", .{});
    if (has_ghostty_vt) {
        std.debug.print("libghostty-vt: Available\n", .{});
    } else {
        std.debug.print("libghostty-vt: Not integrated (optional)\n", .{});
    }

    // Demo: create a field and write text
    _ = try field_mgr.add_field(0, 20, .{});
    try term.write_string("IBM 3270 Terminal");

    try term.render();

    // Demonstrate client module (after screen render)
    std.debug.print("\n=== Client Connection Example ===\n", .{});
    const client = client_mod.Client.init(allocator, "mainframe.example.com", 3270);
    std.debug.print("Initialized client for {s}:{}\n", .{ client.host, client.port });
    std.debug.print("To connect to a real host, call client.connect()\n", .{});

    // Optional: Demonstrate libghostty-vt integration
    if (has_ghostty_vt) {
        std.debug.print("\n=== libghostty-vt Integration Demo ===\n", .{});
        var vt_term = try ghostty_vt_terminal.GhosttyVtTerminal.init(allocator, &scr);
        defer vt_term.deinit();

        try vt_term.write_string("VT Terminal Output");
        const vt_output = try vt_term.getTerminalOutput();
        defer allocator.free(vt_output);
        std.debug.print("Output: {s}\n", .{vt_output});
    }
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
    _ = @import("data_entry.zig");
    _ = @import("attributes.zig");
    _ = ghostty_vt_example;
    _ = ghostty_vt_terminal;
    _ = client_mod;
}
