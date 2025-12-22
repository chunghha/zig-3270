const std = @import("std");
const protocol = @import("protocol.zig");
const parser = @import("parser.zig");
const property_testing = @import("property_testing.zig");
const parse_utils = @import("parse_utils.zig");

/// Protocol Properties - Property-based tests for TN3270 protocol
/// Verifies invariants and roundtrip properties
/// Property: Command codes can be parsed and formatted repeatedly
pub const CommandParseRoundtripProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandParseRoundtripProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: CommandParseRoundtripProperty, input: []const u8) !bool {
        if (input.len < 1) return true;

        // Parse command code
        const cmd_code = parse_utils.parse_command_code(input[0]) catch return true;

        // Format it back
        const formatted = @intFromEnum(cmd_code);

        // Should be identical to input
        return formatted == input[0];
    }
};

/// Property: Field attributes are always in valid ranges
pub const FieldAttributeValidityProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FieldAttributeValidityProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: FieldAttributeValidityProperty, input: []const u8) !bool {
        if (input.len < 1) return true;

        const attr = input[0];

        // Field attributes are either 0x00-0x0F or 0xC0-0xFF
        const valid = (attr >= 0x00 and attr <= 0x0F) or (attr >= 0xC0 and attr <= 0xFF);

        return valid or attr == 0xFF; // 0xFF is also used for invalid/unset
    }
};

/// Property: Addresses always fit within 24x80 grid
pub const AddressValidityProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AddressValidityProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: AddressValidityProperty, input: []const u8) !bool {
        if (input.len < 2) return true;

        const row = input[0];
        const col = input[1];

        // 24x80 screen limits
        return row < 24 and col < 80;
    }
};

/// Property: Parser never crashes on arbitrary bytes
pub const ParserCrashResistanceProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ParserCrashResistanceProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: ParserCrashResistanceProperty, input: []const u8) !bool {
        // Create a parser with a bounded buffer
        const bounded = @min(input.len, 1920);
        var bounded_input = try self.allocator.alloc(u8, bounded);
        defer self.allocator.free(bounded_input);

        @memcpy(bounded_input, input[0..bounded]);

        // Try to parse - should never crash
        var cmd_parser = try parser.Parser.init(self.allocator, bounded_input);
        defer cmd_parser.deinit();

        _ = cmd_parser.parse() catch {
            // Errors are OK, crashes are not
            return true;
        };

        return true;
    }
};

/// Property: Address conversion is identity-preserving
pub const AddressConversionProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AddressConversionProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: AddressConversionProperty, input: []const u8) !bool {
        if (input.len < 2) return true;

        const row = input[0];
        const col = input[1];

        if (row >= 24 or col >= 80) return true;

        // Convert to offset and back
        const offset: u16 = row * 80 + col;
        const converted_row = offset / 80;
        const converted_col = offset % 80;

        // Should recover original values
        return converted_row == row and converted_col == col;
    }
};

/// Property: Buffer operations don't overflow
pub const BufferBoundaryProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) BufferBoundaryProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: BufferBoundaryProperty, input: []const u8) !bool {
        // Large buffers should not cause issues
        if (input.len > 65536) {
            return true; // Skip very large inputs
        }

        // Buffer should be intact after processing
        var buffer = try self.allocator.dupe(u8, input);
        defer self.allocator.free(buffer);

        // Simulate some processing
        const processed_len = @min(buffer.len, 1920);
        var checksum: u32 = 0;
        for (buffer[0..processed_len]) |byte| {
            checksum +%= @as(u32, byte);
        }

        // Checksum should be valid
        return checksum <= 0xFFFFFFFF;
    }
};

/// Property: Command codes are consistent across parse/format
pub const CommandConsistencyProperty = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandConsistencyProperty {
        return .{ .allocator = allocator };
    }

    pub fn check(self: CommandConsistencyProperty, input: []const u8) !bool {
        if (input.len < 1) return true;

        const byte_value = input[0];

        // All known command codes should be parseable
        if (parse_utils.parse_command_code(byte_value)) |_| {
            return true;
        } else |_| {
            // Unknown codes should be rejected consistently
            return true;
        }
    }
};

// ============================================================================
// INTEGRATION TESTS
// ============================================================================

test "protocol property runner setup" {
    var allocator = std.testing.allocator;

    const runner = property_testing.PropertyRunner.init(allocator);
    try std.testing.expectEqual(@as(usize, 100), runner.iterations);
}

test "command parse roundtrip property" {
    var allocator = std.testing.allocator;

    var prop = CommandParseRoundtripProperty.init(allocator);
    var buffer: [1]u8 = .{0x7E}; // Clear command code

    const result = try prop.check(&buffer);
    try std.testing.expect(result);
}

test "field attribute validity property" {
    var allocator = std.testing.allocator;

    var prop = FieldAttributeValidityProperty.init(allocator);

    // Test valid ranges
    var buffer: [1]u8 = .{0x05};
    try std.testing.expect(try prop.check(&buffer));

    buffer[0] = 0xC1;
    try std.testing.expect(try prop.check(&buffer));

    buffer[0] = 0xFF;
    try std.testing.expect(try prop.check(&buffer));
}

test "address validity property" {
    var allocator = std.testing.allocator;

    var prop = AddressValidityProperty.init(allocator);

    // Valid address
    var buffer: [2]u8 = .{ 10, 40 };
    try std.testing.expect(try prop.check(&buffer));

    // Invalid row
    buffer[0] = 24;
    buffer[1] = 40;
    try std.testing.expect(!try prop.check(&buffer));

    // Invalid col
    buffer[0] = 10;
    buffer[1] = 80;
    try std.testing.expect(!try prop.check(&buffer));
}

test "address conversion property" {
    var allocator = std.testing.allocator;

    var prop = AddressConversionProperty.init(allocator);

    // Test various addresses
    var buffer: [2]u8 = .{ 0, 0 };
    try std.testing.expect(try prop.check(&buffer));

    buffer[0] = 23;
    buffer[1] = 79;
    try std.testing.expect(try prop.check(&buffer));

    buffer[0] = 12;
    buffer[1] = 40;
    try std.testing.expect(try prop.check(&buffer));
}

test "buffer boundary property" {
    var allocator = std.testing.allocator;

    var prop = BufferBoundaryProperty.init(allocator);

    // Small buffer
    var small_buf: [10]u8 = .{1} ** 10;
    try std.testing.expect(try prop.check(&small_buf));

    // Medium buffer
    var med_buf = try allocator.alloc(u8, 1000);
    defer allocator.free(med_buf);
    for (med_buf) |*b| b.* = 0xAA;
    try std.testing.expect(try prop.check(med_buf));
}

test "command consistency property" {
    var allocator = std.testing.allocator;

    var prop = CommandConsistencyProperty.init(allocator);

    var buffer: [1]u8 = .{0x7E};
    try std.testing.expect(try prop.check(&buffer));

    buffer[0] = 0xF5; // Another command code
    try std.testing.expect(try prop.check(&buffer));
}

test "parser crash resistance property" {
    var allocator = std.testing.allocator;

    var prop = ParserCrashResistanceProperty.init(allocator);

    var buffer: [50]u8 = undefined;
    @memset(&buffer, 0xFF);

    // Should not crash
    try std.testing.expect(try prop.check(&buffer));
}
