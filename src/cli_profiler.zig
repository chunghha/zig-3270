const std = @import("std");
const profiler = @import("profiler.zig");

/// Performance baseline metrics from benchmarks
pub const PerformanceBaseline = struct {
    parser_throughput_mbps: f64 = 500.0, // MB/s
    commands_per_ms: f64 = 2000.0, // commands/ms
    avg_allocation_bytes_per_command: u64 = 512,
    peak_memory_usage: u64 = 1024 * 1024, // 1 MB
};

/// CLI tool for performance analysis and reporting
pub const CliProfiler = struct {
    allocator: std.mem.Allocator,
    baseline: PerformanceBaseline,

    pub fn init(allocator: std.mem.Allocator) CliProfiler {
        return CliProfiler{
            .allocator = allocator,
            .baseline = PerformanceBaseline{},
        };
    }

    /// Generate performance report from profiler data
    pub fn generate_report(
        self: CliProfiler,
        prof: *const profiler.Profiler,
        duration_ms: f64,
        command_count: u64,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== PERFORMANCE ANALYSIS REPORT ===\n\n", .{});

        // Summary
        try writer.print("SUMMARY\n", .{});
        try writer.print("-------\n", .{});
        try writer.print("Duration: {d:.2} ms\n", .{duration_ms});
        try writer.print("Commands Processed: {}\n", .{command_count});
        if (duration_ms > 0) {
            const throughput = @as(f64, @floatFromInt(command_count)) / duration_ms;
            try writer.print("Throughput: {d:.0} commands/ms\n", .{throughput});
        }
        try writer.print("\n", .{});

        // Memory stats
        try writer.print("MEMORY USAGE\n", .{});
        try writer.print("------------\n", .{});
        try writer.print("Total Allocated: {} bytes ({d:.2} KB)\n", .{
            prof.memory_stats.total_allocated,
            @as(f64, @floatFromInt(prof.memory_stats.total_allocated)) / 1024.0,
        });
        try writer.print("Total Freed: {} bytes ({d:.2} KB)\n", .{
            prof.memory_stats.total_freed,
            @as(f64, @floatFromInt(prof.memory_stats.total_freed)) / 1024.0,
        });
        try writer.print("Current Usage: {} bytes ({d:.2} KB)\n", .{
            prof.memory_stats.current_usage,
            @as(f64, @floatFromInt(prof.memory_stats.current_usage)) / 1024.0,
        });
        try writer.print("Peak Usage: {} bytes ({d:.2} KB)\n", .{
            prof.memory_stats.peak_usage,
            @as(f64, @floatFromInt(prof.memory_stats.peak_usage)) / 1024.0,
        });
        try writer.print("Allocation Count: {}\n", .{prof.memory_stats.allocation_count});
        try writer.print("Deallocation Count: {}\n", .{prof.memory_stats.deallocation_count});
        try writer.print("\n", .{});

        // Timing stats
        if (prof.timings.count() > 0) {
            try writer.print("TIMING ANALYSIS\n", .{});
            try writer.print("---------------\n", .{});

            var iter = prof.timings.valueIterator();
            while (iter.next()) |stat| {
                try writer.print("{s}:\n", .{stat.name});
                try writer.print("  Calls: {}\n", .{stat.call_count});
                try writer.print("  Total: {d:.3} ms\n", .{stat.total_time_ms()});
                try writer.print("  Avg: {d:.2} μs\n", .{stat.avg_time_us()});
                try writer.print("  Min: {d:.2} μs\n", .{@as(f64, @floatFromInt(stat.min_time_ns)) / 1000.0});
                try writer.print("  Max: {d:.2} μs\n", .{@as(f64, @floatFromInt(stat.max_time_ns)) / 1000.0});
            }
            try writer.print("\n", .{});
        }

        return result.toOwnedSlice();
    }

    /// Compare against baseline and identify performance issues
    pub fn compare_baseline(
        self: CliProfiler,
        prof: *const profiler.Profiler,
        command_count: u64,
        duration_ms: f64,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== PERFORMANCE COMPARISON ===\n\n", .{});

        // Throughput comparison
        try writer.print("THROUGHPUT\n", .{});
        try writer.print("---------\n", .{});
        if (duration_ms > 0) {
            const actual = @as(f64, @floatFromInt(command_count)) / duration_ms;
            const baseline = self.baseline.commands_per_ms;
            const ratio = (actual / baseline) * 100.0;
            try writer.print("Baseline: {d:.0} commands/ms\n", .{baseline});
            try writer.print("Actual:   {d:.0} commands/ms\n", .{actual});
            try writer.print("Performance: {d:.1}% of baseline\n", .{ratio});
            if (actual < baseline) {
                try writer.print("⚠ WARNING: Below baseline performance\n", .{});
            } else {
                try writer.print("✓ OK: Meeting or exceeding baseline\n", .{});
            }
        }
        try writer.print("\n", .{});

        // Memory comparison
        try writer.print("MEMORY USAGE\n", .{});
        try writer.print("------------\n", .{});
        const baseline_peak = self.baseline.peak_memory_usage;
        const actual_peak = prof.memory_stats.peak_usage;
        const mem_ratio = (@as(f64, @floatFromInt(actual_peak)) / @as(f64, @floatFromInt(baseline_peak))) * 100.0;
        try writer.print("Baseline Peak: {} bytes\n", .{baseline_peak});
        try writer.print("Actual Peak:   {} bytes\n", .{actual_peak});
        try writer.print("Memory Usage: {d:.1}% of baseline\n", .{mem_ratio});
        if (actual_peak > baseline_peak) {
            try writer.print("⚠ WARNING: Peak memory exceeds baseline\n", .{});
        } else {
            try writer.print("✓ OK: Within baseline memory\n", .{});
        }
        try writer.print("\n", .{});

        return result.toOwnedSlice();
    }

    /// Identify bottlenecks from timing data
    pub fn identify_bottlenecks(
        self: CliProfiler,
        prof: *const profiler.Profiler,
    ) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var writer = result.writer();

        try writer.print("=== PERFORMANCE BOTTLENECKS ===\n\n", .{});

        if (prof.timings.count() == 0) {
            try writer.print("No timing data available.\n", .{});
            return result.toOwnedSlice();
        }

        // Sort timings by total time
        var timings_array = try std.ArrayList(profiler.Profiler.TimingStats).initCapacity(
            self.allocator,
            prof.timings.count(),
        );
        defer timings_array.deinit();

        var iter = prof.timings.valueIterator();
        while (iter.next()) |stat| {
            try timings_array.append(stat.*);
        }

        // Sort by total time (descending)
        std.mem.sort(
            profiler.Profiler.TimingStats,
            timings_array.items,
            {},
            struct {
                fn compare(_: void, a: profiler.Profiler.TimingStats, b: profiler.Profiler.TimingStats) bool {
                    return a.total_time_ns > b.total_time_ns;
                }
            }.compare,
        );

        try writer.print("Top bottlenecks by total time:\n", .{});
        try writer.print("\n", .{});

        var total_time: u64 = 0;
        for (timings_array.items) |stat| {
            total_time += stat.total_time_ns;
        }

        for (timings_array.items, 0..) |stat, idx| {
            const pct = if (total_time > 0)
                (@as(f64, @floatFromInt(stat.total_time_ns)) / @as(f64, @floatFromInt(total_time))) * 100.0
            else
                0.0;

            try writer.print("{d:2}. {s}\n", .{ idx + 1, stat.name });
            try writer.print("    Time: {d:.3} ms ({d:.1}%)\n", .{ stat.total_time_ms(), pct });
            try writer.print("    Calls: {}\n", .{stat.call_count});
            try writer.print("    Avg: {d:.2} μs\n", .{stat.avg_time_us()});
            if (pct > 20.0) {
                try writer.print("    ⚠ HOT PATH - Consider optimization\n", .{});
            }
            try writer.print("\n", .{});
        }

        return result.toOwnedSlice();
    }

    /// Export performance report to file
    pub fn export_report(
        self: CliProfiler,
        report: []const u8,
        path: []const u8,
    ) !void {
        var file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        _ = try file.writeAll(report);
    }
};

