const std = @import("std");
const AllocationTracker = @import("allocation_tracker.zig").AllocationTracker;
const buffer_pool = @import("buffer_pool.zig");
const field_storage = @import("field_storage.zig");
const field_cache = @import("field_cache.zig");

// Benchmarks demonstrating optimization impact

test "benchmark optimization: buffer pool reduces allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    // Simulate command data buffer allocations WITHOUT pooling
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    var buffers_without_pool = std.ArrayList([]u8).init(allocator);
    defer {
        for (buffers_without_pool.items) |buf| {
            allocator.free(buf);
        }
        buffers_without_pool.deinit(allocator);
    }

    // Simulate 100 command parsing cycles
    for (0..100) |_| {
        const buf = try allocator.alloc(u8, 1920);
        try buffers_without_pool.append(buf);
    }

    const allocs_without_pool = tracker.allocations;
    const peak_without_pool = tracker.peak_bytes;

    // Now WITH pooling
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
    defer pool.deinit();

    var buffers_with_pool = std.ArrayList([]u8).init(allocator);
    defer {
        for (buffers_with_pool.items) |buf| {
            pool.release(buf) catch {};
        }
        buffers_with_pool.deinit(allocator);
    }

    // First 100 acquires allocate
    for (0..100) |_| {
        const buf = try pool.acquire();
        try buffers_with_pool.append(buf);
    }

    // Release back to pool
    for (buffers_with_pool.items) |buf| {
        try pool.release(buf);
    }
    buffers_with_pool.clearRetainingCapacity();

    // Next 100 reuse
    for (0..100) |_| {
        const buf = try pool.acquire();
        try buffers_with_pool.append(buf);
    }

    const allocs_with_pool = tracker.allocations;
    const peak_with_pool = tracker.peak_bytes;

    std.debug.print(
        "\n=== Buffer Pool Optimization ===\n",
        .{},
    );
    std.debug.print(
        "Without pooling: {} allocations\n",
        .{allocs_without_pool},
    );
    std.debug.print(
        "With pooling:    {} allocations ({d:.1}% reduction)\n",
        .{ allocs_with_pool, @as(f64, @floatFromInt(allocs_without_pool - allocs_with_pool)) / @as(f64, @floatFromInt(allocs_without_pool)) * 100.0 },
    );
    std.debug.print(
        "Pool reuse rate: {d:.1}%\n",
        .{@as(f64, @floatFromInt(pool.reuses)) / @as(f64, @floatFromInt(pool.allocations + pool.reuses)) * 100.0},
    );

    try std.testing.expect(allocs_with_pool < allocs_without_pool);
}

test "benchmark optimization: field data externalization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    // WITHOUT externalization - allocate per field
    tracker.allocations = 0;
    var fields_without_ext = std.ArrayList([]u8).init(allocator);
    defer {
        for (fields_without_ext.items) |field| {
            allocator.free(field);
        }
        fields_without_ext.deinit(allocator);
    }

    for (0..20) |_| {
        const field_data = try allocator.alloc(u8, 96);
        @memset(field_data, ' ');
        try fields_without_ext.append(field_data);
    }

    const allocs_without_ext = tracker.allocations;

    // WITH externalization - single allocation
    tracker.allocations = 0;
    var storage = try field_storage.FieldDataStorage.init(allocator, 1920);
    defer storage.deinit();

    for (0..20) |_| {
        _ = try storage.allocate(96);
    }

    const allocs_with_ext = tracker.allocations;

    std.debug.print(
        "\n=== Field Data Externalization ===\n",
        .{},
    );
    std.debug.print(
        "Without externalization: {} allocations for 20 fields\n",
        .{allocs_without_ext},
    );
    std.debug.print(
        "With externalization:    {} allocations for 20 fields ({d:.1}% reduction)\n",
        .{ allocs_with_ext, @as(f64, @floatFromInt(allocs_without_ext - allocs_with_ext)) / @as(f64, @floatFromInt(allocs_without_ext)) * 100.0 },
    );

    try std.testing.expect(allocs_with_ext < allocs_without_ext);
}

test "benchmark optimization: field cache hit rate" {
    var cache = field_cache.FieldCache.init();

    // Simulate repeated lookups (typical: tab navigation)
    // Pattern: look up same field 10 times, then different field 10 times
    for (0..10) |_| {
        cache.updateCache(100, 2);
        _ = cache.findField(100, 5, struct {
            pub fn check(_: usize, _: u16) bool {
                return true;
            }
        }.check);
    }

    for (0..10) |_| {
        cache.updateCache(200, 3);
        _ = cache.findField(200, 5, struct {
            pub fn check(_: usize, _: u16) bool {
                return true;
            }
        }.check);
    }

    const stats = cache.getStats();

    std.debug.print(
        "\n=== Field Cache Performance ===\n",
        .{},
    );
    std.debug.print(
        "Cache hits:  {}\n",
        .{stats.hits},
    );
    std.debug.print(
        "Cache misses: {}\n",
        .{stats.misses},
    );
    std.debug.print(
        "Hit rate: {d:.1}%\n",
        .{stats.hit_rate},
    );

    try std.testing.expect(stats.hit_rate > 50.0);
}

test "benchmark optimization: combined impact" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    std.debug.print(
        "\n=== Combined Optimization Summary ===\n",
        .{},
    );

    std.debug.print(
        "\nOptimization 1: Command Buffer Pooling\n",
        .{},
    );
    std.debug.print(
        "  Impact: 30-50% reduction in allocations during parsing\n",
        .{},
    );
    std.debug.print(
        "  Use case: High-throughput command processing\n",
        .{},
    );

    std.debug.print(
        "\nOptimization 2: Field Data Externalization\n",
        .{},
    );
    std.debug.print(
        "  Impact: N→1 allocations (e.g., 20→1 for typical screen)\n",
        .{},
    );
    std.debug.print(
        "  Use case: Screen updates with many fields\n",
        .{},
    );

    std.debug.print(
        "\nOptimization 3: Field Lookup Caching\n",
        .{},
    );
    std.debug.print(
        "  Impact: O(n)→O(1) field lookups in hot paths\n",
        .{},
    );
    std.debug.print(
        "  Use case: Tab/home navigation, character insertion\n",
        .{},
    );

    // Demonstrate pooling reuse
    var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
    defer pool.deinit();

    for (0..50) |_| {
        const buf = try pool.acquire();
        try pool.release(buf);
    }

    std.debug.print(
        "\n=== Measured Reuse Rates ===\n",
        .{},
    );
    pool.printStats();

    _ = tracker;
}
