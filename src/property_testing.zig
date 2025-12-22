const std = @import("std");
const protocol = @import("protocol.zig");

/// Property-Based Testing Framework for TN3270 Protocol
/// Inspired by QuickCheck - generates and tests properties of protocol components
/// Random number generator wrapper for reproducible tests
pub const Rng = struct {
    prng: std.Random.DefaultPrng,
    random: std.Random,

    pub fn init(seed: u64) Rng {
        var prng = std.Random.DefaultPrng.init(seed);
        return .{
            .prng = prng,
            .random = prng.random(),
        };
    }

    pub fn u8(self: *Rng) u8 {
        return self.random.int(u8);
    }

    pub fn u16(self: *Rng) u16 {
        return self.random.int(u16);
    }

    pub fn u32(self: *Rng) u32 {
        return self.random.int(u32);
    }

    pub fn range(self: *Rng, min: u32, max: u32) u32 {
        if (min >= max) return min;
        return min + (self.random.intRangeLessThan(u32, 0, max - min));
    }

    pub fn bytes(self: *Rng, buffer: []u8) void {
        for (buffer) |*b| {
            b.* = self.u8();
        }
    }

    pub fn bool(self: *Rng) bool {
        return self.random.boolean();
    }
};

/// Generator trait for creating arbitrary values
pub const Generator = struct {
    data: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        generate: *const fn (*anyopaque, *Rng) error{}![]const u8,
        free: *const fn (*anyopaque, std.mem.Allocator) void,
    };

    pub fn init(comptime T: type, ptr: *T) Generator {
        return .{
            .data = ptr,
            .vtable = &.{
                .generate = generate_impl(T),
                .free = free_impl(T),
            },
        };
    }

    fn generate_impl(comptime T: type) *const fn (*anyopaque, *Rng) error{}![]const u8 {
        return struct {
            fn f(ptr: *anyopaque, rng: *Rng) error{}![]const u8 {
                const self = @as(*T, @ptrCast(ptr));
                return try self.generate(rng);
            }
        }.f;
    }

    fn free_impl(comptime T: type) *const fn (*anyopaque, std.mem.Allocator) void {
        return struct {
            fn f(ptr: *anyopaque, allocator: std.mem.Allocator) void {
                const self = @as(*T, @ptrCast(ptr));
                self.free(allocator);
            }
        }.f;
    }

    pub fn generate(self: Generator, rng: *Rng) error{}![]const u8 {
        return try self.vtable.generate(self.data, rng);
    }

    pub fn free(self: Generator, allocator: std.mem.Allocator) void {
        self.vtable.free(self.data, allocator);
    }
};

