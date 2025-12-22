const std = @import("std");

/// Debug logging module for protocol interaction tracing
/// Configurable per-module logging levels and output targets
pub const DebugLog = struct {
    /// Log level for filtering messages
    pub const Level = enum(u3) {
        disabled = 0,
        err = 1,
        warn = 2,
        info = 3,
        dbg = 4,
        trace = 5,

        pub fn as_string(self: Level) []const u8 {
            return switch (self) {
                .disabled => "DISABLED",
                .err => "ERROR",
                .warn => "WARN",
                .info => "INFO",
                .dbg => "DEBUG",
                .trace => "TRACE",
            };
        }
    };

    /// Module categories for selective logging
    pub const Module = enum {
        parser,
        protocol,
        command,
        executor,
        field,
        screen,
        terminal,
        network,
        data_entry,
        ebcdic,

        pub fn as_string(self: Module) []const u8 {
            return switch (self) {
                .parser => "parser",
                .protocol => "protocol",
                .command => "command",
                .executor => "executor",
                .field => "field",
                .screen => "screen",
                .terminal => "terminal",
                .network => "network",
                .data_entry => "data_entry",
                .ebcdic => "ebcdic",
            };
        }
    };

    /// Output format for logs
    pub const Format = enum {
        text,
        json,

        pub fn as_string(self: Format) []const u8 {
            return switch (self) {
                .text => "text",
                .json => "json",
            };
        }
    };

    /// Logger configuration
    pub const Config = struct {
        global_level: Level = .disabled,
        module_levels: std.EnumMap(Module, Level) = .{},
        format: Format = .text,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Config {
            return Config{
                .allocator = allocator,
                .module_levels = std.EnumMap(Module, Level){},
                .format = .text,
            };
        }

        pub fn init_from_env(allocator: std.mem.Allocator) Config {
            var config = Config.init(allocator);

            // Read ZIG_3270_LOG_LEVEL environment variable
            if (std.posix.getenv("ZIG_3270_LOG_LEVEL")) |level_str| {
                if (std.mem.eql(u8, level_str, "disabled")) {
                    config.global_level = .disabled;
                } else if (std.mem.eql(u8, level_str, "error")) {
                    config.global_level = .err;
                } else if (std.mem.eql(u8, level_str, "warn")) {
                    config.global_level = .warn;
                } else if (std.mem.eql(u8, level_str, "info")) {
                    config.global_level = .info;
                } else if (std.mem.eql(u8, level_str, "debug")) {
                    config.global_level = .dbg;
                } else if (std.mem.eql(u8, level_str, "trace")) {
                    config.global_level = .trace;
                }
            }

            // Read ZIG_3270_LOG_FORMAT environment variable
            if (std.posix.getenv("ZIG_3270_LOG_FORMAT")) |format_str| {
                if (std.mem.eql(u8, format_str, "json")) {
                    config.format = .json;
                } else {
                    config.format = .text;
                }
            }

            return config;
        }

        pub fn set_global_level(self: *Config, level: Level) void {
            self.global_level = level;
        }

        pub fn set_module_level(self: *Config, module: Module, level: Level) void {
            self.module_levels.put(module, level);
        }

        pub fn set_format(self: *Config, format: Format) void {
            self.format = format;
        }

        pub fn get_level(self: Config, module: Module) Level {
            if (self.module_levels.get(module)) |level| {
                return level;
            }
            return self.global_level;
        }
    };

    /// Central logger instance (thread-local in production)
    var logger_config: ?Config = null;

    /// Initialize logger with configuration
    pub fn init(allocator: std.mem.Allocator) void {
        logger_config = Config.init(allocator);
    }

    /// Set global logging level
    pub fn set_level(level: Level) void {
        if (logger_config) |*config| {
            config.set_global_level(level);
        }
    }

    /// Set logging level for specific module
    pub fn set_module_level(module: Module, level: Level) void {
        if (logger_config) |*config| {
            config.set_module_level(module, level);
        }
    }

    /// Check if logging is enabled for module and level
    pub fn is_enabled(module: Module, level: Level) bool {
        if (logger_config) |config| {
            const enabled_level = config.get_level(module);
            return @intFromEnum(level) <= @intFromEnum(enabled_level);
        }
        return false;
    }

    /// Log error message
    pub fn error_log(module: Module, comptime fmt: []const u8, args: anytype) void {
        log_impl(.err, module, fmt, args);
    }

    /// Log warning message
    pub fn warn(module: Module, comptime fmt: []const u8, args: anytype) void {
        log_impl(.warn, module, fmt, args);
    }

    /// Log info message
    pub fn info(module: Module, comptime fmt: []const u8, args: anytype) void {
        log_impl(.info, module, fmt, args);
    }

    /// Log debug message
    pub fn debug_log(module: Module, comptime fmt: []const u8, args: anytype) void {
        log_impl(.dbg, module, fmt, args);
    }

    /// Log trace message (most detailed)
    pub fn trace(module: Module, comptime fmt: []const u8, args: anytype) void {
        log_impl(.trace, module, fmt, args);
    }

    /// Internal logging implementation
    fn log_impl(level: Level, module: Module, comptime fmt: []const u8, args: anytype) void {
        if (!is_enabled(module, level)) {
            return;
        }

        const stderr = std.io.getStdErr();
        var writer = stderr.writer();
        const now = std.time.milliTimestamp();

        if (logger_config) |config| {
            switch (config.format) {
                .json => {
                    // JSON format: {"timestamp":"ms","level":"LEVEL","module":"module","message":"..."}
                    _ = writer.print("{{\"timestamp\":{d},\"level\":\"{s}\",\"module\":\"{s}\",\"message\":\"", .{
                        now, level.as_string(), module.as_string(),
                    }) catch return;
                    _ = writer.print(fmt, args) catch return;
                    _ = writer.print("\"}}\n", .{}) catch return;
                },
                .text => {
                    // Text format: [TIME] LEVEL module: message
                    _ = writer.print("[{d:0>6}ms] {s:6s} {s:12s}: ", .{
                        now % 1000000, // Keep last 6 digits
                        level.as_string(),
                        module.as_string(),
                    }) catch return;
                    _ = writer.print(fmt, args) catch return;
                    _ = writer.print("\n", .{}) catch return;
                },
            }
        } else {
            // Fallback: basic text format when config not initialized
            _ = writer.print("[{d:0>6}ms] {s:6s} {s:12s}: ", .{
                now % 1000000,
                level.as_string(),
                module.as_string(),
            }) catch return;
            _ = writer.print(fmt, args) catch return;
            _ = writer.print("\n", .{}) catch return;
        }
    }
};

