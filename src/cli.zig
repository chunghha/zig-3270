const std = @import("std");
const debug_log = @import("debug_log.zig");

pub const CliCommand = enum {
    connect,
    replay,
    dump,
    help,
    version,
};

pub const CliArgs = struct {
    command: CliCommand = .help,
    host: []const u8 = "localhost",
    port: u16 = 23,
    profile: ?[]const u8 = null,
    timeout: u32 = 5000,
    verbose: bool = false,
    log_level: debug_log.DebugLog.Level = .warn,
    file: ?[]const u8 = null, // for replay/dump commands
};

pub const CliParser = struct {
    pub fn init(_: std.mem.Allocator) CliParser {
        return .{};
    }

    pub fn parse(_: CliParser, args: []const []const u8) !CliArgs {
        var result = CliArgs{};

        if (args.len == 0) {
            return result;
        }

        var i: usize = 1; // Skip program name
        while (i < args.len) : (i += 1) {
            const arg = args[i];

            if (std.mem.eql(u8, arg, "connect")) {
                result.command = .connect;
            } else if (std.mem.eql(u8, arg, "replay")) {
                result.command = .replay;
            } else if (std.mem.eql(u8, arg, "dump")) {
                result.command = .dump;
            } else if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                result.command = .help;
            } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
                result.command = .version;
            } else if (std.mem.eql(u8, arg, "--host")) {
                i += 1;
                if (i >= args.len) return error.MissingHostValue;
                result.host = args[i];
            } else if (std.mem.eql(u8, arg, "--port")) {
                i += 1;
                if (i >= args.len) return error.MissingPortValue;
                const port_str = args[i];
                result.port = std.fmt.parseInt(u16, port_str, 10) catch return error.InvalidPort;
                if (result.port == 0) return error.InvalidPort;
            } else if (std.mem.eql(u8, arg, "--profile")) {
                i += 1;
                if (i >= args.len) return error.MissingProfileValue;
                result.profile = args[i];
            } else if (std.mem.eql(u8, arg, "--timeout")) {
                i += 1;
                if (i >= args.len) return error.MissingTimeoutValue;
                const timeout_str = args[i];
                result.timeout = std.fmt.parseInt(u32, timeout_str, 10) catch return error.InvalidTimeout;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                result.verbose = true;
                result.log_level = .dbg;
            } else if (std.mem.eql(u8, arg, "--debug")) {
                result.verbose = true;
                result.log_level = .trace;
            } else if (std.mem.eql(u8, arg, "--file")) {
                i += 1;
                if (i >= args.len) return error.MissingFileValue;
                result.file = args[i];
            } else {
                return error.UnknownArgument;
            }
        }

        return result;
    }

    pub fn print_help() void {
        const help_text =
            \\zig-3270: TN3270 Terminal Emulator
            \\
            \\USAGE:
            \\    zig-3270 [COMMAND] [OPTIONS]
            \\
            \\COMMANDS:
            \\    connect         Connect to a mainframe (default)
            \\    replay <file>   Replay a recorded session
            \\    dump <file>     Dump session data
            \\    help            Show this help message
            \\    version         Show version information
            \\
            \\OPTIONS:
            \\    --host <HOST>       Target host (default: localhost)
            \\    --port <PORT>       Target port (default: 23)
            \\    --profile <NAME>    Load connection profile
            \\    --timeout <MS>      Connection timeout in ms (default: 5000)
            \\    --verbose           Enable verbose logging
            \\    --debug             Enable debug logging
            \\    --file <PATH>       File for replay/dump commands
            \\    -h, --help          Show this help message
            \\    -v, --version       Show version information
            \\
            \\EXAMPLES:
            \\    zig-3270 connect --host mvs38j.com --port 23
            \\    zig-3270 --profile tso
            \\    zig-3270 replay --file session.bin
            \\
        ;
        std.debug.print("{s}", .{help_text});
    }

    pub fn print_version() void {
        std.debug.print("zig-3270 v0.6.0\n", .{});
    }
};

// Tests
test "parse connect command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "connect" };
    const result = try parser.parse(&args);

    try std.testing.expectEqual(CliCommand.connect, result.command);
    try std.testing.expectEqualSlices(u8, "localhost", result.host);
    try std.testing.expectEqual(@as(u16, 23), result.port);
}

test "parse connect with host and port" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "connect", "--host", "mvs38j.com", "--port", "23" };
    const result = try parser.parse(&args);

    try std.testing.expectEqual(CliCommand.connect, result.command);
    try std.testing.expectEqualSlices(u8, "mvs38j.com", result.host);
    try std.testing.expectEqual(@as(u16, 23), result.port);
}

test "parse help command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "help" };
    const result = try parser.parse(&args);

    try std.testing.expectEqual(CliCommand.help, result.command);
}

test "parse version command" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--version" };
    const result = try parser.parse(&args);

    try std.testing.expectEqual(CliCommand.version, result.command);
}

test "parse verbose flag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--verbose" };
    const result = try parser.parse(&args);

    try std.testing.expect(result.verbose);
    try std.testing.expectEqual(debug_log.DebugLog.Level.dbg, result.log_level);
}

test "parse debug flag" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--debug" };
    const result = try parser.parse(&args);

    try std.testing.expect(result.verbose);
    try std.testing.expectEqual(debug_log.DebugLog.Level.trace, result.log_level);
}

test "parse profile argument" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--profile", "tso" };
    const result = try parser.parse(&args);

    try std.testing.expect(result.profile != null);
    try std.testing.expectEqualSlices(u8, "tso", result.profile.?);
}

test "invalid port number rejected" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--port", "65536" };
    const result = parser.parse(&args);

    try std.testing.expectError(error.InvalidPort, result);
}

test "zero port rejected" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--port", "0" };
    const result = parser.parse(&args);

    try std.testing.expectError(error.InvalidPort, result);
}

test "unknown argument error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const parser = CliParser.init(allocator);
    const args = [_][]const u8{ "zig-3270", "--unknown-flag" };
    const result = parser.parse(&args);

    try std.testing.expectError(error.UnknownArgument, result);
}
