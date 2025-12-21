const std = @import("std");
const emulator = @import("emulator.zig");
const protocol_layer = @import("protocol_layer.zig");
const domain_layer = @import("domain_layer.zig");
const protocol = @import("protocol.zig");
const command_mod = @import("command.zig");
const executor = @import("executor.zig");
const screen = @import("screen.zig");
const field = @import("field.zig");
const terminal_mod = @import("terminal.zig");
const parse_utils = @import("parse_utils.zig");

// End-to-end integration tests combining multiple modules
// Tests full workflows: screen updates, field parsing, command execution
// Validates protocol_layer and domain_layer facades work correctly together

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

// ============================================================================
// NEW E2E TESTS FOR LAYER FACADES
// ============================================================================

test "layer facade integration: protocol_layer with domain_layer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create screen (domain layer)
    var scr = try domain_layer.Screen.init(allocator, 24, 80);
    defer scr.deinit();

    // Create executor (domain layer)
    var fm = domain_layer.FieldManager.init(allocator);
    defer fm.deinit();
    var exec = domain_layer.Executor.init(allocator, &scr, &fm);

    // Build command using protocol layer
    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    try order_data.append(0x11); // Set Buffer Address
    try order_data.append(0x00);
    try order_data.append(0x00);
    try order_data.appendSlice("LayerTest");

    // Create command using protocol layer
    const cmd = protocol_layer.Command{
        .code = protocol_layer.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    // Execute through domain layer
    try exec.execute(cmd);

    // Verify through domain layer
    try std.testing.expectEqual(@as(u8, 'L'), try scr.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'a'), try scr.read_char(0, 1));
}

test "e2e: complex screen with multiple fields and cursor movement" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Create multi-field screen: label + input on line 0, another field on line 1
    var order_data = std.ArrayList(u8).init(allocator);
    defer order_data.deinit();

    // Line 1: Protected label
    try order_data.append(0x11); // Set Buffer Address (0,0)
    try order_data.append(0x00);
    try order_data.append(0x00);
    try order_data.append(0x1D); // Start Field
    try order_data.append(0x01); // Protected
    try order_data.appendSlice("Name: ");

    // Line 1: Unprotected input
    try order_data.append(0x11); // Set Buffer Address (0,6)
    try order_data.append(0x00);
    try order_data.append(0x06);
    try order_data.append(0x1D); // Start Field
    try order_data.append(0x00); // Unprotected
    try order_data.appendSlice("__________");

    // Line 2: Another field
    try order_data.append(0x11); // Set Buffer Address (1,0)
    try order_data.append(0x00);
    try order_data.append(0x50); // 80 in decimal = row 1
    try order_data.append(0x1D); // Start Field
    try order_data.append(0x00); // Unprotected
    try order_data.appendSlice("Comments: ");

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    try exec.execute(cmd);

    // Verify field structure
    try std.testing.expect(emu.field_count() >= 3);

    // Verify screen content
    try std.testing.expectEqual(@as(u8, 'N'), try emu.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, '_'), try emu.read_char(0, 6));
    try std.testing.expectEqual(@as(u8, 'C'), try emu.read_char(1, 0));
}

test "e2e: sequential commands (erase write then write)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // First command: Erase Write with initial content
    var order_data1 = std.ArrayList(u8).init(allocator);
    defer order_data1.deinit();

    try order_data1.append(0x11);
    try order_data1.append(0x00);
    try order_data1.append(0x00);
    try order_data1.appendSlice("Screen 1");

    const cmd1 = command_mod.Command{
        .code = protocol.CommandCode.erase_write,
        .data = try allocator.dupe(u8, order_data1.items),
    };
    defer allocator.free(cmd1.data);

    try exec.execute(cmd1);

    // Verify first screen
    try std.testing.expectEqual(@as(u8, 'S'), try emu.read_char(0, 0));

    // Second command: Write (partial update without erase)
    var order_data2 = std.ArrayList(u8).init(allocator);
    defer order_data2.deinit();

    try order_data2.append(0x11); // Set address to (0, 10)
    try order_data2.append(0x00);
    try order_data2.append(0x0A);
    try order_data2.appendSlice("Updated");

    const cmd2 = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data2.items),
    };
    defer allocator.free(cmd2.data);

    try exec.execute(cmd2);

    // Verify: old content at (0,0) should still exist
    try std.testing.expectEqual(@as(u8, 'S'), try emu.read_char(0, 0));
    // New content at (0,10)
    try std.testing.expectEqual(@as(u8, 'U'), try emu.read_char(0, 10));
}

test "e2e: protocol layer command parsing through executor" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Test parsing valid command codes
    const write_code = try parse_utils.parse_command_code(0x01);
    try std.testing.expectEqual(protocol.CommandCode.write, write_code);

    const read_code = try parse_utils.parse_command_code(0x06);
    try std.testing.expectEqual(protocol.CommandCode.read_modified, read_code);

    // Test parsing valid order codes
    const sba_code = try parse_utils.parse_order_code(0x11);
    try std.testing.expectEqual(protocol.OrderCode.set_buffer_address, sba_code);

    const sf_code = try parse_utils.parse_order_code(0x1D);
    try std.testing.expectEqual(protocol.OrderCode.start_field, sf_code);
}

test "e2e: terminal state with screen updates" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create screen and terminal
    var scr = try domain_layer.Screen.init(allocator, 24, 80);
    defer scr.deinit();

    const term = domain_layer.Terminal.init(allocator, &scr);

    // Verify initial state
    try std.testing.expectEqual(@as(u16, 0), term.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), term.cursor_col);

    // Write through terminal
    try term.write_string("Terminal Test");

    // Verify text was written to screen
    try std.testing.expectEqual(@as(u8, 'T'), try scr.read_char(0, 0));
    try std.testing.expectEqual(@as(u8, 'e'), try scr.read_char(0, 1));
}

test "e2e: address conversion round-trip with protocol layer" {
    // Verify address conversion works correctly for all screen positions
    for (0..24) |row| {
        for (0..80) |col| {
            const orig_addr = protocol_layer.Address{
                .row = @as(u8, @truncate(row)),
                .col = @as(u8, @truncate(col)),
            };

            // Convert to buffer position
            const buf_pos = parse_utils.address_to_buffer(orig_addr);

            // Convert back
            const new_addr = parse_utils.buffer_to_address(buf_pos);

            try std.testing.expectEqual(orig_addr.row, new_addr.row);
            try std.testing.expectEqual(orig_addr.col, new_addr.col);
        }
    }
}
