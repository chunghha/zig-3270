const std = @import("std");
const protocol = @import("protocol.zig");
const error_context = @import("error_context.zig");

/// Extended Structured Field (SF) support for Write Structured Field (WSF) commands
/// Implements TN3270 specification for advanced field attributes and screen modeling
/// Structured Field Type enumeration - WSF field types
pub const StructuredFieldType = enum(u8) {
    // 0x00 - Reserved
    read_partition = 0x01, // Query partition capabilities
    erase_reset = 0x03, // Erase all unprotected data
    set_reply_mode = 0x09, // Set reply mode for read commands
    outline = 0x0A, // Outline specification
    define_color_pair = 0x0B, // Color pair definition
    load_programmed_symbols = 0x0C, // LPS - Load symbols
    color_attribute = 0x10, // Color attribute
    extended_highlighting = 0x11, // Extended highlighting
    seal_unseal = 0x12, // Field seal/unseal
    character_set = 0x13, // 3270-DS character set
    transparency = 0x14, // Transparency attribute
    font = 0x15, // Font specification
    mode_mod = 0x16, // Mode modification
    image = 0x17, // Image specification
    cursor_position = 0x19, // Cursor address
    field_validation = 0x1A, // Field validation rules
    extended_field_attributes = 0x1B, // Extended field attributes
    graphics = 0x1C, // Graphics specification
    positioning = 0x1D, // Positioning spec
    formatting = 0x1E, // Formatting options
    _, // Unknown types

    pub fn to_bytes(self: StructuredFieldType) u8 {
        return @intFromEnum(self);
    }

    pub fn from_byte(byte: u8) ?StructuredFieldType {
        return std.meta.intToEnum(StructuredFieldType, byte) catch null;
    }
};

/// Structured Field Header
pub const StructuredFieldHeader = struct {
    field_type: StructuredFieldType,
    length: u16,
    flags: u8 = 0,

    const MIN_LENGTH = 3; // Type + length (2 bytes)

    pub fn from_buffer(buffer: []const u8) ?StructuredFieldHeader {
        if (buffer.len < MIN_LENGTH) return null;

        const length = (@as(u16, buffer[1]) << 8) | buffer[2];
        const field_type = StructuredFieldType.from_byte(buffer[0]) orelse return null;

        return .{
            .field_type = field_type,
            .length = length,
            .flags = if (buffer.len > 3) buffer[3] else 0,
        };
    }

    pub fn to_buffer(self: StructuredFieldHeader, buffer: []u8) !usize {
        if (buffer.len < MIN_LENGTH) return error.BufferTooSmall;

        buffer[0] = self.field_type.to_bytes();
        buffer[1] = @intCast((self.length >> 8) & 0xFF);
        buffer[2] = @intCast(self.length & 0xFF);

        return MIN_LENGTH;
    }
};

/// Color Pair Definition
pub const ColorPair = struct {
    pair_id: u8,
    foreground: u8,
    background: u8,

    pub fn from_buffer(buffer: []const u8) ?ColorPair {
        if (buffer.len < 3) return null;
        return .{
            .pair_id = buffer[0],
            .foreground = buffer[1],
            .background = buffer[2],
        };
    }
};

/// Extended Field Attributes
pub const ExtendedFieldAttribute = struct {
    attribute_type: u8,
    value: u8,

    pub fn from_buffer(buffer: []const u8) ?ExtendedFieldAttribute {
        if (buffer.len < 2) return null;
        return .{
            .attribute_type = buffer[0],
            .value = buffer[1],
        };
    }
};

/// Field Validation Rule
pub const FieldValidationRule = struct {
    rule_type: enum(u8) {
        mandatory = 0x01,
        optional = 0x02,
        trigger = 0x03,
        numeric = 0x04,
    },
    flags: u8 = 0,

    pub fn from_buffer(buffer: []const u8) ?FieldValidationRule {
        if (buffer.len < 1) return null;

        const rule_type = switch (buffer[0]) {
            0x01 => return .{ .rule_type = .mandatory },
            0x02 => return .{ .rule_type = .optional },
            0x03 => return .{ .rule_type = .trigger },
            0x04 => return .{ .rule_type = .numeric },
            else => return null,
        };

        return rule_type;
    }
};

