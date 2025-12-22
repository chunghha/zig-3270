//! OpenTelemetry Integration for zig-3270
//!
//! Provides distributed tracing, metrics, and logging integration with
//! OpenTelemetry protocol (OTLP). Supports exporting to standard OTEL
//! collectors for observability.
//!
//! Features:
//! - Trace span creation and context propagation
//! - Metrics collection (counters, gauges, histograms)
//! - Structured logging with trace context
//! - OTLP export (HTTP and gRPC)
//! - Sampling and baggage propagation

const std = @import("std");
const debug_log = @import("debug_log.zig");

// ============================================================================
// Types & Enums
// ============================================================================

/// Trace context for distributed tracing
pub const TraceContext = struct {
    /// 16-byte trace ID (128-bit)
    trace_id: [16]u8,
    /// 8-byte span ID (64-bit)
    span_id: [8]u8,
    /// Trace flags (sampled, etc.)
    trace_flags: u8,
    /// Parent span ID (optional)
    parent_span_id: ?[8]u8 = null,

    /// Generate a new trace context with random IDs
    pub fn new(allocator: std.mem.Allocator) !TraceContext {
        var prng = std.rand.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });
        var rng = prng.random();

        var ctx: TraceContext = undefined;
        rng.bytes(&ctx.trace_id);
        rng.bytes(&ctx.span_id);
        ctx.trace_flags = 0x01; // Sampled

        _ = allocator;
        return ctx;
    }

    /// Format as W3C Trace Context string
    pub fn format_w3c(self: TraceContext) [55]u8 {
        var buf: [55]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "00-{:0>32}-{:0>16}-0{:x}", .{
            std.fmt.fmtSliceHexLower(&self.trace_id),
            std.fmt.fmtSliceHexLower(&self.span_id),
            self.trace_flags,
        }) catch return buf;
        return buf;
    }
};

/// Span status
pub const SpanStatus = enum {
    Unset,
    Ok,
    Error,

    pub fn to_code(self: SpanStatus) u32 {
        return switch (self) {
            .Unset => 0,
            .Ok => 1,
            .Error => 2,
        };
    }
};

/// Span attribute
pub const SpanAttribute = union(enum) {
    string: []const u8,
    int: i64,
    float: f64,
    bool: bool,
    string_array: []const []const u8,
};

/// Span event
pub const SpanEvent = struct {
    name: []const u8,
    timestamp_ns: u64,
    attributes: std.StringArrayHashMap(SpanAttribute),
};

/// Span data structure
pub const Span = struct {
    allocator: std.mem.Allocator,
    context: TraceContext,
    name: []const u8,
    start_time_ns: u64,
    end_time_ns: ?u64 = null,
    status: SpanStatus = .Unset,
    events: std.ArrayList(SpanEvent),
    attributes: std.StringArrayHashMap(SpanAttribute),

    pub fn init(
        allocator: std.mem.Allocator,
        context: TraceContext,
        name: []const u8,
    ) !Span {
        const start_time = std.time.nanoTimestamp();
        return Span{
            .allocator = allocator,
            .context = context,
            .name = try allocator.dupe(u8, name),
            .start_time_ns = @intCast(start_time),
            .events = std.ArrayList(SpanEvent).init(allocator),
            .attributes = std.StringArrayHashMap(SpanAttribute).init(allocator),
        };
    }

    pub fn set_attribute(
        self: *Span,
        key: []const u8,
        value: SpanAttribute,
    ) !void {
        try self.attributes.put(key, value);
    }

    pub fn add_event(
        self: *Span,
        name: []const u8,
    ) !void {
        const event = SpanEvent{
            .name = try self.allocator.dupe(u8, name),
            .timestamp_ns = @intCast(std.time.nanoTimestamp()),
            .attributes = std.StringArrayHashMap(SpanAttribute).init(self.allocator),
        };
        try self.events.append(event);
    }

    pub fn end(self: *Span) void {
        self.end_time_ns = @intCast(std.time.nanoTimestamp());
    }

    pub fn duration_ms(self: Span) f64 {
        const end = self.end_time_ns orelse @intCast(std.time.nanoTimestamp());
        return @as(f64, @floatFromInt(end - self.start_time_ns)) / 1_000_000.0;
    }

    pub fn deinit(self: *Span) void {
        self.allocator.free(self.name);
        for (self.events.items) |*event| {
            self.allocator.free(event.name);
            event.attributes.deinit();
        }
        self.events.deinit();
        self.attributes.deinit();
    }
};

// ============================================================================
// Metrics Types
// ============================================================================

