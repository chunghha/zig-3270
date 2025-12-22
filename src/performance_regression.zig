//! Performance regression testing framework
//!
//! Provides:
//! - Baseline storage and loading
//! - Regression detection (10% warning, 20% failure threshold)
//! - Per-module performance tracking
//! - Report generation

const std = @import("std");

/// Performance metrics for a module
pub const ModuleMetrics = struct {
    name: []const u8,
    throughput_mbs: f64, // MB/s
    operations_per_second: u64,
    avg_latency_us: f64, // microseconds
    peak_memory_bytes: u64,

    pub fn format(self: ModuleMetrics, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{s}: {d:.2} MB/s, {d} ops/s, {d:.2} µs latency, {d} bytes peak", .{
            self.name,
            self.throughput_mbs,
            self.operations_per_second,
            self.avg_latency_us,
            self.peak_memory_bytes,
        });
    }
};

/// Regression detection result
pub const RegressionResult = struct {
    module: []const u8,
    metric: []const u8,
    baseline: f64,
    current: f64,
    change_percent: f64,
    status: RegressionStatus,

    pub const RegressionStatus = enum {
        ok, // <10% change
        warning, // 10-20% change
        failure, // >20% change
    };

    pub fn is_regression(self: RegressionResult) bool {
        return self.status != .ok;
    }
};

/// Baseline storage (in-memory representation)
pub const Baseline = struct {
    allocator: std.mem.Allocator,
    metrics: std.StringHashMap(ModuleMetrics),
    timestamp: i64,
    zig_version: []const u8,

    pub fn init(allocator: std.mem.Allocator) Baseline {
        return Baseline{
            .allocator = allocator,
            .metrics = std.StringHashMap(ModuleMetrics).init(allocator),
            .timestamp = std.time.timestamp(),
            .zig_version = "0.15.0", // Can be detected at runtime
        };
    }

    pub fn deinit(self: *Baseline) void {
        self.metrics.deinit();
    }

    pub fn add_metric(self: *Baseline, metrics: ModuleMetrics) !void {
        try self.metrics.put(metrics.name, metrics);
    }

    pub fn get_metric(self: Baseline, name: []const u8) ?ModuleMetrics {
        return self.metrics.get(name);
    }
};

/// Regression detector
pub const RegressionDetector = struct {
    allocator: std.mem.Allocator,
    baseline: Baseline,

    pub fn init(allocator: std.mem.Allocator, baseline: Baseline) RegressionDetector {
        return RegressionDetector{
            .allocator = allocator,
            .baseline = baseline,
        };
    }

    pub fn detect_regression(self: RegressionDetector, current: ModuleMetrics) ?RegressionResult {
        const baseline_opt = self.baseline.get_metric(current.name);
        if (baseline_opt == null) return null; // No baseline

        const baseline = baseline_opt.?;

        // Check throughput
        const tp_change = (baseline.throughput_mbs - current.throughput_mbs) / baseline.throughput_mbs * 100.0;
        if (tp_change > 10.0) {
            return RegressionResult{
                .module = current.name,
                .metric = "throughput_mbs",
                .baseline = baseline.throughput_mbs,
                .current = current.throughput_mbs,
                .change_percent = tp_change,
                .status = if (tp_change > 20.0) .failure else .warning,
            };
        }

        // Check latency (increase is bad)
        const lat_change = (current.avg_latency_us - baseline.avg_latency_us) / baseline.avg_latency_us * 100.0;
        if (lat_change > 10.0) {
            return RegressionResult{
                .module = current.name,
                .metric = "avg_latency_us",
                .baseline = baseline.avg_latency_us,
                .current = current.avg_latency_us,
                .change_percent = lat_change,
                .status = if (lat_change > 20.0) .failure else .warning,
            };
        }

        // Check operations per second
        const ops_change = (baseline.operations_per_second -| current.operations_per_second) * 100 / (baseline.operations_per_second + 1);
        if (ops_change > 10) {
            return RegressionResult{
                .module = current.name,
                .metric = "operations_per_second",
                .baseline = @floatFromInt(baseline.operations_per_second),
                .current = @floatFromInt(current.operations_per_second),
                .change_percent = @floatFromInt(ops_change),
                .status = if (ops_change > 20) .failure else .warning,
            };
        }

        return null; // No regression detected
    }
};