/// Seal/Unseal specification
pub const SealUnseal = struct {
    operation: enum(u8) {
        seal = 0x00,
        unseal = 0x01,
    },
    field_address: protocol.Address,

    pub fn from_buffer(buffer: []const u8) ?SealUnseal {
        if (buffer.len < 3) return null;

        const op = switch (buffer[0]) {
            0x00 => @as(@TypeOf(@as(SealUnseal, undefined).operation), .seal),
            0x01 => .unseal,
            else => return null,
        };

        return .{
            .operation = op,
            .field_address = .{
                .row = buffer[1],
                .col = buffer[2],
            },
        };
    }
};

/// Transparency attribute (for overlaid fields)
pub const Transparency = struct {
    mode: enum(u8) {
        solid = 0x00,
        transparent = 0x01,
    },
    color: u8 = 0,

    pub fn from_buffer(buffer: []const u8) ?Transparency {
        if (buffer.len < 1) return null;

        const mode = switch (buffer[0]) {
            0x00 => @as(@TypeOf(@as(Transparency, undefined).mode), .solid),
            0x01 => .transparent,
            else => return null,
        };

        return .{
            .mode = mode,
            .color = if (buffer.len > 1) buffer[1] else 0,
        };
    }
};

/// Character Set specification
pub const CharacterSet = struct {
    set_id: enum(u8) {
        default = 0x00,
        ascii = 0x01,
        ebcdic = 0x02,
        apl = 0x03,
        local = 0x04,
    } = .default,
    code_page: u16 = 0,

    pub fn from_buffer(buffer: []const u8) ?CharacterSet {
        if (buffer.len < 1) return null;

        const set_id = switch (buffer[0]) {
            0x00 => @as(@TypeOf(@as(CharacterSet, undefined).set_id), .default),
            0x01 => .ascii,
            0x02 => .ebcdic,
            0x03 => .apl,
            0x04 => .local,
            else => return null,
        };

        const code_page = if (buffer.len > 2)
            (@as(u16, buffer[1]) << 8) | buffer[2]
        else
            0;

        return .{
            .set_id = set_id,
            .code_page = code_page,
        };
    }
};

/// Parsed Structured Field
pub const StructuredField = union(enum) {
    read_partition: StructuredFieldHeader,
    erase_reset: StructuredFieldHeader,
    color_pair: ColorPair,
    extended_field: ExtendedFieldAttribute,
    validation_rule: FieldValidationRule,
    seal_unseal: SealUnseal,
    transparency: Transparency,
    character_set: CharacterSet,
    unknown: struct {
        field_type: StructuredFieldType,
        data: []const u8,
    },

    pub fn parse(allocator: std.mem.Allocator, buffer: []const u8) !?StructuredField {
        const header = StructuredFieldHeader.from_buffer(buffer) orelse return null;

        // Check we have enough data for the full field
        if (buffer.len < header.length) return error.IncompleteField;

        const field_data = if (buffer.len > 3) buffer[3..header.length] else &.{};

        return switch (header.field_type) {
            .read_partition => .{ .read_partition = header },
            .erase_reset => .{ .erase_reset = header },
            .define_color_pair => blk: {
                const pair = ColorPair.from_buffer(field_data) orelse return error.InvalidColorPair;
                break :blk .{ .color_pair = pair };
            },
            .extended_field_attributes => blk: {
                const attr = ExtendedFieldAttribute.from_buffer(field_data) orelse return error.InvalidExtendedAttribute;
                break :blk .{ .extended_field = attr };
            },
            .field_validation => blk: {
                const rule = FieldValidationRule.from_buffer(field_data) orelse return error.InvalidValidationRule;
                break :blk .{ .validation_rule = rule };
            },
            .seal_unseal => blk: {
                const seal = SealUnseal.from_buffer(field_data) orelse return error.InvalidSealUnseal;
                break :blk .{ .seal_unseal = seal };
            },
            .transparency => blk: {
                const trans = Transparency.from_buffer(field_data) orelse return error.InvalidTransparency;
                break :blk .{ .transparency = trans };
            },
            .character_set => blk: {
                const charset = CharacterSet.from_buffer(field_data) orelse return error.InvalidCharacterSet;
                break :blk .{ .character_set = charset };
            },
            else => blk: {
                const data = try allocator.dupe(u8, field_data);
                break :blk .{
                    .unknown = .{
                        .field_type = header.field_type,
                        .data = data,
                    },
                };
            },
        };
    }

    pub fn deinit(self: *StructuredField, allocator: std.mem.Allocator) void {
        if (self.* == .unknown) {
            allocator.free(self.unknown.data);
        }
    }
};

