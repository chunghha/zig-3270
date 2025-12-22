const std = @import("std");
const protocol = @import("protocol.zig");

/// 3270 command buffer parsing
pub const Parser = struct {
    allocator: std.mem.Allocator,
    buffer: []u8,
    position: usize,

    /// Initialize parser with a buffer
    pub fn init(allocator: std.mem.Allocator, buffer: []u8) Parser {
        return Parser{
            .allocator = allocator,
            .buffer = buffer,
            .position = 0,
        };
    }

    /// Peek next byte without advancing position
    pub fn peek(self: *Parser) !u8 {
        if (self.position >= self.buffer.len) {
            return error.EndOfBuffer;
        }
        return self.buffer[self.position];
    }

    /// Read next byte and advance position
    pub fn read(self: *Parser) !u8 {
        const byte = try self.peek();
        self.position += 1;
        return byte;
    }

    /// Read N bytes into a buffer
    pub fn read_bytes(self: *Parser, n: usize) ![]u8 {
        if (self.position + n > self.buffer.len) {
            return error.EndOfBuffer;
        }
        const result = self.buffer[self.position .. self.position + n];
        self.position += n;
        return result;
    }

    /// Reset parser position
    pub fn reset(self: *Parser) void {
        self.position = 0;
    }

    /// Check if there are more bytes to read
    pub fn has_more(self: *Parser) bool {
        return self.position < self.buffer.len;
    }
};

test "parser initialization" {
    var buffer: [10]u8 = undefined;
    const parser = Parser.init(std.testing.allocator, &buffer);
    try std.testing.expectEqual(@as(usize, 0), parser.position);
}

test "parser peek and read" {
    var buffer: [3]u8 = .{ 0x05, 0x11, 0x42 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    const peeked = try parser.peek();
    try std.testing.expectEqual(@as(u8, 0x05), peeked);
    try std.testing.expectEqual(@as(usize, 0), parser.position);

    const read_byte = try parser.read();
    try std.testing.expectEqual(@as(u8, 0x05), read_byte);
    try std.testing.expectEqual(@as(usize, 1), parser.position);
}

test "parser read bytes" {
    var buffer: [5]u8 = .{ 0x01, 0x02, 0x03, 0x04, 0x05 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    const bytes = try parser.read_bytes(3);
    try std.testing.expectEqual(@as(usize, 3), bytes.len);
    try std.testing.expectEqual(@as(usize, 3), parser.position);
}

/// Error recovery for malformed or corrupted data streams
pub const ErrorRecovery = struct {
    allocator: std.mem.Allocator,
    recovery_mode: RecoveryMode = .lenient,
    error_count: u32 = 0,
    recovery_count: u32 = 0,

    pub const RecoveryMode = enum {
        strict, // Fail immediately on error
        lenient, // Skip bad data and continue
        auto_correct, // Attempt to fix known issues
    };

    /// Error recovery result
    pub const RecoveryResult = struct {
        success: bool,
        bytes_skipped: usize = 0,
        error_message: ?[]const u8 = null,
        recovery_method: ?[]const u8 = null,
    };

    pub fn init(allocator: std.mem.Allocator) ErrorRecovery {
        return .{
            .allocator = allocator,
            .recovery_mode = .lenient,
        };
    }

    /// Detect frame boundary in corrupted stream
    /// Looks for known command codes or frame markers
    pub fn find_frame_boundary(buffer: []const u8, start_pos: usize) !?usize {
        if (start_pos >= buffer.len) return null;

        const known_commands = [_]u8{ 0xF1, 0xF5, 0xF3, 0x6B, 0xE0 };

        for (start_pos + 1..buffer.len) |i| {
            for (known_commands) |cmd| {
                if (buffer[i] == cmd) {
                    return i;
                }
            }
        }

        return null;
    }

    /// Validate frame format
    /// Returns true if frame looks valid, false if corruption detected
    pub fn validate_frame(frame: []const u8) bool {
        if (frame.len < 2) return false;

        const command_code = frame[0];

        // Check if command code is valid
        const valid_codes = [_]u8{ 0xF1, 0xF5, 0xF3, 0x6B, 0xE0 };
        var is_valid = false;
        for (valid_codes) |code| {
            if (command_code == code) {
                is_valid = true;
                break;
            }
        }

        if (!is_valid) {
            return false;
        }

        // Check basic size constraints
        if (command_code == 0x6B and frame.len < 3) {
            return false;
        }

        return true;
    }

    /// Attempt recovery from corrupted data
    pub fn recover_from_corruption(self: *ErrorRecovery, buffer: []const u8) !RecoveryResult {
        var result = RecoveryResult{ .success = false };

        // Try to find next valid frame boundary
        if (try find_frame_boundary(buffer, 0)) |boundary| {
            result.bytes_skipped = boundary;
            result.success = true;
            result.recovery_method = try self.allocator.dupe(u8, "frame_boundary_resync");
            self.recovery_count += 1;
            return result;
        }

        // If we can't find a boundary, report detailed error
        result.error_message = try self.allocator.dupe(u8, "Unable to locate frame boundary");
        self.error_count += 1;
        return result;
    }

    /// Get recovery statistics
    pub fn get_stats(self: ErrorRecovery) struct {
        total_errors: u32,
        total_recoveries: u32,
        recovery_rate: f64,
    } {
        const total = self.error_count + self.recovery_count;
        const rate: f64 = if (total > 0)
            @as(f64, @floatFromInt(self.recovery_count)) / @as(f64, @floatFromInt(total))
        else
            0.0;

        return .{
            .total_errors = self.error_count,
            .total_recoveries = self.recovery_count,
            .recovery_rate = rate,
        };
    }

    /// Reset error counters
    pub fn reset_stats(self: *ErrorRecovery) void {
        self.error_count = 0;
        self.recovery_count = 0;
    }
};

/// Fuzzing framework for protocol robustness testing
pub const FuzzTester = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    test_count: u64 = 0,
    crash_count: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, seed: u64) FuzzTester {
        return .{
            .allocator = allocator,
            .seed = seed,
        };
    }

    /// Fuzz command codes
    pub fn fuzz_command_codes(self: *FuzzTester, iterations: u32) !u64 {
        const error_count: u64 = 0;

        for (0..iterations) |_| {
            // Simulate fuzzing by incrementing test count
            self.test_count += 1;

            // A real fuzzer would execute parser here and track crashes
        }

        return error_count;
    }

    /// Fuzz data streams
    pub fn fuzz_data_streams(self: *FuzzTester, iterations: u32) !u64 {
        const error_count: u64 = 0;

        var buffer: [256]u8 = undefined;
        for (0..iterations) |i| {
            // Fill buffer with pseudo-random data
            buffer[i % buffer.len] = @intCast((self.seed ^ @as(u64, @intCast(i))) & 0xFF);

            // A real fuzzer would parse this and check for crashes
            self.test_count += 1;
        }

        return error_count;
    }

    /// Get fuzzing statistics
    pub fn get_stats(self: FuzzTester) struct {
        tests_run: u64,
        crashes_found: u64,
        crash_rate: f64,
    } {
        const rate: f64 = if (self.test_count > 0)
            @as(f64, @floatFromInt(self.crash_count)) / @as(f64, @floatFromInt(self.test_count))
        else
            0.0;

        return .{
            .tests_run = self.test_count,
            .crashes_found = self.crash_count,
            .crash_rate = rate,
        };
    }
};

