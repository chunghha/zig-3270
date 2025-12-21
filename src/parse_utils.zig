const std = @import("std");
const protocol = @import("protocol.zig");

/// Parsing utility functions for protocol data streams
/// Consolidates common patterns used across command.zig, executor.zig, and data_entry.zig
/// Check if buffer has enough bytes to read
pub fn has_bytes(buffer: []const u8, pos: usize, n: usize) bool {
    return pos + n <= buffer.len;
}

/// Safe read of N bytes from buffer at position
pub fn read_bytes(buffer: []const u8, pos: usize, n: usize) ![]const u8 {
    if (!has_bytes(buffer, pos, n)) {
        return error.InsufficientData;
    }
    return buffer[pos .. pos + n];
}

/// Convert buffer position to 3270 screen address
pub fn buffer_to_address(pos: usize) protocol.Address {
    const row = @as(u8, @truncate(pos / 80));
    const col = @as(u8, @truncate(pos % 80));
    return protocol.Address{ .row = row, .col = col };
}

/// Convert 3270 screen address to buffer position
pub fn address_to_buffer(addr: protocol.Address) u16 {
    return (addr.row * 80) + addr.col;
}

/// Parse command code from byte
pub fn parse_command_code(byte: u8) !protocol.CommandCode {
    return std.meta.intToEnum(protocol.CommandCode, byte);
}

/// Parse order code from byte
pub fn parse_order_code(byte: u8) !protocol.OrderCode {
    return std.meta.intToEnum(protocol.OrderCode, byte);
}

/// Parse field attribute from byte
pub fn parse_field_attribute(byte: u8) protocol.FieldAttribute {
    return @bitCast(byte);
}

/// Encode field attribute to byte
pub fn encode_field_attribute(attr: protocol.FieldAttribute) u8 {
    return @bitCast(attr);
}

test "has bytes check" {
    const buffer = "hello";
    try std.testing.expect(has_bytes(buffer, 0, 5));
    try std.testing.expect(has_bytes(buffer, 0, 3));
    try std.testing.expect(!has_bytes(buffer, 0, 6));
    try std.testing.expect(!has_bytes(buffer, 4, 2));
}

test "read bytes" {
    const buffer = "hello world";
    const result = try read_bytes(buffer, 0, 5);
    try std.testing.expectEqualStrings("hello", result);

    const result2 = try read_bytes(buffer, 6, 5);
    try std.testing.expectEqualStrings("world", result2);
}

test "read bytes out of range" {
    const buffer = "hello";
    const result = read_bytes(buffer, 0, 10);
    try std.testing.expectError(error.InsufficientData, result);
}

test "buffer to address" {
    const addr0 = buffer_to_address(0);
    try std.testing.expectEqual(@as(u8, 0), addr0.row);
    try std.testing.expectEqual(@as(u8, 0), addr0.col);

    const addr20 = buffer_to_address(20);
    try std.testing.expectEqual(@as(u8, 0), addr20.row);
    try std.testing.expectEqual(@as(u8, 20), addr20.col);

    const addr80 = buffer_to_address(80);
    try std.testing.expectEqual(@as(u8, 1), addr80.row);
    try std.testing.expectEqual(@as(u8, 0), addr80.col);
}

test "address to buffer" {
    const buf0 = address_to_buffer(protocol.Address{ .row = 0, .col = 0 });
    try std.testing.expectEqual(@as(u16, 0), buf0);

    const buf20 = address_to_buffer(protocol.Address{ .row = 0, .col = 20 });
    try std.testing.expectEqual(@as(u16, 20), buf20);

    const buf80 = address_to_buffer(protocol.Address{ .row = 1, .col = 0 });
    try std.testing.expectEqual(@as(u16, 80), buf80);
}

test "parse command code" {
    const write = try parse_command_code(0x01);
    try std.testing.expectEqual(protocol.CommandCode.write, write);

    const read_mod = try parse_command_code(0x06);
    try std.testing.expectEqual(protocol.CommandCode.read_modified, read_mod);
}

test "parse order code" {
    const sba = try parse_order_code(0x11);
    try std.testing.expectEqual(protocol.OrderCode.set_buffer_address, sba);

    const sf = try parse_order_code(0x1D);
    try std.testing.expectEqual(protocol.OrderCode.start_field, sf);
}

test "parse field attribute" {
    // 0x09 = binary 00001001 = protected + intensified in little-endian packed struct
    const attr = parse_field_attribute(0x09);
    try std.testing.expect(attr.protected);
    try std.testing.expect(attr.intensified);
    try std.testing.expect(!attr.numeric);
}

test "encode field attribute" {
    var attr: protocol.FieldAttribute = .{};
    attr.protected = true;
    attr.intensified = true;
    const byte = encode_field_attribute(attr);
    try std.testing.expectEqual(@as(u8, 0x09), byte);
}