/// Structured Field Parser
pub const StructuredFieldParser = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StructuredFieldParser {
        return .{ .allocator = allocator };
    }

    /// Parse a single structured field from buffer
    pub fn parse_field(self: StructuredFieldParser, buffer: []const u8) !?StructuredField {
        return try StructuredField.parse(self.allocator, buffer);
    }

    /// Parse multiple structured fields from buffer
    pub fn parse_fields(self: StructuredFieldParser, buffer: []const u8) !std.ArrayList(StructuredField) {
        var fields = std.ArrayList(StructuredField).init(self.allocator);
        var offset: usize = 0;

        while (offset < buffer.len) {
            if (try self.parse_field(buffer[offset..])) |field| {
                try fields.append(field);

                // Get length from header
                if (offset + 3 <= buffer.len) {
                    const len = (@as(u16, buffer[offset + 1]) << 8) | buffer[offset + 2];
                    offset += len;
                } else {
                    break;
                }
            } else {
                break;
            }
        }

        return fields;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "structured field type enum" {
    const ft = StructuredFieldType.read_partition;
    try std.testing.expectEqual(@as(u8, 0x01), ft.to_bytes());

    const ft2 = StructuredFieldType.from_byte(0x01);
    try std.testing.expect(ft2 != null);
    if (ft2) |f| {
        try std.testing.expectEqual(StructuredFieldType.read_partition, f);
    }
}

test "structured field header from buffer" {
    var buffer: [4]u8 = .{ 0x01, 0x00, 0x05, 0x42 };
    const header = StructuredFieldHeader.from_buffer(&buffer);

    try std.testing.expect(header != null);
    if (header) |h| {
        try std.testing.expectEqual(StructuredFieldType.read_partition, h.field_type);
        try std.testing.expectEqual(@as(u16, 5), h.length);
        try std.testing.expectEqual(@as(u8, 0x42), h.flags);
    }
}

test "structured field header to buffer" {
    var buffer: [3]u8 = undefined;
    const header = StructuredFieldHeader{
        .field_type = .read_partition,
        .length = 5,
    };

    const size = try header.to_buffer(&buffer);
    try std.testing.expectEqual(@as(usize, 3), size);
    try std.testing.expectEqual(@as(u8, 0x01), buffer[0]);
    try std.testing.expectEqual(@as(u8, 0x00), buffer[1]);
    try std.testing.expectEqual(@as(u8, 0x05), buffer[2]);
}

test "color pair from buffer" {
    var buffer: [3]u8 = .{ 0x01, 0x02, 0x03 };
    const pair = ColorPair.from_buffer(&buffer);

    try std.testing.expect(pair != null);
    if (pair) |p| {
        try std.testing.expectEqual(@as(u8, 0x01), p.pair_id);
        try std.testing.expectEqual(@as(u8, 0x02), p.foreground);
        try std.testing.expectEqual(@as(u8, 0x03), p.background);
    }
}

test "seal unseal from buffer" {
    var buffer: [3]u8 = .{ 0x00, 0x05, 0x0A };
    const seal = SealUnseal.from_buffer(&buffer);

    try std.testing.expect(seal != null);
    if (seal) |s| {
        try std.testing.expectEqual(SealUnseal.operation.seal, s.operation);
        try std.testing.expectEqual(@as(u8, 0x05), s.field_address.row);
        try std.testing.expectEqual(@as(u8, 0x0A), s.field_address.col);
    }
}

test "transparency from buffer" {
    var buffer: [2]u8 = .{ 0x01, 0x05 };
    const trans = Transparency.from_buffer(&buffer);

    try std.testing.expect(trans != null);
    if (trans) |t| {
        try std.testing.expectEqual(.transparent, t.mode);
        try std.testing.expectEqual(@as(u8, 0x05), t.color);
    }
}

test "character set from buffer" {
    var buffer: [3]u8 = .{ 0x02, 0x04, 0x37 };
    const charset = CharacterSet.from_buffer(&buffer);

    try std.testing.expect(charset != null);
    if (charset) |cs| {
        try std.testing.expectEqual(CharacterSet.set_id.ebcdic, cs.set_id);
        try std.testing.expectEqual(@as(u16, 0x0437), cs.code_page);
    }
}

test "structured field parser color pair" {
    var allocator = std.testing.allocator;
    var parser = StructuredFieldParser.init(allocator);

    // Color pair field: type=0x0B, length=0x0006, pair_id=0x01, fg=0x02, bg=0x03
    var buffer: [6]u8 = .{ 0x0B, 0x00, 0x06, 0x01, 0x02, 0x03 };

    const field = try parser.parse_field(&buffer);
    try std.testing.expect(field != null);

    if (field) |f| {
        try std.testing.expect(f == .color_pair);
        if (f == .color_pair) {
            try std.testing.expectEqual(@as(u8, 0x01), f.color_pair.pair_id);
        }
    }
}

test "structured field parser unknown field" {
    var allocator = std.testing.allocator;
    var parser = StructuredFieldParser.init(allocator);

    // Unknown field type
    var buffer: [5]u8 = .{ 0xFF, 0x00, 0x05, 0xAA, 0xBB };

    const field = try parser.parse_field(&buffer);
    try std.testing.expect(field != null);

    if (field) |f| {
        try std.testing.expect(f == .unknown);
        if (f == .unknown) {
            try std.testing.expectEqual(@as(usize, 2), f.unknown.data.len);
            defer allocator.free(f.unknown.data);
        }
    }
}

test "structured field parser multiple fields" {
    var allocator = std.testing.allocator;
    var parser = StructuredFieldParser.init(allocator);

    // Two color pair fields
    var buffer: [12]u8 = .{
        0x0B, 0x00, 0x06, 0x01, 0x02, 0x03, // First color pair
        0x0B, 0x00, 0x06, 0x04, 0x05, 0x06, // Second color pair
    };

    const fields = try parser.parse_fields(&buffer);
    defer {
        for (fields.items) |*f| {
            f.deinit(allocator);
        }
        fields.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), fields.items.len);
}