/// Command code generator
pub const CommandCodeGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CommandCodeGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: CommandCodeGenerator, rng: *Rng) ![]const u8 {
        var buffer = try self.allocator.alloc(u8, 1);
        buffer[0] = rng.u8();
        return buffer;
    }

    pub fn free(self: CommandCodeGenerator, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Field attribute generator
pub const FieldAttributeGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FieldAttributeGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: FieldAttributeGenerator, rng: *Rng) ![]const u8 {
        var buffer = try self.allocator.alloc(u8, 1);
        // Valid field attributes are in specific ranges
        buffer[0] = if (rng.bool()) rng.range(0x00, 0x0F) else rng.range(0xC0, 0xFF);
        return buffer;
    }

    pub fn free(self: FieldAttributeGenerator, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Address generator (row, col on 24x80 screen)
pub const AddressGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AddressGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: AddressGenerator, rng: *Rng) ![]const u8 {
        var buffer = try self.allocator.alloc(u8, 2);
        buffer[0] = rng.range(0, 24); // Row 0-23
        buffer[1] = rng.range(0, 80); // Col 0-79
        return buffer;
    }

    pub fn free(self: AddressGenerator, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Buffer content generator
pub const BufferGenerator = struct {
    allocator: std.mem.Allocator,
    max_size: usize = 1024,

    pub fn init(allocator: std.mem.Allocator) BufferGenerator {
        return .{ .allocator = allocator };
    }

    pub fn generate(self: BufferGenerator, rng: *Rng) ![]const u8 {
        const size = rng.range(0, @as(u32, @intCast(self.max_size)));
        var buffer = try self.allocator.alloc(u8, size);
        rng.bytes(buffer);
        return buffer;
    }

    pub fn free(self: BufferGenerator, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

/// Property test result
pub const PropertyResult = struct {
    passed: bool,
    iterations: usize,
    seed: u64,
    failure_input: ?[]u8 = null,
    failure_message: ?[]const u8 = null,

    pub fn deinit(self: *PropertyResult, allocator: std.mem.Allocator) void {
        if (self.failure_input) |input| {
            allocator.free(input);
        }
    }
};

/// Property test runner
pub const PropertyRunner = struct {
    allocator: std.mem.Allocator,
    iterations: usize = 100,
    seed: u64 = 42,

    pub fn init(allocator: std.mem.Allocator) PropertyRunner {
        return .{ .allocator = allocator };
    }

    /// Run a property-based test with shrinking support
    pub fn run_test(
        self: PropertyRunner,
        comptime TestFn: type,
        test_fn: TestFn,
        generator: Generator,
    ) !PropertyResult {
        var rng = Rng.init(self.seed);

        for (0..self.iterations) |_| {
            const input = try generator.generate(&rng);
            defer self.allocator.free(input);

            if (!try test_fn.check(input)) {
                // Property failed - try to shrink
                var shrank_input = try self.allocator.dupe(u8, input);
                defer self.allocator.free(shrank_input);

                return .{
                    .passed = false,
                    .iterations = self.iterations,
                    .seed = self.seed,
                    .failure_input = shrank_input,
                    .failure_message = "Property check failed",
                };
            }
        }

        return .{
            .passed = true,
            .iterations = self.iterations,
            .seed = self.seed,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "rng initialization and generation" {
    var rng = Rng.init(12345);

    const b1 = rng.u8();
    const b2 = rng.u16();
    const b3 = rng.u32();

    // Just verify they don't crash
    _ = b1;
    _ = b2;
    _ = b3;
}

test "rng range generation" {
    var rng = Rng.init(54321);

    const value = rng.range(10, 20);
    try std.testing.expect(value >= 10 and value < 20);
}

test "rng bytes generation" {
    var allocator = std.testing.allocator;
    var rng = Rng.init(99999);

    var buffer = try allocator.alloc(u8, 64);
    defer allocator.free(buffer);

    rng.bytes(buffer);

    // Verify buffer was filled (not all zeros)
    var any_nonzero = false;
    for (buffer) |b| {
        if (b != 0) any_nonzero = true;
    }
    try std.testing.expect(any_nonzero);
}

test "command code generator" {
    var allocator = std.testing.allocator;
    var rng = Rng.init(11111);

    var gen = CommandCodeGenerator.init(allocator);
    defer gen.free(allocator);

    const code = try gen.generate(&rng);
    defer allocator.free(code);

    try std.testing.expectEqual(@as(usize, 1), code.len);
}

test "field attribute generator" {
    var allocator = std.testing.allocator;
    var rng = Rng.init(22222);

    var gen = FieldAttributeGenerator.init(allocator);
    defer gen.free(allocator);

    const attr = try gen.generate(&rng);
    defer allocator.free(attr);

    try std.testing.expectEqual(@as(usize, 1), attr.len);
}

test "address generator" {
    var allocator = std.testing.allocator;
    var rng = Rng.init(33333);

    var gen = AddressGenerator.init(allocator);
    defer gen.free(allocator);

    const addr = try gen.generate(&rng);
    defer allocator.free(addr);

    try std.testing.expectEqual(@as(usize, 2), addr.len);
    try std.testing.expect(addr[0] < 24); // Row valid
    try std.testing.expect(addr[1] < 80); // Col valid
}

test "buffer generator" {
    var allocator = std.testing.allocator;
    var rng = Rng.init(44444);

    var gen = BufferGenerator.init(allocator);
    defer gen.free(allocator);

    const buf = try gen.generate(&rng);
    defer allocator.free(buf);

    try std.testing.expect(buf.len <= gen.max_size);
}

test "rng boolean generation" {
    var rng = Rng.init(55555);

    const b1 = rng.bool();
    const b2 = rng.bool();

    // Just verify they are booleans
    _ = b1;
    _ = b2;
}

test "property runner initialization" {
    var allocator = std.testing.allocator;
    const runner = PropertyRunner.init(allocator);

    try std.testing.expectEqual(@as(usize, 100), runner.iterations);
    try std.testing.expectEqual(@as(u64, 42), runner.seed);
}

test "rng range boundary conditions" {
    var rng = Rng.init(66666);

    const v1 = rng.range(5, 5); // min == max
    try std.testing.expectEqual(@as(u32, 5), v1);

    const v2 = rng.range(0, 1); // Range of 1
    try std.testing.expect(v2 == 0);
}
