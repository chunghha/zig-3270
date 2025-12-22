const std = @import("std");
const error_context = @import("error_context.zig");

/// Configuration validation module
/// Validates configuration parameters at startup with helpful feedback
pub const ConfigValidator = struct {
    allocator: std.mem.Allocator,
    errors: std.ArrayList(ValidationError),

    pub const ValidationError = struct {
        code: error_context.ErrorContext.ErrorCode,
        field: []const u8,
        value: ?[]const u8 = null,
        message: []const u8,
        recovery: []const u8,
    };

    pub const Config = struct {
        host: ?[]const u8 = null,
        port: ?u16 = null,
        connect_timeout_ms: u32 = 10000,
        read_timeout_ms: u32 = 5000,
        write_timeout_ms: u32 = 5000,
        max_retries: u8 = 3,
        log_level: []const u8 = "disabled",
        log_format: []const u8 = "text",
    };

    pub fn init(allocator: std.mem.Allocator) ConfigValidator {
        return ConfigValidator{
            .allocator = allocator,
            .errors = std.ArrayList(ValidationError).init(allocator),
        };
    }

    pub fn deinit(self: *ConfigValidator) void {
        self.errors.deinit();
    }

    /// Validate entire configuration
    pub fn validate(self: *ConfigValidator, config: Config) !bool {
        self.errors.clearRetainingCapacity();

        try self.validate_host(config.host);
        try self.validate_port(config.port);
        try self.validate_timeouts(config.connect_timeout_ms, config.read_timeout_ms, config.write_timeout_ms);
        try self.validate_retries(config.max_retries);
        try self.validate_log_level(config.log_level);
        try self.validate_log_format(config.log_format);

        return self.errors.items.len == 0;
    }

    /// Validate host configuration
    fn validate_host(self: *ConfigValidator, host: ?[]const u8) !void {
        if (host == null) {
            // Host is optional
            return;
        }

        const h = host.?;
        if (h.len == 0) {
            try self.add_error(.config_invalid_value, "host", h, "Empty host address", "Provide valid FQDN or IP address");
            return;
        }

        // Check for invalid characters
        for (h) |c| {
            if (!is_valid_host_char(c)) {
                try self.add_error(.config_invalid_value, "host", h, "Invalid characters in host", "Use alphanumeric, dots, hyphens, and underscores");
                return;
            }
        }

        // Check length
        if (h.len > 255) {
            try self.add_error(.config_invalid_value, "host", h, "Host name too long (> 255 chars)", "Shorten hostname");
        }
    }

    /// Validate port configuration
    fn validate_port(self: *ConfigValidator, port: ?u16) !void {
        if (port == null) {
            // Port is optional
            return;
        }

        const p = port.?;
        if (p == 0) {
            try self.add_error(.config_invalid_value, "port", null, "Port cannot be 0", "Use valid port 1-65535");
            return;
        }

        if (p < 1024) {
            try self.add_error(.config_invalid_value, "port", null, "Port below 1024 (privileged)", "Use unprivileged port or run with elevated privileges");
        }

        // Note: 3270 is the standard TN3270 port
        if (p != 3270 and p != 23) {
            // Not a standard port, but not an error
        }
    }

    /// Validate timeout configurations
    fn validate_timeouts(
        self: *ConfigValidator,
        connect_timeout: u32,
        read_timeout: u32,
        write_timeout: u32,
    ) !void {
        if (connect_timeout == 0) {
            try self.add_error(.config_invalid_value, "connect_timeout_ms", null, "Connect timeout must be > 0", "Set to positive milliseconds (e.g., 10000)");
        } else if (connect_timeout > 300000) {
            try self.add_error(.config_invalid_value, "connect_timeout_ms", null, "Connect timeout too large (> 5 min)", "Use reasonable timeout (e.g., 10-60 seconds)");
        }

        if (read_timeout == 0) {
            try self.add_error(.config_invalid_value, "read_timeout_ms", null, "Read timeout must be > 0", "Set to positive milliseconds (e.g., 5000)");
        } else if (read_timeout > 300000) {
            try self.add_error(.config_invalid_value, "read_timeout_ms", null, "Read timeout too large (> 5 min)", "Use reasonable timeout");
        }

        if (write_timeout == 0) {
            try self.add_error(.config_invalid_value, "write_timeout_ms", null, "Write timeout must be > 0", "Set to positive milliseconds (e.g., 5000)");
        }
    }

    /// Validate retry configuration
    fn validate_retries(self: *ConfigValidator, max_retries: u8) !void {
        if (max_retries > 100) {
            try self.add_error(.config_invalid_value, "max_retries", null, "Max retries too high (> 100)", "Use reasonable number (e.g., 3-10)");
        }
    }

    /// Validate log level
    fn validate_log_level(self: *ConfigValidator, log_level: []const u8) !void {
        const valid_levels = [_][]const u8{ "disabled", "error", "warn", "info", "debug", "trace" };

        var found = false;
        for (valid_levels) |level| {
            if (std.mem.eql(u8, log_level, level)) {
                found = true;
                break;
            }
        }

        if (!found) {
            try self.add_error(.config_invalid_value, "log_level", log_level, "Invalid log level", "Use: disabled, error, warn, info, debug, or trace");
        }
    }

    /// Validate log format
    fn validate_log_format(self: *ConfigValidator, log_format: []const u8) !void {
        const valid_formats = [_][]const u8{ "text", "json" };

        var found = false;
        for (valid_formats) |fmt| {
            if (std.mem.eql(u8, log_format, fmt)) {
                found = true;
                break;
            }
        }

        if (!found) {
            try self.add_error(.config_invalid_value, "log_format", log_format, "Invalid log format", "Use: text or json");
        }
    }

    /// Add validation error
    fn add_error(
        self: *ConfigValidator,
        code: error_context.ErrorContext.ErrorCode,
        field: []const u8,
        value: ?[]const u8,
        message: []const u8,
        recovery: []const u8,
    ) !void {
        try self.errors.append(ValidationError{
            .code = code,
            .field = field,
            .value = value,
            .message = message,
            .recovery = recovery,
        });
    }

    /// Get formatted error report
    pub fn error_report(self: *ConfigValidator, allocator: std.mem.Allocator) ![]u8 {
        var report = std.ArrayList(u8).init(allocator);
        defer report.deinit();

        var writer = report.writer();

        if (self.errors.items.len == 0) {
            try writer.writeAll("Configuration valid - no errors\n");
        } else {
            try writer.print("Configuration validation failed ({d} errors):\n\n", .{self.errors.items.len});

            for (self.errors.items, 1..) |err, i| {
                try writer.print("{d}. [{d:#x}] {s} (field: {s})\n", .{ i, err.code, err.code.description(), err.field });
                try writer.print("   Issue: {s}\n", .{err.message});
                if (err.value) |val| {
                    try writer.print("   Value: {s}\n", .{val});
                }
                try writer.print("   Recovery: {s}\n\n", .{err.recovery});
            }
        }

        return report.toOwnedSlice();
    }

    /// Check if host character is valid
    fn is_valid_host_char(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9') or
            c == '.' or c == '-' or c == '_';
    }
};