// === Tests ===

test "debug log level string representation" {
    try std.testing.expectEqualStrings("ERROR", DebugLog.Level.err.as_string());
    try std.testing.expectEqualStrings("WARN", DebugLog.Level.warn.as_string());
    try std.testing.expectEqualStrings("INFO", DebugLog.Level.info.as_string());
    try std.testing.expectEqualStrings("DEBUG", DebugLog.Level.dbg.as_string());
    try std.testing.expectEqualStrings("TRACE", DebugLog.Level.trace.as_string());
    try std.testing.expectEqualStrings("DISABLED", DebugLog.Level.disabled.as_string());
}

test "debug log module string representation" {
    try std.testing.expectEqualStrings("parser", DebugLog.Module.parser.as_string());
    try std.testing.expectEqualStrings("protocol", DebugLog.Module.protocol.as_string());
    try std.testing.expectEqualStrings("command", DebugLog.Module.command.as_string());
    try std.testing.expectEqualStrings("executor", DebugLog.Module.executor.as_string());
    try std.testing.expectEqualStrings("ebcdic", DebugLog.Module.ebcdic.as_string());
}

test "debug log config initialization" {
    const config = DebugLog.Config.init(std.testing.allocator);
    try std.testing.expectEqual(DebugLog.Level.disabled, config.global_level);
}

