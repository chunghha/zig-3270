const std = @import("std");
const emulator = @import("emulator.zig");
const client_mod = @import("client.zig");
const hex_viewer = @import("hex_viewer.zig");
const ghostty_vt_terminal = @import("ghostty_vt_terminal.zig");
const ghostty_vt_example = @import("ghostty_vt_example.zig");

// Optional: libghostty-vt integration (only available if dependency is available)
const has_ghostty_vt = @import("builtin").zig_backend != .other;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize emulator (facade that wraps screen, terminal, field, input)
    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    std.debug.print("=== 3270 Emulator ===\n", .{});
    const size = emu.screen_size();
    std.debug.print("Screen: {}x{}\n", .{ size.rows, size.cols });
    std.debug.print("Modules: Emulator (facade), Client, Hex Viewer\n", .{});
    if (has_ghostty_vt) {
        std.debug.print("libghostty-vt: Available\n", .{});
    } else {
        std.debug.print("libghostty-vt: Not integrated (optional)\n", .{});
    }

    // Demo: create a field and write text
    try emu.add_field(0, 20, .{});
    try emu.write_string("IBM 3270 Terminal");

    try emu.render();

    // Demonstrate client module (after screen render)
    std.debug.print("\n=== Client Connection Example ===\n", .{});
    const client = client_mod.Client.init(allocator, "mainframe.example.com", 3270);
    std.debug.print("Initialized client for {s}:{}\n", .{ client.host, client.port });
    std.debug.print("To connect to a real host, call client.connect()\n", .{});

    // Optional: Demonstrate libghostty-vt integration
    if (has_ghostty_vt) {
        std.debug.print("\n=== libghostty-vt Integration Demo ===\n", .{});
        var vt_term = try ghostty_vt_terminal.GhosttyVtTerminal.init(allocator, &emu.screen_buffer);
        defer vt_term.deinit();

        try vt_term.write_string("VT Terminal Output");
        const vt_output = try vt_term.getTerminalOutput();
        defer allocator.free(vt_output);
        std.debug.print("Output: {s}\n", .{vt_output});
    }
}

test {
    _ = @import("emulator.zig");
    _ = @import("protocol_layer.zig");
    _ = @import("domain_layer.zig");
    _ = @import("input.zig");
    _ = @import("attributes.zig");
    _ = @import("hex_viewer.zig");
    _ = @import("cli.zig");
    _ = @import("profile_manager.zig");
    _ = @import("session_recorder.zig");
    _ = ghostty_vt_example;
    _ = ghostty_vt_terminal;
    _ = client_mod;
}