/// Report generator
pub const ReportGenerator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReportGenerator {
        return ReportGenerator{
            .allocator = allocator,
        };
    }

    pub fn generate_report(
        self: ReportGenerator,
        baseline: Baseline,
        current: []const ModuleMetrics,
        writer: anytype,
    ) !void {
        try writer.print("Performance Regression Report\n", .{});
        try writer.print("==============================\n", .{});
        try writer.print("Timestamp: {d}\n", .{baseline.timestamp});
        try writer.print("Zig Version: {s}\n\n", .{baseline.zig_version});

        var failures: usize = 0;
        var warnings: usize = 0;

        for (current) |metrics| {
            const detector = RegressionDetector.init(self.allocator, baseline);
            const result_opt = detector.detect_regression(metrics);

            if (result_opt) |result| {
                if (result.is_regression()) {
                    const status_str = if (result.status == .failure) "FAIL" else "WARN";
                    try writer.print("[{s}] {s}: {s} changed {d:.1}% ({d:.2} -> {d:.2})\n", .{
                        status_str,
                        result.module,
                        result.metric,
                        result.change_percent,
                        result.baseline,
                        result.current,
                    });

                    if (result.status == .failure) {
                        failures += 1;
                    } else {
                        warnings += 1;
                    }
                }
            }
        }

        try writer.print("\nSummary: {d} failures, {d} warnings\n", .{ failures, warnings });
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "ModuleMetrics format" {
    const metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    var buf: [200]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try metrics.format("", .{}, fbs.writer());
    const result = fbs.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "parser"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "500"));
}

test "Baseline initialization" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    try std.testing.expect(baseline.metrics.count() == 0);
    try std.testing.expect(baseline.timestamp > 0);
}

test "Baseline add and get metric" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(metrics);
    const retrieved = baseline.get_metric("parser");

    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(f64, 500.0), retrieved.?.throughput_mbs);
}

test "RegressionDetector no baseline" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    var detector = RegressionDetector.init(std.testing.allocator, baseline);

    const current = ModuleMetrics{
        .name = "unknown",
        .throughput_mbs = 400.0,
        .operations_per_second = 80_000,
        .avg_latency_us = 12.5,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try std.testing.expectEqual(@as(?RegressionResult, null), result);
}

test "RegressionDetector detects throughput regression warning" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const baseline_metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(baseline_metrics);
    var detector = RegressionDetector.init(std.testing.allocator, baseline);

    // 15% regression (warning threshold)
    const current = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 425.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(RegressionResult.RegressionStatus.warning, result.?.status);
}

test "RegressionDetector detects throughput regression failure" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const baseline_metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(baseline_metrics);
    var detector = RegressionDetector.init(std.testing.allocator, baseline);

    // 25% regression (failure threshold)
    const current = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 375.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(RegressionResult.RegressionStatus.failure, result.?.status);
}

test "RegressionDetector detects latency regression" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const baseline_metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(baseline_metrics);
    var detector = RegressionDetector.init(std.testing.allocator, baseline);

    // 30% latency increase (failure)
    const current = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 13.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(RegressionResult.RegressionStatus.failure, result.?.status);
}

test "RegressionDetector passes when within threshold" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const baseline_metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(baseline_metrics);
    var detector = RegressionDetector.init(std.testing.allocator, baseline);

    // 5% improvement (within threshold)
    const current = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 525.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try std.testing.expectEqual(@as(?RegressionResult, null), result);
}

test "ReportGenerator generates report" {
    var baseline = Baseline.init(std.testing.allocator);
    defer baseline.deinit();

    const baseline_metrics = ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(baseline_metrics);

    var generator = ReportGenerator.init(std.testing.allocator);
    var buf: [500]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const current = [_]ModuleMetrics{
        ModuleMetrics{
            .name = "parser",
            .throughput_mbs = 425.0,
            .operations_per_second = 100_000,
            .avg_latency_us = 10.0,
            .peak_memory_bytes = 1_000_000,
        },
    };

    try generator.generate_report(baseline, &current, fbs.writer());
    const result = fbs.getWritten();

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "Regression"));
}