// Tests for error recovery
test "error_recovery: init creates recovery" {
    const recovery = ErrorRecovery.init(std.testing.allocator);
    try std.testing.expect(recovery.error_count == 0);
    try std.testing.expect(recovery.recovery_count == 0);
}

test "error_recovery: validate valid frame" {
    const frame = [_]u8{ 0xF1, 0x00 };
    try std.testing.expect(ErrorRecovery.validate_frame(&frame));
}

test "error_recovery: reject invalid frame" {
    const frame = [_]u8{ 0xFF, 0x00 };
    try std.testing.expect(!ErrorRecovery.validate_frame(&frame));
}

test "error_recovery: find frame boundary" {
    const buffer = [_]u8{ 0xFF, 0xFF, 0xF1, 0x00 };
    const boundary = try ErrorRecovery.find_frame_boundary(&buffer, 0);
    try std.testing.expectEqual(boundary, 2);
}

test "error_recovery: recover from corruption" {
    const recovery = ErrorRecovery.init(std.testing.allocator);

    const buffer = [_]u8{ 0xFF, 0xFF, 0xF1, 0x00 };
    var mut_recovery = recovery;
    const result = try mut_recovery.recover_from_corruption(&buffer);

    try std.testing.expect(result.success);
    try std.testing.expectEqual(result.bytes_skipped, 2);
    if (result.recovery_method) |method| {
        recovery.allocator.free(method);
    }
}

test "error_recovery: get stats" {
    var recovery = ErrorRecovery.init(std.testing.allocator);
    recovery.error_count = 10;
    recovery.recovery_count = 8;

    const stats = recovery.get_stats();
    try std.testing.expectEqual(stats.total_errors, 10);
    try std.testing.expectEqual(stats.total_recoveries, 8);
    try std.testing.expect(stats.recovery_rate > 0.4 and stats.recovery_rate < 0.5);
}

test "fuzz_tester: init creates tester" {
    const fuzz = FuzzTester.init(std.testing.allocator, 12345);
    try std.testing.expectEqual(fuzz.seed, 12345);
    try std.testing.expectEqual(fuzz.test_count, 0);
}

test "fuzz_tester: fuzz command codes" {
    var fuzz = FuzzTester.init(std.testing.allocator, 12345);
    _ = try fuzz.fuzz_command_codes(100);
    try std.testing.expectEqual(fuzz.test_count, 100);
}

test "fuzz_tester: fuzz data streams" {
    var fuzz = FuzzTester.init(std.testing.allocator, 12345);
    _ = try fuzz.fuzz_data_streams(50);
    try std.testing.expectEqual(fuzz.test_count, 50);
}

test "fuzz_tester: get stats" {
    var fuzz = FuzzTester.init(std.testing.allocator, 12345);
    fuzz.test_count = 1000;
    fuzz.crash_count = 5;

    const stats = fuzz.get_stats();
    try std.testing.expectEqual(stats.tests_run, 1000);
    try std.testing.expectEqual(stats.crashes_found, 5);
    try std.testing.expect(stats.crash_rate > 0.004 and stats.crash_rate < 0.006);
}

test "parser end of buffer" {
    var buffer: [2]u8 = .{ 0x01, 0x02 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    _ = try parser.read();
    _ = try parser.read();
    const result = parser.peek();
    try std.testing.expectError(error.EndOfBuffer, result);
}

test "parser has_more" {
    var buffer: [2]u8 = .{ 0x01, 0x02 };
    var parser = Parser.init(std.testing.allocator, &buffer);

    try std.testing.expect(parser.has_more());
    _ = try parser.read();
    try std.testing.expect(parser.has_more());
    _ = try parser.read();
    try std.testing.expect(!parser.has_more());
}

test "parser reset" {
    var buffer: [3]u8 = undefined;
    var parser = Parser.init(std.testing.allocator, &buffer);
    parser.position = 2;
    parser.reset();
    try std.testing.expectEqual(@as(usize, 0), parser.position);
}
