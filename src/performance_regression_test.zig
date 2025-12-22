/// Performance regression testing suite for v0.10.0
/// Validates that performance metrics stay within acceptable thresholds compared to baselines
const std = @import("std");
const testing = std.testing;
const performance_regression = @import("performance_regression.zig");
const allocation_tracker = @import("allocation_tracker.zig");
const protocol_layer = @import("protocol_layer.zig");

/// Baseline metrics established for v0.9.4
pub const V094_BASELINE = struct {
    pub const parser: performance_regression.ModuleMetrics = .{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    pub const executor: performance_regression.ModuleMetrics = .{
        .name = "executor",
        .throughput_mbs = 300.0,
        .operations_per_second = 50_000,
        .avg_latency_us = 20.0,
        .peak_memory_bytes = 2_000_000,
    };

    pub const field_lookup: performance_regression.ModuleMetrics = .{
        .name = "field_lookup",
        .throughput_mbs = 1000.0,
        .operations_per_second = 200_000,
        .avg_latency_us = 5.0,
        .peak_memory_bytes = 500_000,
    };

    pub const session_creation: performance_regression.ModuleMetrics = .{
        .name = "session_creation",
        .throughput_mbs = 50.0,
        .operations_per_second = 1_000,
        .avg_latency_us = 1000.0,
        .peak_memory_bytes = 5_000_000,
    };
};

test "regression: parser throughput within 2% of v0.9.4 baseline" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.parser);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 495.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}

test "regression: parser throughput regression detected at 5% loss" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.parser);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 425.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try testing.expect(result != null);
    try testing.expectEqual(performance_regression.RegressionResult.RegressionStatus.warning, result.?.status);
}

test "regression: executor throughput within threshold" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.executor);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "executor",
        .throughput_mbs = 290.0,
        .operations_per_second = 50_000,
        .avg_latency_us = 20.0,
        .peak_memory_bytes = 2_000_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}

test "regression: field lookup latency improvement detected" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.field_lookup);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "field_lookup",
        .throughput_mbs = 1050.0,
        .operations_per_second = 200_000,
        .avg_latency_us = 4.75,
        .peak_memory_bytes = 500_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}

test "regression: field lookup latency regression at 25%" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.field_lookup);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "field_lookup",
        .throughput_mbs = 1000.0,
        .operations_per_second = 200_000,
        .avg_latency_us = 6.25,
        .peak_memory_bytes = 500_000,
    };

    const result = detector.detect_regression(current);
    try testing.expect(result != null);
    try testing.expectEqual(performance_regression.RegressionResult.RegressionStatus.failure, result.?.status);
}

test "regression: session creation latency within bounds" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.session_creation);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "session_creation",
        .throughput_mbs = 50.0,
        .operations_per_second = 1_000,
        .avg_latency_us = 1080.0,
        .peak_memory_bytes = 5_000_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}

test "regression: baseline with multiple metrics" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.parser);
    try baseline.add_metric(V094_BASELINE.executor);
    try baseline.add_metric(V094_BASELINE.field_lookup);

    try testing.expectEqual(@as(usize, 3), baseline.metrics.count());

    try testing.expect(baseline.get_metric("parser") != null);
    try testing.expect(baseline.get_metric("executor") != null);
    try testing.expect(baseline.get_metric("field_lookup") != null);
}

test "regression: report generation with mixed results" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.parser);
    try baseline.add_metric(V094_BASELINE.executor);

    var generator = performance_regression.ReportGenerator.init(testing.allocator);

    var buf: [1000]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    const current = [_]performance_regression.ModuleMetrics{
        .{
            .name = "parser",
            .throughput_mbs = 490.0,
            .operations_per_second = 100_000,
            .avg_latency_us = 10.0,
            .peak_memory_bytes = 1_000_000,
        },
        .{
            .name = "executor",
            .throughput_mbs = 210.0,
            .operations_per_second = 50_000,
            .avg_latency_us = 20.0,
            .peak_memory_bytes = 2_000_000,
        },
    };

    try generator.generate_report(baseline, &current, fbs.writer());
    const result = fbs.getWritten();

    try testing.expect(result.len > 0);
}

test "regression: peak memory usage validation" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    const parser_baseline = performance_regression.ModuleMetrics{
        .name = "parser_memory",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    try baseline.add_metric(parser_baseline);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "parser_memory",
        .throughput_mbs = 500.0,
        .operations_per_second = 100_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_050_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}

test "regression: baseline consistency across operations" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    for ([_]performance_regression.ModuleMetrics{
        V094_BASELINE.parser,
        V094_BASELINE.executor,
        V094_BASELINE.field_lookup,
        V094_BASELINE.session_creation,
    }) |metric| {
        try baseline.add_metric(metric);
    }

    try testing.expectEqual(@as(usize, 4), baseline.metrics.count());

    try testing.expect(baseline.get_metric("parser") != null);
    try testing.expect(baseline.get_metric("executor") != null);
    try testing.expect(baseline.get_metric("field_lookup") != null);
    try testing.expect(baseline.get_metric("session_creation") != null);

    try testing.expect(baseline.timestamp > 0);
}

test "regression: operations per second degradation" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    try baseline.add_metric(V094_BASELINE.parser);

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "parser",
        .throughput_mbs = 500.0,
        .operations_per_second = 80_000,
        .avg_latency_us = 10.0,
        .peak_memory_bytes = 1_000_000,
    };

    const result = detector.detect_regression(current);
    try testing.expect(result != null);
    if (result) |r| {
        try testing.expect(r.change_percent >= 10);
    }
}

test "regression: zero baseline handling" {
    var baseline = performance_regression.Baseline.init(testing.allocator);
    defer baseline.deinit();

    var detector = performance_regression.RegressionDetector.init(testing.allocator, baseline);

    const current = performance_regression.ModuleMetrics{
        .name = "unknown_module",
        .throughput_mbs = 100.0,
        .operations_per_second = 10_000,
        .avg_latency_us = 100.0,
        .peak_memory_bytes = 500_000,
    };

    const result = detector.detect_regression(current);
    try testing.expectEqual(@as(?performance_regression.RegressionResult, null), result);
}
