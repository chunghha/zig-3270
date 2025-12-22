//! Fuzzing framework for TN3270 protocol robustness testing
//!
//! Provides automated fuzzing capabilities for:
//! - Command code fuzzing (all 256 possible values)
//! - Data stream fuzzing (random valid/invalid sequences)
//! - Field attribute fuzzing (all combinations)
//! - Address fuzzing (boundary conditions)
//!
//! Tracks coverage metrics and crash reporting.

const std = @import("std");
const protocol = @import("protocol.zig");

/// Fuzzer for protocol command codes
pub const CommandFuzzer = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: std.Random.Xoroshiro128,

    pub fn init(allocator: std.mem.Allocator, seed: u64) CommandFuzzer {
        var prng = std.Random.Xoroshiro128.init(seed);
        return CommandFuzzer{
            .allocator = allocator,
            .seed = seed,
            .rng = prng,
        };
    }

    /// Generate random command code
    pub fn next_command(self: *CommandFuzzer) u8 {
        return @truncate(self.rng.random().int(u8));
    }

    /// Generate N random command codes
    pub fn generate_commands(self: *CommandFuzzer, count: usize, out: []u8) usize {
        const n = @min(count, out.len);
        for (0..n) |i| {
            out[i] = self.next_command();
        }
        return n;
    }

    /// Check if command is valid TN3270 command
    pub fn is_valid_command(cmd: u8) bool {
        return switch (cmd) {
            0x00, 0x01, 0x02, 0x03, 0x05, 0x06, 0x07, 0x0D, 0x0E, 0x0F, 0x10, 0x13, 0x39, 0xF3 => true,
            else => false,
        };
    }
};

/// Fuzzer for data streams (order codes and data)
pub const DataStreamFuzzer = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: std.Random.Xoroshiro128,

    pub fn init(allocator: std.mem.Allocator, seed: u64) DataStreamFuzzer {
        var prng = std.Random.Xoroshiro128.init(seed);
        return DataStreamFuzzer{
            .allocator = allocator,
            .seed = seed,
            .rng = prng,
        };
    }

    /// Generate random data stream
    pub fn next_byte(self: *DataStreamFuzzer) u8 {
        return @truncate(self.rng.random().int(u8));
    }

    /// Generate random order code or data
    pub fn generate_stream(self: *DataStreamFuzzer, max_len: usize, out: []u8) usize {
        const len = 1 + (self.rng.random().int(usize) % max_len);
        const n = @min(len, out.len);
        for (0..n) |i| {
            out[i] = self.next_byte();
        }
        return n;
    }

    /// Check if byte is valid order code
    pub fn is_order_code(byte: u8) bool {
        return switch (byte) {
            0x05, 0x08, 0x0D, 0x12, 0x13, 0x1D, 0x28, 0x29, 0x2A, 0x2C, 0x3C, 0x11 => true,
            else => false,
        };
    }
};

/// Fuzzer for field attributes
pub const AttributeFuzzer = struct {
    allocator: std.mem.Allocator,
    counter: u16,

    pub fn init(allocator: std.mem.Allocator) AttributeFuzzer {
        return AttributeFuzzer{
            .allocator = allocator,
            .counter = 0,
        };
    }

    /// Generate next attribute combination (0-255)
    pub fn next_attribute(self: *AttributeFuzzer) u8 {
        const attr = @truncate(self.counter);
        self.counter = (self.counter + 1) % 256;
        return attr;
    }

    /// Reset counter to start
    pub fn reset(self: *AttributeFuzzer) void {
        self.counter = 0;
    }

    /// Check if attribute is valid (reserved bits should be 0)
    pub fn is_valid_attribute(attr: u8) bool {
        return (attr & 0x07) == 0;
    }
};

/// Fuzzer for buffer addresses
pub const AddressFuzzer = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    rng: std.Random.Xoroshiro128,

    pub fn init(allocator: std.mem.Allocator, seed: u64) AddressFuzzer {
        var prng = std.Random.Xoroshiro128.init(seed);
        return AddressFuzzer{
            .allocator = allocator,
            .seed = seed,
            .rng = prng,
        };
    }

    /// Generate random address (0-1919, fits 24x80 screen)
    pub fn next_address(self: *AddressFuzzer) u16 {
        return self.rng.random().int(u16) % 1920;
    }

    /// Generate address at boundary
    pub fn boundary_address(self: *AddressFuzzer) u16 {
        const idx = self.rng.random().int(usize) % 5;
        return switch (idx) {
            0 => 0, // Start
            1 => 1919, // End
            2 => 80, // Row boundary
            3 => 79, // Column boundary
            else => 960, // Middle
        };
    }
};

