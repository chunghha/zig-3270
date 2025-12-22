const std = @import("std");
const protocol = @import("protocol.zig");

/// Extended field validation and constraint support
/// Provides validation rules and constraints for 3270 fields
pub const FieldValidation = struct {
    /// Validation rule types
    pub const ValidationRule = enum {
        none,
        numeric_only,
        alphabetic_only,
        alphanumeric,
        date_mmddyy,
        date_ddmmyy,
        date_yyyymmdd,
        time_hhmmss,
        phone_number,
        credit_card,
        custom,
    };

    /// Validation constraint
    pub const Constraint = struct {
        rule: ValidationRule,
        min_length: usize = 0,
        max_length: usize = 0,
        pattern: ?[]const u8 = null,

        pub fn deinit(self: *Constraint, allocator: std.mem.Allocator) void {
            if (self.pattern) |p| {
                allocator.free(p);
            }
        }
    };

    /// Validate a field value against constraints
    pub fn validate(
        allocator: std.mem.Allocator,
        value: []const u8,
        constraint: Constraint,
    ) !bool {
        if (value.len < constraint.min_length or
            (constraint.max_length > 0 and value.len > constraint.max_length))
        {
            return false;
        }

        return switch (constraint.rule) {
            .none => true,
            .numeric_only => isNumericOnly(value),
            .alphabetic_only => isAlphabeticOnly(value),
            .alphanumeric => isAlphanumeric(value),
            .date_mmddyy => isValidDateMMDDYY(value),
            .date_ddmmyy => isValidDateDDMMYY(value),
            .date_yyyymmdd => isValidDateYYYYMMDD(value),
            .time_hhmmss => isValidTimeHHMMSS(value),
            .phone_number => isValidPhoneNumber(value),
            .credit_card => isValidCreditCard(value),
            .custom => true, // Custom validation handled by caller
        };
    }

    /// Get validation error message
    pub fn errorMessage(
        allocator: std.mem.Allocator,
        value: []const u8,
        constraint: Constraint,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();

        var writer = result.writer();

        if (value.len < constraint.min_length) {
            try writer.print("Field must contain at least {} characters (got {})", .{
                constraint.min_length,
                value.len,
            });
            return result.toOwnedSlice();
        }

        if (constraint.max_length > 0 and value.len > constraint.max_length) {
            try writer.print("Field must contain at most {} characters (got {})", .{
                constraint.max_length,
                value.len,
            });
            return result.toOwnedSlice();
        }

        const is_valid = try validate(allocator, value, constraint);
        if (!is_valid) {
            const rule_name = switch (constraint.rule) {
                .none => "valid",
                .numeric_only => "numeric",
                .alphabetic_only => "alphabetic",
                .alphanumeric => "alphanumeric",
                .date_mmddyy => "date (MM/DD/YY)",
                .date_ddmmyy => "date (DD/MM/YY)",
                .date_yyyymmdd => "date (YYYY/MM/DD)",
                .time_hhmmss => "time (HH:MM:SS)",
                .phone_number => "phone number",
                .credit_card => "credit card",
                .custom => "valid",
            };
            try writer.print("Field must be {s}", .{rule_name});
            return result.toOwnedSlice();
        }

        return try allocator.dupe(u8, "");
    }

    fn isNumericOnly(value: []const u8) bool {
        for (value) |ch| {
            if (ch < '0' or ch > '9') {
                return false;
            }
        }
        return true;
    }

    fn isAlphabeticOnly(value: []const u8) bool {
        for (value) |ch| {
            if (!((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z')))
            {
                return false;
            }
        }
        return true;
    }

    fn isAlphanumeric(value: []const u8) bool {
        for (value) |ch| {
            if (!((ch >= 'a' and ch <= 'z') or
                (ch >= 'A' and ch <= 'Z') or
                (ch >= '0' and ch <= '9')))
            {
                return false;
            }
        }
        return true;
    }

    fn isValidDateMMDDYY(value: []const u8) bool {
        if (value.len != 6) return false;
        const mm = std.fmt.parseInt(u32, value[0..2], 10) catch return false;
        const dd = std.fmt.parseInt(u32, value[2..4], 10) catch return false;
        _ = std.fmt.parseInt(u32, value[4..6], 10) catch return false;
        return mm >= 1 and mm <= 12 and dd >= 1 and dd <= 31;
    }

    fn isValidDateDDMMYY(value: []const u8) bool {
        if (value.len != 6) return false;
        const dd = std.fmt.parseInt(u32, value[0..2], 10) catch return false;
        const mm = std.fmt.parseInt(u32, value[2..4], 10) catch return false;
        _ = std.fmt.parseInt(u32, value[4..6], 10) catch return false;
        return mm >= 1 and mm <= 12 and dd >= 1 and dd <= 31;
    }

    fn isValidDateYYYYMMDD(value: []const u8) bool {
        if (value.len != 8) return false;
        _ = std.fmt.parseInt(u32, value[0..4], 10) catch return false;
        const mm = std.fmt.parseInt(u32, value[4..6], 10) catch return false;
        const dd = std.fmt.parseInt(u32, value[6..8], 10) catch return false;
        return mm >= 1 and mm <= 12 and dd >= 1 and dd <= 31;
    }

    fn isValidTimeHHMMSS(value: []const u8) bool {
        if (value.len != 6) return false;
        const hh = std.fmt.parseInt(u32, value[0..2], 10) catch return false;
        const mm = std.fmt.parseInt(u32, value[2..4], 10) catch return false;
        const ss = std.fmt.parseInt(u32, value[4..6], 10) catch return false;
        return hh < 24 and mm < 60 and ss < 60;
    }

    fn isValidPhoneNumber(value: []const u8) bool {
        var digit_count: u32 = 0;
        for (value) |ch| {
            if (ch >= '0' and ch <= '9') {
                digit_count += 1;
            } else if (ch != '-' and ch != '(' and ch != ')' and ch != ' ') {
                return false;
            }
        }
        return digit_count >= 10; // At least 10 digits
    }

    fn isValidCreditCard(value: []const u8) bool {
        if (value.len < 13 or value.len > 19) return false;

        var digit_count: u32 = 0;
        for (value) |ch| {
            if (ch >= '0' and ch <= '9') {
                digit_count += 1;
            } else if (ch != '-' and ch != ' ') {
                return false;
            }
        }

        return digit_count >= 13; // Minimum card number length
    }
};

/// Extended field type support
pub const FieldType = enum {
    alphanumeric,
    numeric,
    alphabetic,
    date,
    time,
    phone_number,
    credit_card,
    email,
    url,
    currency,
    percentage,
    custom,
};

/// Detect field type from attribute patterns
pub fn detectFieldType(attribute: protocol.FieldAttribute, sample_data: []const u8) FieldType {
    // If numeric attribute set, likely numeric field
    if (attribute.numeric) {
        return .numeric;
    }

    // Analyze sample data
    if (sample_data.len > 0) {
        if (isLikelyPhoneNumber(sample_data)) {
            return .phone_number;
        }
        if (isLikelyDate(sample_data)) {
            return .date;
        }
        if (isLikelyEmail(sample_data)) {
            return .email;
        }
    }

    return .alphanumeric;
}

fn isLikelyPhoneNumber(data: []const u8) bool {
    var digit_count: u32 = 0;
    for (data) |ch| {
        if (ch >= '0' and ch <= '9') {
            digit_count += 1;
        }
    }
    return digit_count >= 10;
}

fn isLikelyDate(data: []const u8) bool {
    if (data.len < 6) return false;
    var slash_count: u32 = 0;
    for (data) |ch| {
        if (ch == '/') slash_count += 1;
    }
    return slash_count >= 2;
}

fn isLikelyEmail(data: []const u8) bool {
    var at_count: u32 = 0;
    for (data) |ch| {
        if (ch == '@') at_count += 1;
    }
    return at_count == 1;
}

// Tests
test "field validation: numeric only" {
    var constraint = FieldValidation.Constraint{
        .rule = .numeric_only,
        .min_length = 1,
    };
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(try FieldValidation.validate(std.testing.allocator, "12345", constraint));
    try std.testing.expect(!try FieldValidation.validate(std.testing.allocator, "123A5", constraint));
}

test "field validation: alphabetic only" {
    var constraint = FieldValidation.Constraint{
        .rule = .alphabetic_only,
        .min_length = 1,
    };
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(try FieldValidation.validate(std.testing.allocator, "ABCDE", constraint));
    try std.testing.expect(!try FieldValidation.validate(std.testing.allocator, "ABC12", constraint));
}

test "field validation: date mmddyy" {
    var constraint = FieldValidation.Constraint{
        .rule = .date_mmddyy,
        .min_length = 6,
        .max_length = 6,
    };
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(try FieldValidation.validate(std.testing.allocator, "123124", constraint));
    try std.testing.expect(!try FieldValidation.validate(std.testing.allocator, "135124", constraint)); // Invalid month
}

test "field validation: time hhmmss" {
    var constraint = FieldValidation.Constraint{
        .rule = .time_hhmmss,
        .min_length = 6,
        .max_length = 6,
    };
    defer constraint.deinit(std.testing.allocator);

    try std.testing.expect(try FieldValidation.validate(std.testing.allocator, "123045", constraint));
    try std.testing.expect(!try FieldValidation.validate(std.testing.allocator, "250000", constraint)); // Invalid hour
}

test "field validation: error message" {
    var constraint = FieldValidation.Constraint{
        .rule = .numeric_only,
        .min_length = 5,
    };
    defer constraint.deinit(std.testing.allocator);

    const msg = try FieldValidation.errorMessage(std.testing.allocator, "123", constraint);
    defer std.testing.allocator.free(msg);

    try std.testing.expect(msg.len > 0);
}

test "field type detection: phone number" {
    const attr = protocol.FieldAttribute{};
    const detected = detectFieldType(attr, "555-123-4567");
    try std.testing.expectEqual(FieldType.phone_number, detected);
}

test "field type detection: date" {
    const attr = protocol.FieldAttribute{};
    const detected = detectFieldType(attr, "12/31/24");
    try std.testing.expectEqual(FieldType.date, detected);
}