// Tests
test "cli profiler: generate report" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prof = profiler.Profiler.init(allocator);
    defer prof.deinit();

    prof.memory_stats.total_allocated = 1024;
    prof.memory_stats.total_freed = 512;
    prof.memory_stats.current_usage = 512;
    prof.memory_stats.peak_usage = 2048;

    const cli = CliProfiler.init(allocator);
    const report = try cli.generate_report(&prof, 100.0, 50000);
    defer allocator.free(report);

    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "PERFORMANCE ANALYSIS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "MEMORY USAGE"));
}

test "cli profiler: compare baseline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prof = profiler.Profiler.init(allocator);
    defer prof.deinit();

    prof.memory_stats.peak_usage = 500000; // 500 KB

    const cli = CliProfiler.init(allocator);
    const report = try cli.compare_baseline(&prof, 100000, 50.0);
    defer allocator.free(report);

    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "PERFORMANCE COMPARISON"));
    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "THROUGHPUT"));
}

test "cli profiler: identify bottlenecks" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prof = profiler.Profiler.init(allocator);
    defer prof.deinit();

    // Add some timing data
    prof.record_timing("parser", 50_000_000); // 50ms
    prof.record_timing("executor", 10_000_000); // 10ms

    const cli = CliProfiler.init(allocator);
    const report = try cli.identify_bottlenecks(&prof);
    defer allocator.free(report);

    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "BOTTLENECKS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "parser"));
}

test "cli profiler: empty profiler" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prof = profiler.Profiler.init(allocator);
    defer prof.deinit();

    const cli = CliProfiler.init(allocator);
    const report = try cli.identify_bottlenecks(&prof);
    defer allocator.free(report);

    try std.testing.expect(std.mem.containsAtLeast(u8, report, 1, "No timing data"));
}
