/// Example integration of libghostty-vt terminal emulation into the 3270 emulator.
/// This demonstrates using ghostty-vt to handle VT sequence parsing and terminal state.
const std = @import("std");
const ghostty_vt = @import("ghostty_vt");

/// Example of parsing a VT sequence using libghostty-vt
pub fn parseVtSequence(
    allocator: std.mem.Allocator,
    sequence: []const u8,
) !void {
    // Create a terminal for demonstration
    var terminal = try ghostty_vt.Terminal.init(allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer terminal.deinit(allocator);

    // Process the sequence byte by byte
    for (sequence) |byte| {
        try terminal.processByte(byte);
    }

    // Get the rendered output
    const rendered = try terminal.plainString(allocator);
    defer allocator.free(rendered);

    std.debug.print("Parsed output:\n{s}\n", .{rendered});
}

/// Example demonstrating cursor positioning and styling using libghostty-vt
pub fn demonstrateTerminalFeatures(allocator: std.mem.Allocator) !void {
    var terminal = try ghostty_vt.Terminal.init(allocator, .{
        .cols = 40,
        .rows = 10,
    });
    defer terminal.deinit(allocator);

    // Print some styled text
    try terminal.printString("Styled Text Demo");
    const output = try terminal.plainString(allocator);
    defer allocator.free(output);

    std.debug.print("Terminal capabilities demo:\n{s}\n", .{output});
}

test "libghostty_vt integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test basic terminal initialization
    var terminal = try ghostty_vt.Terminal.init(allocator, .{
        .cols = 80,
        .rows = 24,
    });
    defer terminal.deinit(allocator);

    // Test printing
    try terminal.printString("Hello from libghostty-vt!");
    const output = try terminal.plainString(allocator);
    defer allocator.free(output);

    try std.testing.expect(output.len > 0);
}