// === Tests ===

test "config validator init" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();
    try std.testing.expect(validator.errors.items.len == 0);
}

test "config validator valid configuration" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "mainframe.example.com",
        .port = 3270,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(valid);
    try std.testing.expect(validator.errors.items.len == 0);
}

test "config validator invalid host empty string" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "",
        .port = 3270,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
    try std.testing.expect(validator.errors.items.len > 0);
}

test "config validator invalid port zero" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "example.com",
        .port = 0,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}

test "config validator invalid timeout zero" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "example.com",
        .port = 3270,
        .connect_timeout_ms = 0,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}

test "config validator invalid log level" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "example.com",
        .port = 3270,
        .log_level = "invalid",
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}

test "config validator valid log levels" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const levels = [_][]const u8{ "disabled", "error", "warn", "info", "debug", "trace" };

    for (levels) |level| {
        validator.errors.clearRetainingCapacity();

        const config = ConfigValidator.Config{
            .host = "example.com",
            .port = 3270,
            .log_level = level,
        };

        const valid = try validator.validate(config);
        try std.testing.expect(valid);
    }
}

test "config validator valid log formats" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const formats = [_][]const u8{ "text", "json" };

    for (formats) |format| {
        validator.errors.clearRetainingCapacity();

        const config = ConfigValidator.Config{
            .host = "example.com",
            .port = 3270,
            .log_format = format,
        };

        const valid = try validator.validate(config);
        try std.testing.expect(valid);
    }
}

test "config validator error report" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "",
        .port = 0,
    };

    _ = try validator.validate(config);

    const report = try validator.error_report(std.testing.allocator);
    defer std.testing.allocator.free(report);

    try std.testing.expect(report.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "Configuration validation failed"));
}

test "config validator host character validation" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "valid-host_123.example.com",
        .port = 3270,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(valid);
}

test "config validator host too long" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    var long_host: [256]u8 = undefined;
    @memset(&long_host, 'a');

    const config = ConfigValidator.Config{
        .host = &long_host,
        .port = 3270,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}

test "config validator timeout too large" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "example.com",
        .port = 3270,
        .connect_timeout_ms = 600000, // > 5 min
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}

test "config validator max retries too high" {
    var validator = ConfigValidator.init(std.testing.allocator);
    defer validator.deinit();

    const config = ConfigValidator.Config{
        .host = "example.com",
        .port = 3270,
        .max_retries = 255,
    };

    const valid = try validator.validate(config);
    try std.testing.expect(!valid);
}
