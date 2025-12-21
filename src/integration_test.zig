const std = @import("std");
const emulator = @import("emulator.zig");
const protocol = @import("protocol.zig");
const command_mod = @import("command.zig");
const executor = @import("executor.zig");
const screen = @import("screen.zig");
const field = @import("field.zig");
const parse_utils = @import("parse_utils.zig");

// End-to-end integration tests combining multiple modules
// Tests full workflows: screen updates, field parsing, command execution

test "full screen update cycle: erase write with field and data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize emulator
    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Initialize executor (handles command execution)
    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Build a Write command with orders:
    // 1. Set buffer address to (0, 0)
    // 2. Start field (unprotected)
    // 3. Write "Hello"
    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    // Order: Set Buffer Address (0x11) at position 0,0
    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(0x00); // Row 0
    try order_data.append(0x00); // Col 0

    // Order: Start Field (0x1D) with attribute 0x00 (unprotected)
    try order_data.append(0x1D); // Start Field
    try order_data.append(0x00); // Attribute: unprotected

    // Text data
    try order_data.appendSlice("Hello");

    // Create and execute command
    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    try exec.execute(cmd);

    // Verify results
    // Text should be written to screen
    try std.testing.expectEqual(@as(u8, 'H'), try emu.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'e'), try emu.read_char(0, 1));
    try std.testing.expectEqual(@as(u8, 'l'), try emu.read_char(0, 2));
    try std.testing.expectEqual(@as(u8, 'l'), try emu.read_char(0, 3));
    try std.testing.expectEqual(@as(u8, 'o'), try emu.read_char(0, 4));

    // Field should be created
    try std.testing.expectEqual(@as(usize, 1), emu.field_count());
}

test "full screen update cycle: multiple fields with different attributes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Build command with two fields:
    // Field 1 (0,0): Protected label "Username: "
    // Field 2 (0,10): Unprotected input area
    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    // Field 1: Protected text at (0,0)
    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(0x00); // (0, 0)
    try order_data.append(0x00);

    try order_data.append(0x1D); // Start Field
    try order_data.append(0x01); // Protected (bit 0 set in little-endian)

    try order_data.appendSlice("Username: ");

    // Field 2: Unprotected input at (0, 10)
    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(0x00); // (0, 10)
    try order_data.append(0x0A);

    try order_data.append(0x1D); // Start Field
    try order_data.append(0x00); // Unprotected

    try order_data.appendSlice("     ");

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    try exec.execute(cmd);

    // Verify field 1 text
    try std.testing.expectEqual(@as(u8, 'U'), try emu.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 's'), try emu.read_char(0, 1));

    // Verify field 2 starts with spaces
    try std.testing.expectEqual(@as(u8, ' '), try emu.read_char(0, 15));

    // Should have 2 fields
    try std.testing.expectEqual(@as(usize, 2), emu.field_count());
}

test "erase write command clears screen" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Write some initial data
    try emu.write_char(0, 0, 'A');
    try emu.write_char(0, 1, 'B');
    try emu.write_char(1, 0, 'C');

    // Verify data is there
    try std.testing.expectEqual(@as(u8, 'A'), try emu.read_char(0, 0));

    // Execute erase write command
    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(0x00); // (0, 0)
    try order_data.append(0x00);

    try order_data.appendSlice("New");

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.erase_write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    try exec.execute(cmd);

    // Old data should be cleared
    try std.testing.expectEqual(@as(u8, ' '), try emu.read_char(1, 0));

    // New data should be written
    try std.testing.expectEqual(@as(u8, 'N'), try emu.read_char(0, 0));
}

test "parse utils integration with protocol operations" {
    // Test that parse_utils works correctly with protocol types
    const addr = protocol.Address{ .row = 5, .col = 20 };

    // Convert to buffer position
    const buf_pos = parse_utils.address_to_buffer(addr);
    try std.testing.expectEqual(@as(u16, 420), buf_pos); // 5*80 + 20

    // Convert back
    const addr2 = parse_utils.buffer_to_address(buf_pos);
    try std.testing.expectEqual(addr.row, addr2.row);
    try std.testing.expectEqual(addr.col, addr2.col);
}

test "command execution with boundary conditions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Write at bottom-right of screen
    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    // Set address to (23, 79) - last position
    const last_addr = parse_utils.address_to_buffer(protocol.Address{ .row = 23, .col = 79 });
    const addr_bytes = protocol.Address.to_bytes(protocol.Address{ .row = 23, .col = 79 });

    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(addr_bytes[0]);
    try order_data.append(addr_bytes[1]);

    try order_data.append('X');

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    try exec.execute(cmd);

    // Verify write succeeded
    try std.testing.expectEqual(@as(u8, 'X'), try emu.read_char(23, 79));
}

test "full workflow: screen initialization, updates, and field management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create emulator
    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Initial state
    const size = emu.screen_size();
    try std.testing.expectEqual(@as(u16, 24), size.rows);
    try std.testing.expectEqual(@as(u16, 80), size.cols);
    try std.testing.expectEqual(@as(usize, 0), emu.field_count());

    // Add a field manually
    try emu.add_field(0, 40, .{});
    try std.testing.expectEqual(@as(usize, 1), emu.field_count());

    // Write text
    try emu.write_string("Test string");

    // Clear screen
    emu.clear_screen();
    try std.testing.expectEqual(@as(u8, ' '), try emu.read_char(0, 0));

    // Render
    try emu.render();
}