test "debug log config set and get level" {
    var config = DebugLog.Config.init(std.testing.allocator);
    config.set_global_level(.dbg);
    try std.testing.expectEqual(DebugLog.Level.dbg, config.get_level(.parser));
}

test "debug log config module specific levels" {
    var config = DebugLog.Config.init(std.testing.allocator);
    config.set_global_level(.warn);
    config.set_module_level(.parser, .trace);

    try std.testing.expectEqual(DebugLog.Level.trace, config.get_level(.parser));
    try std.testing.expectEqual(DebugLog.Level.warn, config.get_level(.protocol));
}

test "debug log is_enabled checks global level" {
    DebugLog.logger_config = DebugLog.Config.init(std.testing.allocator);
    defer if (DebugLog.logger_config) |*cfg| {
        _ = cfg;
    };

    DebugLog.set_level(.info);
    try std.testing.expect(DebugLog.is_enabled(.parser, .err));
    try std.testing.expect(DebugLog.is_enabled(.parser, .warn));
    try std.testing.expect(DebugLog.is_enabled(.parser, .info));
    try std.testing.expect(!DebugLog.is_enabled(.parser, .dbg));
    try std.testing.expect(!DebugLog.is_enabled(.parser, .trace));
}

test "debug log is_enabled checks module level" {
    DebugLog.logger_config = DebugLog.Config.init(std.testing.allocator);
    defer if (DebugLog.logger_config) |*cfg| {
        _ = cfg;
    };

    DebugLog.set_level(.warn);
    DebugLog.set_module_level(.parser, .trace);

    try std.testing.expect(DebugLog.is_enabled(.parser, .trace));
    try std.testing.expect(DebugLog.is_enabled(.protocol, .warn));
    try std.testing.expect(!DebugLog.is_enabled(.protocol, .dbg));
}

test "debug log level ordering" {
    try std.testing.expect(@intFromEnum(DebugLog.Level.disabled) < @intFromEnum(DebugLog.Level.err));
    try std.testing.expect(@intFromEnum(DebugLog.Level.err) < @intFromEnum(DebugLog.Level.warn));
    try std.testing.expect(@intFromEnum(DebugLog.Level.warn) < @intFromEnum(DebugLog.Level.info));
    try std.testing.expect(@intFromEnum(DebugLog.Level.info) < @intFromEnum(DebugLog.Level.dbg));
    try std.testing.expect(@intFromEnum(DebugLog.Level.dbg) < @intFromEnum(DebugLog.Level.trace));
}

test "debug log logging disabled by default" {
    DebugLog.logger_config = null;
    defer DebugLog.logger_config = null;

    try std.testing.expect(!DebugLog.is_enabled(.parser, .err));
    try std.testing.expect(!DebugLog.is_enabled(.parser, .info));
}

test "debug log format enum representation" {
    try std.testing.expectEqualStrings("text", DebugLog.Format.text.as_string());
    try std.testing.expectEqualStrings("json", DebugLog.Format.json.as_string());
}

test "debug log config set format" {
    var config = DebugLog.Config.init(std.testing.allocator);
    try std.testing.expectEqual(DebugLog.Format.text, config.format);
    config.set_format(.json);
    try std.testing.expectEqual(DebugLog.Format.json, config.format);
}

test "debug log JSON output format" {
    DebugLog.logger_config = DebugLog.Config.init(std.testing.allocator);
    defer if (DebugLog.logger_config) |*cfg| {
        _ = cfg;
    };

    DebugLog.set_level(.info);
    if (DebugLog.logger_config) |*config| {
        config.set_format(.json);
    }

    // This test just verifies the configuration is set, actual output would be stderr
    if (DebugLog.logger_config) |config| {
        try std.testing.expectEqual(DebugLog.Format.json, config.format);
    }
}
