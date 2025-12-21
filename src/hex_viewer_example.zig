const std = @import("std");
const hex_viewer = @import("hex_viewer.zig");

/// Example program demonstrating the hex viewer for 3270 data
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== 3270 Hex Viewer Example ===\n\n", .{});

    // Example 1: Simple ASCII text
    std.debug.print("Example 1: Simple ASCII text\n", .{});
    const text = "IBM 3270";
    var viewer = hex_viewer.HexViewer.init(allocator, 16);
    try viewer.print(text);
    std.debug.print("\n", .{});

    // Example 2: Mixed ASCII and control characters
    std.debug.print("Example 2: Mixed ASCII and control characters\n", .{});
    const mixed = &[_]u8{
        0x1B, // ESC
        0x41, // 'A'
        0x00, // NUL
        0x42, // 'B'
        0x0D, // CR
        0x0A, // LF
        0x43, // 'C'
    };
    try viewer.print(mixed);
    std.debug.print("\n", .{});

    // Example 3: Longer data with multiple lines
    std.debug.print("Example 3: Longer data (16 bytes per line)\n", .{});
    const longer_data = "The quick brown fox jumps over the lazy dog";
    try viewer.print(longer_data);
    std.debug.print("\n", .{});

    // Example 4: Custom bytes per line
    std.debug.print("Example 4: Custom bytes per line (8 bytes)\n", .{});
    viewer = hex_viewer.HexViewer.init(allocator, 8);
    try viewer.print(longer_data);
    std.debug.print("\n", .{});

    // Example 5: Binary 3270 command sequence (mock data)
    std.debug.print("Example 5: Mock 3270 command sequence\n", .{});
    const command_seq = &[_]u8{
        0x5A, // Read Buffer
        0x13, // Attribute byte
        0xC1, // EBCDIC 'A'
        0xC2, // EBCDIC 'B'
        0xC3, // EBCDIC 'C'
        0x1D, // Start Field
        0x41, // Field attribute
    };
    try viewer.print(command_seq);
    std.debug.print("\n", .{});

    std.debug.print("=== End of Examples ===\n", .{});
}
