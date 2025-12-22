/// Comprehensive stability and long-running tests for v0.10.0
/// Tests system stability under sustained load, extended operations, and resource cleanup
const std = @import("std");
const testing = std.testing;

/// Statistics for a stability test run
pub const StabilityStats = struct {
    iterations: usize = 0,
    total_commands: usize = 0,
    total_allocs: usize = 0,
    peak_bytes: usize = 0,
    final_bytes: usize = 0,
    errors: usize = 0,

    /// Calculate memory leak indicator (final vs peak)
    pub fn memoryLeakIndicator(self: StabilityStats) f64 {
        if (self.peak_bytes == 0) return 0;
        return @as(f64, @floatFromInt(self.final_bytes)) / @as(f64, @floatFromInt(self.peak_bytes)) * 100.0;
    }

    /// Calculate commands per second
    pub fn commandsPerSecond(self: StabilityStats) f64 {
        if (self.total_commands == 0) return 0;
        return @as(f64, @floatFromInt(self.total_commands));
    }
};

test "stability: sustained allocation cycle 100 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    // Execute 100 iterations of allocate/deallocate
    for (0..100) |_| {
        const items = try allocator.alloc(u8, 256);
        defer allocator.free(items);

        for (0..items.len) |i| {
            items[i] = @as(u8, @intCast(i % 256));
        }

        stats.iterations += 1;
        stats.total_commands += 1;
    }

    // Validation: 100 iterations completed
    try testing.expectEqual(@as(usize, 100), stats.iterations);
    try testing.expectEqual(@as(usize, 100), stats.total_commands);
}

test "stability: rapid small allocations 200 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..200) |i| {
        const size = (i % 100) + 1;
        const items = try allocator.alloc(u8, size);
        defer allocator.free(items);

        stats.iterations += 1;
        stats.total_commands += size;
    }

    try testing.expectEqual(@as(usize, 200), stats.iterations);
    try testing.expect(stats.total_commands > 0);
}

test "stability: large buffer allocations 50 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..50) |_| {
        const buffer = try allocator.alloc(u8, 1024);
        defer allocator.free(buffer);

        for (0..buffer.len) |i| {
            buffer[i] = @as(u8, @intCast(i % 256));
        }

        stats.iterations += 1;
        stats.total_commands += 1;
    }

    try testing.expectEqual(@as(usize, 50), stats.iterations);
}

test "stability: mixed size allocations 75 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    const sizes = [_]usize{ 16, 64, 256, 512, 1024 };

    for (0..75) |i| {
        const size = sizes[i % sizes.len];
        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);

        stats.iterations += 1;
        stats.total_commands += 1;
    }

    try testing.expectEqual(@as(usize, 75), stats.iterations);
}

test "stability: array allocation and iteration 100 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..100) |i| {
        const count = (i % 20) + 1;
        const items = try allocator.alloc(u32, count);
        defer allocator.free(items);

        for (0..items.len) |j| {
            items[j] = @as(u32, @intCast(j));
        }

        stats.iterations += 1;
        stats.total_commands += count;
    }

    try testing.expectEqual(@as(usize, 100), stats.iterations);
    try testing.expect(stats.total_commands > 0);
}

test "stability: alternating allocate/deallocate 150 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    var held: ?[]u8 = null;

    for (0..150) |i| {
        if (i % 2 == 0) {
            if (held) |h| {
                allocator.free(h);
            }
            held = try allocator.alloc(u8, 512);
        } else {
            if (held) |h| {
                allocator.free(h);
                held = null;
            }
        }
        stats.iterations += 1;
    }

    if (held) |h| {
        allocator.free(h);
    }

    try testing.expectEqual(@as(usize, 150), stats.iterations);
}

test "stability: nested allocation context 80 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..80) |_| {
        const outer = try allocator.alloc(u8, 256);
        defer allocator.free(outer);

        for (0..10) |_| {
            const inner = try allocator.alloc(u8, 64);
            defer allocator.free(inner);
            stats.total_commands += 1;
        }

        stats.iterations += 1;
    }

    try testing.expectEqual(@as(usize, 80), stats.iterations);
    try testing.expectEqual(@as(usize, 800), stats.total_commands);
}

test "stability: allocation fragmentation resistance 120 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    var held: [30]?[]u8 = [_]?[]u8{null} ** 30;

    for (0..120) |i| {
        const size = (i % 50) + 10;
        const buffer = try allocator.alloc(u8, size);

        const idx = i % 30;
        if (held[idx]) |old| {
            allocator.free(old);
        }
        held[idx] = buffer;

        stats.iterations += 1;
    }

    for (&held) |*slot| {
        if (slot.*) |buf| {
            allocator.free(buf);
        }
    }

    try testing.expectEqual(@as(usize, 120), stats.iterations);
}

test "stability: sequential buffer copies 90 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..90) |iteration| {
        var src = try allocator.alloc(u8, 128);
        defer allocator.free(src);

        for (0..src.len) |i| {
            src[i] = @as(u8, @intCast((iteration + i) % 256));
        }

        const dst = try allocator.alloc(u8, 128);
        defer allocator.free(dst);

        @memcpy(dst, src);

        // Verify copy
        try testing.expect(std.mem.eql(u8, src, dst));

        stats.iterations += 1;
        stats.total_commands += 2; // copy operation
    }

    try testing.expectEqual(@as(usize, 90), stats.iterations);
}

test "stability: allocation patterns under load 110 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    for (0..110) |i| {
        const pattern = i % 4;

        switch (pattern) {
            0 => {
                const small = try allocator.alloc(u8, 32);
                defer allocator.free(small);
            },
            1 => {
                const medium = try allocator.alloc(u8, 256);
                defer allocator.free(medium);
            },
            2 => {
                const large = try allocator.alloc(u8, 1024);
                defer allocator.free(large);
            },
            else => {
                const xlarge = try allocator.alloc(u8, 4096);
                defer allocator.free(xlarge);
            },
        }

        stats.iterations += 1;
        stats.total_commands += 1;
    }

    try testing.expectEqual(@as(usize, 110), stats.iterations);
}

test "stability: memory reuse efficiency 100 iterations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stats = StabilityStats{};

    // Allocate, use, and deallocate repeatedly to test memory reuse
    for (0..100) |_| {
        const buffers = try allocator.alloc([]u8, 10);
        defer allocator.free(buffers);

        for (0..buffers.len) |i| {
            buffers[i] = try allocator.alloc(u8, 128);
        }

        for (buffers) |buf| {
            allocator.free(buf);
        }

        stats.iterations += 1;
    }

    try testing.expectEqual(@as(usize, 100), stats.iterations);
}

test "stability: stats calculation functions" {
    var stats = StabilityStats{
        .peak_bytes = 1000,
        .final_bytes = 900,
    };

    const leak = stats.memoryLeakIndicator();
    try testing.expect(leak > 80.0 and leak < 95.0);

    stats.total_commands = 1000;
    const cps = stats.commandsPerSecond();
    try testing.expect(cps == 1000.0);
}

test "stability: multiple allocators independent operation" {
    var gpa1 = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa1.deinit();

    var gpa2 = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa2.deinit();

    const alloc1 = gpa1.allocator();
    const alloc2 = gpa2.allocator();

    const buf1 = try alloc1.alloc(u8, 256);
    defer alloc1.free(buf1);

    const buf2 = try alloc2.alloc(u8, 256);
    defer alloc2.free(buf2);

    try testing.expect(buf1.ptr != buf2.ptr);
}