test "validation rule from buffer" {
    var buffer: [1]u8 = .{0x01};
    const rule = FieldValidationRule.from_buffer(&buffer);

    try std.testing.expect(rule != null);
    if (rule) |r| {
        try std.testing.expectEqual(FieldValidationRule.rule_type.mandatory, r.rule_type);
    }
}

test "extended field attribute from buffer" {
    var buffer: [2]u8 = .{ 0x01, 0x42 };
    const attr = ExtendedFieldAttribute.from_buffer(&buffer);

    try std.testing.expect(attr != null);
    if (attr) |a| {
        try std.testing.expectEqual(@as(u8, 0x01), a.attribute_type);
        try std.testing.expectEqual(@as(u8, 0x42), a.value);
    }
}

test "structured field type conversion roundtrip" {
    const types = [_]StructuredFieldType{
        .read_partition,
        .erase_reset,
        .define_color_pair,
        .seal_unseal,
        .transparency,
        .character_set,
    };

    for (types) |original| {
        const byte = original.to_bytes();
        const converted = StructuredFieldType.from_byte(byte);
        try std.testing.expect(converted != null);
        if (converted) |c| {
            try std.testing.expectEqual(original, c);
        }
    }
}

test "structured field header buffer roundtrip" {
    var buffer: [3]u8 = undefined;
    const original = StructuredFieldHeader{
        .field_type = .define_color_pair,
        .length = 0x0105,
    };

    _ = try original.to_buffer(&buffer);
    const parsed = StructuredFieldHeader.from_buffer(&buffer);

    try std.testing.expect(parsed != null);
    if (parsed) |p| {
        try std.testing.expectEqual(original.field_type, p.field_type);
        try std.testing.expectEqual(original.length, p.length);
    }
}
