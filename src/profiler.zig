const std = @import("std");

/// Profiler module for memory and performance analysis
/// Tracks allocations, deallocations, and timing hot paths
pub const Profiler = struct {
    /// Memory statistics
    pub const MemStats = struct {
        total_allocated: usize = 0,
        total_freed: usize = 0,
        peak_usage: usize = 0,
        current_usage: usize = 0,
        allocation_count: u32 = 0,
        deallocation_count: u32 = 0,

        pub fn net_usage(self: MemStats) i64 {
            return @as(i64, @intCast(self.total_allocated)) - @as(i64, @intCast(self.total_freed));
        }
    };

    /// Timing statistics for a named scope
    pub const TimingStats = struct {
        name: []const u8,
        total_time_ns: u64 = 0,
        call_count: u32 = 0,
        min_time_ns: u64 = std.math.maxInt(u64),
        max_time_ns: u64 = 0,

        pub fn avg_time_ns(self: TimingStats) f64 {
            if (self.call_count == 0) return 0;
            return @as(f64, @floatFromInt(self.total_time_ns)) / @as(f64, @floatFromInt(self.call_count));
        }

        pub fn avg_time_us(self: TimingStats) f64 {
            return self.avg_time_ns() / 1000.0;
        }

        pub fn total_time_ms(self: TimingStats) f64 {
            return @as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0;
        }
    };

    /// Timing scope for RAII-style timing
    pub const TimingScope = struct {
        name: []const u8,
        start_ns: u64,
        profiler: *Profiler,

        pub fn init(profiler: *Profiler, name: []const u8) TimingScope {
            return TimingScope{
                .name = name,
                .start_ns = std.time.nanoTimestamp(),
                .profiler = profiler,
            };
        }

        pub fn end(self: TimingScope) void {
            const end_ns = std.time.nanoTimestamp();
            const elapsed = end_ns - self.start_ns;
            self.profiler.record_timing(self.name, elapsed);
        }
    };

    allocator: std.mem.Allocator,
    memory_stats: MemStats = .{},
    timings: std.StringHashMap(TimingStats),

    pub fn init(allocator: std.mem.Allocator) Profiler {
        return Profiler{
            .allocator = allocator,
            .timings = std.StringHashMap(TimingStats).init(allocator),
        };
    }

    pub fn deinit(self: *Profiler) void {
        var iter = self.timings.valueIterator();
        while (iter.next()) |_| {
            // Names are stored externally, not freed here
        }
        self.timings.deinit();
    }

    /// Record an allocation
    pub fn record_alloc(self: *Profiler, size: usize) void {
        self.memory_stats.total_allocated += size;
        self.memory_stats.current_usage += size;
        self.memory_stats.allocation_count += 1;

        if (self.memory_stats.current_usage > self.memory_stats.peak_usage) {
            self.memory_stats.peak_usage = self.memory_stats.current_usage;
        }
    }

    /// Record a deallocation
    pub fn record_free(self: *Profiler, size: usize) void {
        self.memory_stats.total_freed += size;
        if (self.memory_stats.current_usage >= size) {
            self.memory_stats.current_usage -= size;
        }
        self.memory_stats.deallocation_count += 1;
    }

    /// Record timing for an operation
    pub fn record_timing(self: *Profiler, name: []const u8, elapsed_ns: u64) void {
        var stats = self.timings.get(name) orelse TimingStats{
            .name = name,
        };

        stats.total_time_ns += elapsed_ns;
        stats.call_count += 1;
        if (elapsed_ns < stats.min_time_ns) {
            stats.min_time_ns = elapsed_ns;
        }
        if (elapsed_ns > stats.max_time_ns) {
            stats.max_time_ns = elapsed_ns;
        }

        self.timings.put(name, stats) catch {
            // Ignore allocation errors in profiler
        };
    }

    /// Begin a timing scope
    pub fn scope(self: *Profiler, name: []const u8) TimingScope {
        return TimingScope.init(self, name);
    }

    /// Get memory statistics
    pub fn get_memory_stats(self: Profiler) MemStats {
        return self.memory_stats;
    }

    /// Get timing stats for a specific operation
    pub fn get_timing_stats(self: Profiler, name: []const u8) ?TimingStats {
        return self.timings.get(name);
    }

    /// Print memory report
    pub fn print_memory_report(self: Profiler, writer: std.io.AnyWriter) !void {
        const stats = self.memory_stats;
        try writer.print("=== Memory Report ===\n", .{});
        try writer.print("Total Allocated: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.total_allocated)) / 1_000_000.0});
        try writer.print("Total Freed: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.total_freed)) / 1_000_000.0});
        try writer.print("Current Usage: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.current_usage)) / 1_000_000.0});
        try writer.print("Peak Usage: {d:.2} MB\n", .{@as(f64, @floatFromInt(stats.peak_usage)) / 1_000_000.0});
        try writer.print("Allocations: {d}\n", .{stats.allocation_count});
        try writer.print("Deallocations: {d}\n", .{stats.deallocation_count});
        try writer.print("Net Allocations: {d}\n", .{stats.allocation_count - stats.deallocation_count});
    }

    /// Print timing report
    pub fn print_timing_report(self: Profiler, writer: std.io.AnyWriter) !void {
        try writer.print("=== Timing Report ===\n", .{});
        var iter = self.timings.valueIterator();
        while (iter.next()) |stats| {
            try writer.print("{s:20s}: {d:6d} calls, {d:8.2f} µs avg, {d:8.2f} ms total\n", .{
                stats.name,
                stats.call_count,
                stats.avg_time_us(),
                stats.total_time_ms(),
            });
        }
    }
};

// === Tests ===

test "profiler record allocation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_alloc(1024);
    const stats = profiler.get_memory_stats();

    try std.testing.expectEqual(@as(usize, 1024), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 1024), stats.current_usage);
    try std.testing.expectEqual(@as(u32, 1), stats.allocation_count);
}

test "profiler record deallocation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_alloc(1024);
    profiler.record_free(512);
    const stats = profiler.get_memory_stats();

    try std.testing.expectEqual(@as(usize, 1024), stats.total_allocated);
    try std.testing.expectEqual(@as(usize, 512), stats.total_freed);
    try std.testing.expectEqual(@as(usize, 512), stats.current_usage);
    try std.testing.expectEqual(@as(u32, 1), stats.deallocation_count);
}