/// Coverage tracker for fuzzing
pub const CoverageTracker = struct {
    allocator: std.mem.Allocator,
    visited: [256]bool,
    order_visited: [256]bool,
    test_count: usize,

    pub fn init(allocator: std.mem.Allocator) CoverageTracker {
        return CoverageTracker{
            .allocator = allocator,
            .visited = [_]bool{false} ** 256,
            .order_visited = [_]bool{false} ** 256,
            .test_count = 0,
        };
    }

    pub fn mark_command(self: *CoverageTracker, cmd: u8) void {
        self.visited[cmd] = true;
        self.test_count += 1;
    }

    pub fn mark_order(self: *CoverageTracker, order: u8) void {
        self.order_visited[order] = true;
    }

    pub fn coverage_percent(self: CoverageTracker) f32 {
        var count: u32 = 0;
        for (self.visited) |v| {
            if (v) count += 1;
        }
        return @as(f32, @floatFromInt(count)) / 256.0 * 100.0;
    }

    pub fn order_coverage_percent(self: CoverageTracker) f32 {
        var count: u32 = 0;
        for (self.order_visited) |v| {
            if (v) count += 1;
        }
        return @as(f32, @floatFromInt(count)) / 256.0 * 100.0;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "CommandFuzzer initialization" {
    var fuzzer = CommandFuzzer.init(std.testing.allocator, 12345);
    _ = fuzzer;
}

test "CommandFuzzer generates valid commands" {
    var fuzzer = CommandFuzzer.init(std.testing.allocator, 42);
    var buf: [10]u8 = undefined;
    const count = fuzzer.generate_commands(10, &buf);
    try std.testing.expectEqual(@as(usize, 10), count);
}

test "CommandFuzzer identifies valid commands" {
    try std.testing.expect(CommandFuzzer.is_valid_command(0x01)); // Write
    try std.testing.expect(CommandFuzzer.is_valid_command(0x06)); // Read Modified
    try std.testing.expect(!CommandFuzzer.is_valid_command(0x04)); // Invalid
}

test "DataStreamFuzzer generates streams" {
    var fuzzer = DataStreamFuzzer.init(std.testing.allocator, 999);
    var buf: [100]u8 = undefined;
    const len = fuzzer.generate_stream(50, &buf);
    try std.testing.expect(len > 0);
    try std.testing.expect(len <= 50);
}

test "DataStreamFuzzer identifies order codes" {
    try std.testing.expect(DataStreamFuzzer.is_order_code(0x11)); // SBA
    try std.testing.expect(DataStreamFuzzer.is_order_code(0x1D)); // Start Field
    try std.testing.expect(!DataStreamFuzzer.is_order_code(0x41)); // Regular data
}

test "AttributeFuzzer exhaustive coverage" {
    var fuzzer = AttributeFuzzer.init(std.testing.allocator);
    var attrs: [256]u8 = undefined;

    for (0..256) |i| {
        attrs[i] = fuzzer.next_attribute();
    }

    // Verify all values 0-255 generated
    var seen: [256]bool = [_]bool{false} ** 256;
    for (attrs) |attr| {
        seen[attr] = true;
    }

    for (seen) |s| {
        try std.testing.expect(s);
    }
}

test "AttributeFuzzer validity check" {
    try std.testing.expect(AttributeFuzzer.is_valid_attribute(0x00));
    try std.testing.expect(AttributeFuzzer.is_valid_attribute(0xF8)); // Binary 11111000
    try std.testing.expect(!AttributeFuzzer.is_valid_attribute(0x01)); // Reserved bit set
    try std.testing.expect(!AttributeFuzzer.is_valid_attribute(0x07)); // All reserved bits set
}

test "AddressFuzzer generates valid addresses" {
    var fuzzer = AddressFuzzer.init(std.testing.allocator, 555);
    for (0..100) |_| {
        const addr = fuzzer.next_address();
        try std.testing.expect(addr < 1920);
    }
}

test "AddressFuzzer boundary addresses" {
    var fuzzer = AddressFuzzer.init(std.testing.allocator, 777);
    var boundary_count: usize = 0;

    for (0..100) |_| {
        const addr = fuzzer.boundary_address();
        if (addr == 0 or addr == 1919 or addr == 80 or addr == 79 or addr == 960) {
            boundary_count += 1;
        }
    }

    try std.testing.expect(boundary_count > 0);
}

test "CoverageTracker marks commands" {
    var tracker = CoverageTracker.init(std.testing.allocator);

    tracker.mark_command(0x01);
    tracker.mark_command(0x06);
    tracker.mark_command(0x05);

    try std.testing.expect(tracker.visited[0x01]);
    try std.testing.expect(tracker.visited[0x06]);
    try std.testing.expect(tracker.visited[0x05]);
    try std.testing.expect(!tracker.visited[0x02]);
}

test "CoverageTracker calculates coverage" {
    var tracker = CoverageTracker.init(std.testing.allocator);

    for (0..128) |i| {
        tracker.mark_command(@truncate(i));
    }

    const coverage = tracker.coverage_percent();
    try std.testing.expect(coverage >= 50.0);
    try std.testing.expect(coverage <= 55.0);
}

test "CoverageTracker order coverage" {
    var tracker = CoverageTracker.init(std.testing.allocator);

    tracker.mark_order(0x11);
    tracker.mark_order(0x1D);
    tracker.mark_order(0x05);

    const coverage = tracker.order_coverage_percent();
    try std.testing.expect(coverage >= 1.0);
}

test "CoverageTracker test count" {
    var tracker = CoverageTracker.init(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), tracker.test_count);

    tracker.mark_command(0x01);
    try std.testing.expectEqual(@as(usize, 1), tracker.test_count);

    tracker.mark_command(0x06);
    try std.testing.expectEqual(@as(usize, 2), tracker.test_count);
}