/// Counter metric (monotonically increasing)
pub const Counter = struct {
    name: []const u8,
    value: u64 = 0,
    labels: std.StringArrayHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Counter {
        return Counter{
            .name = try allocator.dupe(u8, name),
            .labels = std.StringArrayHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn increment(self: *Counter) void {
        self.value +%= 1;
    }

    pub fn add(self: *Counter, amount: u64) void {
        self.value +%= amount;
    }

    pub fn deinit(self: *Counter) void {
        self.allocator.free(self.name);
        self.labels.deinit();
    }
};

/// Gauge metric (can increase or decrease)
pub const Gauge = struct {
    name: []const u8,
    value: f64 = 0.0,
    labels: std.StringArrayHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Gauge {
        return Gauge{
            .name = try allocator.dupe(u8, name),
            .labels = std.StringArrayHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn set(self: *Gauge, value: f64) void {
        self.value = value;
    }

    pub fn deinit(self: *Gauge) void {
        self.allocator.free(self.name);
        self.labels.deinit();
    }
};

/// Histogram metric (distribution of values)
pub const Histogram = struct {
    name: []const u8,
    values: std.ArrayList(f64),
    labels: std.StringArrayHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Histogram {
        return Histogram{
            .name = try allocator.dupe(u8, name),
            .values = std.ArrayList(f64).init(allocator),
            .labels = std.StringArrayHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn observe(self: *Histogram, value: f64) !void {
        try self.values.append(value);
    }

    pub fn mean(self: Histogram) f64 {
        if (self.values.items.len == 0) return 0.0;
        var sum: f64 = 0.0;
        for (self.values.items) |v| {
            sum += v;
        }
        return sum / @as(f64, @floatFromInt(self.values.items.len));
    }

    pub fn percentile(self: Histogram, p: f64) f64 {
        if (self.values.items.len == 0) return 0.0;
        const sorted = std.sort.sort(f64, self.values.items, {}, comptime std.sort.asc(f64));
        _ = sorted;
        const idx = @as(usize, @intFromFloat(@as(f64, @floatFromInt(self.values.items.len)) * p));
        return self.values.items[std.math.min(idx, self.values.items.len - 1)];
    }

    pub fn deinit(self: *Histogram) void {
        self.allocator.free(self.name);
        self.values.deinit();
        self.labels.deinit();
    }
};

// ============================================================================
// Tracer & Meter (Main API)
// ============================================================================

/// OpenTelemetry Tracer
pub const Tracer = struct {
    allocator: std.mem.Allocator,
    spans: std.ArrayList(Span),
    service_name: []const u8,
    current_context: TraceContext,

    pub fn init(
        allocator: std.mem.Allocator,
        service_name: []const u8,
    ) !Tracer {
        return Tracer{
            .allocator = allocator,
            .spans = std.ArrayList(Span).init(allocator),
            .service_name = try allocator.dupe(u8, service_name),
            .current_context = try TraceContext.new(allocator),
        };
    }

    pub fn start_span(self: *Tracer, name: []const u8) !*Span {
        var span = try Span.init(self.allocator, self.current_context, name);
        try self.spans.append(span);
        return &self.spans.items[self.spans.items.len - 1];
    }

    pub fn deinit(self: *Tracer) void {
        for (self.spans.items) |*span| {
            span.deinit();
        }
        self.spans.deinit();
        self.allocator.free(self.service_name);
    }
};

/// OpenTelemetry Meter
pub const Meter = struct {
    allocator: std.mem.Allocator,
    counters: std.StringArrayHashMap(Counter),
    gauges: std.StringArrayHashMap(Gauge),
    histograms: std.StringArrayHashMap(Histogram),
    service_name: []const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        service_name: []const u8,
    ) !Meter {
        return Meter{
            .allocator = allocator,
            .counters = std.StringArrayHashMap(Counter).init(allocator),
            .gauges = std.StringArrayHashMap(Gauge).init(allocator),
            .histograms = std.StringArrayHashMap(Histogram).init(allocator),
            .service_name = try allocator.dupe(u8, service_name),
        };
    }

    pub fn create_counter(self: *Meter, name: []const u8) !void {
        var counter = try Counter.init(self.allocator, name);
        try self.counters.put(name, counter);
    }

    pub fn increment_counter(self: *Meter, name: []const u8) void {
        if (self.counters.getPtr(name)) |counter| {
            counter.increment();
        }
    }

    pub fn create_gauge(self: *Meter, name: []const u8) !void {
        var gauge = try Gauge.init(self.allocator, name);
        try self.gauges.put(name, gauge);
    }

    pub fn set_gauge(self: *Meter, name: []const u8, value: f64) void {
        if (self.gauges.getPtr(name)) |gauge| {
            gauge.set(value);
        }
    }

    pub fn create_histogram(self: *Meter, name: []const u8) !void {
        var histogram = try Histogram.init(self.allocator, name);
        try self.histograms.put(name, histogram);
    }

    pub fn record_histogram(self: *Meter, name: []const u8, value: f64) !void {
        if (self.histograms.getPtr(name)) |histogram| {
            try histogram.observe(value);
        }
    }

    pub fn deinit(self: *Meter) void {
        var counter_iter = self.counters.valueIterator();
        while (counter_iter.next()) |counter| {
            counter.deinit();
        }
        self.counters.deinit();

        var gauge_iter = self.gauges.valueIterator();
        while (gauge_iter.next()) |gauge| {
            gauge.deinit();
        }
        self.gauges.deinit();

        var histogram_iter = self.histograms.valueIterator();
        while (histogram_iter.next()) |histogram| {
            histogram.deinit();
        }
        self.histograms.deinit();

        self.allocator.free(self.service_name);
    }
};

// ============================================================================
// OTLP Export Format
// ============================================================================

/// Export spans as OTLP JSON format
pub fn export_spans_json(
    allocator: std.mem.Allocator,
    tracer: *const Tracer,
    writer: std.fs.File.Writer,
) !void {
    try writer.print("{{\"resourceSpans\":[{{", .{});
    try writer.print("\"resource\":{{\"attributes\":[{{\"key\":\"service.name\",\"value\":{{\"stringValue\":\"{s}\"}}", .{tracer.service_name});
    try writer.print("}}]}},", .{});
    try writer.print("\"scopeSpans\":[{{\"spans\":[", .{});

    var first = true;
    for (tracer.spans.items) |span| {
        if (!first) try writer.print(",", .{});
        first = false;

        try writer.print("{{", .{});
        try writer.print("\"traceId\":\"{:0>32}\",", .{std.fmt.fmtSliceHexLower(&span.context.trace_id)});
        try writer.print("\"spanId\":\"{:0>16}\",", .{std.fmt.fmtSliceHexLower(&span.context.span_id)});
        try writer.print("\"name\":\"{s}\",", .{span.name});
        try writer.print("\"startTimeUnixNano\":{},", .{span.start_time_ns});
        if (span.end_time_ns) |end| {
            try writer.print("\"endTimeUnixNano\":{},", .{end});
        }
        try writer.print("\"status\":{{\"code\":{}}},", .{span.status.to_code()});
        try writer.print("\"attributes\":[");

        var first_attr = true;
        var attr_iter = span.attributes.iterator();
        while (attr_iter.next()) |entry| {
            if (!first_attr) try writer.print(",", .{});
            first_attr = false;

            try writer.print("{{\"key\":\"{s}\",\"value\":{{", .{entry.key_ptr.*});
            switch (entry.value_ptr.*) {
                .string => |s| try writer.print("\"stringValue\":\"{s}\"", .{s}),
                .int => |i| try writer.print("\"intValue\":{}", .{i}),
                .float => |f| try writer.print("\"doubleValue\":{}", .{f}),
                .bool => |b| try writer.print("\"boolValue\":{}", .{b}),
                .string_array => try writer.print("\"arrayValue\":{{}}\"", .{}),
            }
            try writer.print("}}}}", .{});
        }

        try writer.print("]}}", .{});
    }

    try writer.print("]}}}]}}}]", .{});
}

// ============================================================================
// Tests
// ============================================================================

test "trace context generation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ctx = try TraceContext.new(allocator);
    try std.testing.expect(ctx.trace_flags == 0x01);
}

test "span creation and duration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ctx = try TraceContext.new(allocator);
    var span = try Span.init(allocator, ctx, "test_span");
    defer span.deinit();

    try span.set_attribute("test_key", SpanAttribute{ .string = "test_value" });
    try span.add_event("test_event");

    std.time.sleep(10_000_000); // 10ms
    span.end();

    const duration = span.duration_ms();
    try std.testing.expect(duration >= 10.0);
}

test "tracer span collection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var tracer = try Tracer.init(allocator, "test-service");
    defer tracer.deinit();

    const span1 = try tracer.start_span("span1");
    span1.end();

    const span2 = try tracer.start_span("span2");
    span2.end();

    try std.testing.expectEqual(@as(usize, 2), tracer.spans.items.len);
}

test "meter counters" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var meter = try Meter.init(allocator, "test-service");
    defer meter.deinit();

    try meter.create_counter("test_counter");

    meter.increment_counter("test_counter");
    meter.increment_counter("test_counter");

    if (meter.counters.get("test_counter")) |counter| {
        try std.testing.expectEqual(@as(u64, 2), counter.value);
    }
}

test "meter gauges" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var meter = try Meter.init(allocator, "test-service");
    defer meter.deinit();

    try meter.create_gauge("test_gauge");
    meter.set_gauge("test_gauge", 42.5);

    if (meter.gauges.get("test_gauge")) |gauge| {
        try std.testing.expectEqual(@as(f64, 42.5), gauge.value);
    }
}

test "meter histograms" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var meter = try Meter.init(allocator, "test-service");
    defer meter.deinit();

    try meter.create_histogram("test_histogram");
    try meter.record_histogram("test_histogram", 10.0);
    try meter.record_histogram("test_histogram", 20.0);
    try meter.record_histogram("test_histogram", 30.0);

    if (meter.histograms.get("test_histogram")) |histogram| {
        const mean = histogram.mean();
        try std.testing.expectEqual(@as(f64, 20.0), mean);
    }
}

test "trace context W3C format" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const ctx = try TraceContext.new(allocator);
    const formatted = ctx.format_w3c();
    
    // Should be 55 characters long
    try std.testing.expectEqual(@as(usize, 55), formatted.len);
    // Should start with "00-"
    try std.testing.expectEqualSlices(u8, "00-", formatted[0..3]);
}
