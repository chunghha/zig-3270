const std = @import("std");

/// 3270 Protocol Command Codes
pub const CommandCode = enum(u8) {
    erase_write = 0x05,
    erase_write_alt = 0x0D,
    write = 0x01,
    read_buffer = 0x02,
    read_modified = 0x06,
};

/// 3270 Order Codes
pub const OrderCode = enum(u8) {
    set_buffer_address = 0x11,
    start_field = 0x1D,
    set_attribute = 0x28,
    insert_cursor = 0x13,
    program_tab = 0x05,
    erase_unprotected = 0x12,
    graphic_escape = 0x08,
};

/// Field Attribute Flags
pub const FieldAttribute = packed struct {
    protected: bool = false,
    numeric: bool = false,
    hidden: bool = false,
    intensified: bool = false,
    modified: bool = false,
    reserved: u3 = 0,
};

/// 3270 Address (row, col)
pub const Address = struct {
    row: u8,
    col: u8,

    pub fn from_bytes(bytes: [2]u8) Address {
        const combined = (@as(u16, bytes[0]) << 8) | bytes[1];
        const row = @as(u8, @truncate(combined / 80));
        const col = @as(u8, @truncate(combined % 80));
        return Address{ .row = row, .col = col };
    }

    pub fn to_bytes(self: Address) [2]u8 {
        const combined: u16 = (self.row * 80) + self.col;
        return .{
            @as(u8, @truncate(combined >> 8)),
            @as(u8, @truncate(combined & 0xFF)),
        };
    }
};

test "address from bytes" {
    const addr = Address.from_bytes(.{ 0x00, 0x00 });
    try std.testing.expectEqual(@as(u8, 0), addr.row);
    try std.testing.expectEqual(@as(u8, 0), addr.col);
}

test "address to bytes" {
    const addr = Address{ .row = 0, .col = 0 };
    const bytes = addr.to_bytes();
    try std.testing.expectEqual(@as(u8, 0), bytes[0]);
    try std.testing.expectEqual(@as(u8, 0), bytes[1]);
}

test "address conversion round trip" {
    const original = .{ 0x00, 0x14 };
    const addr = Address.from_bytes(original);
    const bytes = addr.to_bytes();
    try std.testing.expectEqual(original[0], bytes[0]);
    try std.testing.expectEqual(original[1], bytes[1]);
}

test "field attribute structure" {
    var attr: FieldAttribute = .{};
    attr.protected = true;
    attr.intensified = true;
    try std.testing.expect(attr.protected);
    try std.testing.expect(attr.intensified);
    try std.testing.expect(!attr.numeric);
}