test "profiler peak usage tracking" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_alloc(1000);
    try std.testing.expectEqual(@as(usize, 1000), profiler.memory_stats.peak_usage);

    profiler.record_alloc(500);
    try std.testing.expectEqual(@as(usize, 1500), profiler.memory_stats.peak_usage);

    profiler.record_free(2000);
    try std.testing.expectEqual(@as(usize, 1500), profiler.memory_stats.peak_usage);
}

test "profiler net usage calculation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_alloc(1000);
    profiler.record_alloc(500);
    profiler.record_free(300);

    const stats = profiler.get_memory_stats();
    try std.testing.expectEqual(@as(i64, 1200), stats.net_usage());
}

test "profiler timing recording" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_timing("operation_a", 1000);
    profiler.record_timing("operation_a", 2000);

    const stats = profiler.get_timing_stats("operation_a");
    try std.testing.expect(stats != null);
    if (stats) |s| {
        try std.testing.expectEqual(@as(u32, 2), s.call_count);
        try std.testing.expectEqual(@as(u64, 3000), s.total_time_ns);
        try std.testing.expectEqual(@as(u64, 1000), s.min_time_ns);
        try std.testing.expectEqual(@as(u64, 2000), s.max_time_ns);
    }
}

test "profiler timing scope" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    {
        var scope = profiler.scope("test_scope");
        defer scope.end();
        // Simulate some work
    }

    const stats = profiler.get_timing_stats("test_scope");
    try std.testing.expect(stats != null);
    if (stats) |s| {
        try std.testing.expectEqual(@as(u32, 1), s.call_count);
    }
}

test "profiler timing statistics calculations" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_timing("op", 1000);
    profiler.record_timing("op", 2000);
    profiler.record_timing("op", 3000);

    const stats = profiler.get_timing_stats("op");
    try std.testing.expect(stats != null);
    if (stats) |s| {
        try std.testing.expectEqual(@as(f64, 2000.0), s.avg_time_ns());
        try std.testing.expectEqual(@as(u64, 1000), s.min_time_ns);
        try std.testing.expectEqual(@as(u64, 3000), s.max_time_ns);
    }
}

test "profiler multiple operations" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_timing("parse", 5000);
    profiler.record_timing("execute", 3000);
    profiler.record_timing("render", 2000);

    try std.testing.expect(profiler.get_timing_stats("parse") != null);
    try std.testing.expect(profiler.get_timing_stats("execute") != null);
    try std.testing.expect(profiler.get_timing_stats("render") != null);
}

test "profiler allocator wrapper tracking" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    // Simulate allocator usage patterns
    profiler.record_alloc(256);
    profiler.record_alloc(512);
    profiler.record_alloc(1024);
    profiler.record_free(256);

    const stats = profiler.get_memory_stats();
    try std.testing.expectEqual(@as(u32, 3), stats.allocation_count);
    try std.testing.expectEqual(@as(u32, 1), stats.deallocation_count);
    try std.testing.expectEqual(@as(usize, 1536), stats.current_usage);
    try std.testing.expectEqual(@as(usize, 1792), stats.peak_usage);
}

test "profiler memory report generation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_alloc(1024 * 1024); // 1 MB
    profiler.record_free(512 * 1024); // 512 KB

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer().any();
    try profiler.print_memory_report(writer);

    const result = buffer.items;
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "Memory Report"));
}

test "profiler timing report generation" {
    var profiler = Profiler.init(std.testing.allocator);
    defer profiler.deinit();

    profiler.record_timing("parse", 5000);
    profiler.record_timing("execute", 3000);

    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    var writer = buffer.writer().any();
    try profiler.print_timing_report(writer);

    const result = buffer.items;
    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "Timing Report"));
}
