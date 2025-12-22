# OpenTelemetry Integration Guide

zig-3270 includes comprehensive OpenTelemetry (OTEL) support for distributed tracing, metrics collection, and structured logging.

## Quick Start

### 1. Setup OTEL Collector

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: localhost:4318
      grpc:
        endpoint: localhost:4317

processors:
  batch:
    timeout: 10s
    send_batch_size: 1024

exporters:
  jaeger:
    endpoint: http://localhost:14250
  prometheus:
    endpoint: "0.0.0.0:8888"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

### 2. Using Tracer in Zig Code

```zig
const opentelemetry = @import("opentelemetry");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create tracer
    var tracer = try opentelemetry.Tracer.init(allocator, "zig-3270");
    defer tracer.deinit();

    // Start a span
    const span = try tracer.start_span("connect_to_mainframe");
    defer span.end();

    try span.set_attribute("host", opentelemetry.SpanAttribute{ 
        .string = "mainframe.example.com" 
    });
    try span.set_attribute("port", opentelemetry.SpanAttribute{ 
        .int = 23 
    });

    // Do work...
    try span.add_event("connection_established");

    span.status = opentelemetry.SpanStatus.Ok;
}
```

### 3. Using Meter for Metrics

```zig
var meter = try opentelemetry.Meter.init(allocator, "zig-3270");
defer meter.deinit();

// Create metrics
try meter.create_counter("connection_attempts");
try meter.create_gauge("active_connections");
try meter.create_histogram("command_latency_ms");

// Record metrics
meter.increment_counter("connection_attempts");
meter.set_gauge("active_connections", 42.0);
try meter.record_histogram("command_latency_ms", 125.5);
```

## Tracing Architecture

### Trace Context

Each trace has:
- **Trace ID**: 128-bit unique identifier for entire distributed trace
- **Span ID**: 64-bit identifier for individual operation
- **Trace Flags**: Sampling and debug flags
- **W3C Format**: `00-{traceId}-{spanId}-{traceFlags}`

### Span Lifecycle

```
Span.start()
  ├─ set_attribute(key, value)
  ├─ add_event(name)
  └─ Span.end()
```

### Span Types

- **Root Span**: Initiated by client
- **Child Span**: Created within parent span
- **Link**: Cross-reference to other traces

## Metrics

### Counter (Monotonically Increasing)

```zig
try meter.create_counter("requests_total");
meter.increment_counter("requests_total");
meter.add(meter.counters.get("requests_total"), 10);
```

### Gauge (Can Increase/Decrease)

```zig
try meter.create_gauge("memory_usage_bytes");
meter.set_gauge("memory_usage_bytes", 1024.0 * 1024.0); // 1MB
```

### Histogram (Distribution)

```zig
try meter.create_histogram("latency_ms");
try meter.record_histogram("latency_ms", 42.5);

// Get statistics
const histogram = meter.histograms.get("latency_ms").?;
const mean = histogram.mean();
const p95 = histogram.percentile(0.95);
const p99 = histogram.percentile(0.99);
```

## Export Formats

### OTLP JSON

```zig
var file = try std.fs.cwd().createFile("traces.json", .{});
defer file.close();

try opentelemetry.export_spans_json(allocator, &tracer, file.writer());
```

Output format:
```json
{
  "resourceSpans": [{
    "resource": {
      "attributes": [{
        "key": "service.name",
        "value": { "stringValue": "zig-3270" }
      }]
    },
    "scopeSpans": [{
      "spans": [{
        "traceId": "4bf92f3577b34da6a3ce929d0e0e4736",
        "spanId": "00f067aa0ba902b7",
        "name": "connect_to_mainframe",
        "startTimeUnixNano": 1701432000000000000,
        "endTimeUnixNano": 1701432001000000000,
        "status": { "code": 1 },
        "attributes": [...]
      }]
    }]
  }]
}
```

## Integration with Observability Stack

### Jaeger (Distributed Tracing)

1. Deploy Jaeger:
```bash
docker run -d --name jaeger \
  -e COLLECTOR_OTLP_ENABLED=true \
  -p 4317:4317 \
  -p 16686:16686 \
  jaegertracing/all-in-one:latest
```

2. Export spans to Jaeger:
```zig
// Tracer will send to OTEL collector at localhost:4317
// Collector forwards to Jaeger at http://localhost:14250
```

3. View traces at http://localhost:16686

### Prometheus (Metrics)

1. Deploy Prometheus:
```yaml
# prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'zig-3270'
    static_configs:
      - targets: ['localhost:8888']  # OTEL metrics endpoint
```

2. Query metrics:
```
rate(requests_total[1m])           # RPS
active_connections                 # Current connections
histogram_quantile(0.95, latency_ms) # P95 latency
```

### Grafana (Visualization)

1. Add Prometheus datasource
2. Create dashboard panels:

```
Panel 1: Throughput
Query: rate(requests_total[1m])

Panel 2: Active Connections
Query: active_connections

Panel 3: Latency Percentiles
Query 1: histogram_quantile(0.50, latency_ms) as p50
Query 2: histogram_quantile(0.95, latency_ms) as p95
Query 3: histogram_quantile(0.99, latency_ms) as p99
```

## Standard Metrics

### Connection Metrics

- `tn3270.connection.attempts` (Counter): Total connection attempts
- `tn3270.connection.active` (Gauge): Active connections
- `tn3270.connection.failures` (Counter): Failed connections
- `tn3270.connection.latency_ms` (Histogram): Connection time

### Protocol Metrics

- `tn3270.command.received` (Counter): Commands received
- `tn3270.command.sent` (Counter): Commands sent
- `tn3270.command.latency_ms` (Histogram): Command execution time
- `tn3270.parse.errors` (Counter): Parse errors

### Field Metrics

- `tn3270.field.count` (Gauge): Current field count
- `tn3270.field.updates` (Counter): Field updates
- `tn3270.field.lookups` (Counter): Field lookups

### Memory Metrics

- `tn3270.memory.allocations` (Counter): Total allocations
- `tn3270.memory.deallocations` (Counter): Total deallocations
- `tn3270.memory.peak_bytes` (Gauge): Peak memory usage

## Best Practices

### 1. Sampling

For high-throughput applications, sample traces:

```zig
// Sample 1% of traces
if (tracer.current_context.trace_flags & 0x01) == 0 {
    // Skip this trace
}
```

### 2. Context Propagation

For distributed systems, propagate context:

```zig
// Get W3C Trace Context
const traceparent = tracer.current_context.format_w3c();

// Send as HTTP header in outgoing requests
// Traceparent: {formatted}
```

### 3. Attribute Guidelines

- Use lowercase keys with underscores: `http.status_code`
- Keep values concise: avoid large blobs
- Use semantic conventions: https://opentelemetry.io/docs/specs/semconv/

Good:
```zig
try span.set_attribute("http.method", .{ .string = "POST" });
try span.set_attribute("http.status_code", .{ .int = 200 });
try span.set_attribute("user.id", .{ .int = 12345 });
```

Bad:
```zig
try span.set_attribute("everything", .{ .string = "entire JSON object..." });
```

### 4. Error Tracking

```zig
try span.set_attribute("error.type", .{ .string = "ConnectionError" });
try span.set_attribute("error.message", .{ .string = error_msg });
span.status = opentelemetry.SpanStatus.Error;
```

## Performance Considerations

### Memory

- Spans: ~500 bytes each (excluding attributes)
- Metrics: ~1KB per metric definition
- Attributes: ~100 bytes per attribute

### CPU

- Span creation: <100ns
- Metric recording: <1µs
- Exporting: Batched to minimize overhead

### Recommendations

- Batch exports (default: 1024 spans or 10 seconds)
- Sample high-volume traces (1-10%)
- Export to local collector (not over WAN)

## Troubleshooting

### No Traces Appearing in Jaeger

1. Check OTEL collector is running: `curl localhost:4317`
2. Verify collector configuration is correct
3. Check Jaeger UI at http://localhost:16686
4. Look for errors in collector logs

### High Memory Usage

1. Increase batch size in collector
2. Enable sampling in tracer
3. Reduce attribute cardinality
4. Export more frequently

### Missing Metrics

1. Verify meter metrics are created before use
2. Check prometheus scrape configuration
3. Wait for scrape interval (default 15s)
4. Verify endpoint is accessible

## Migration from debug_log

If using `debug_log` module, migrate to OTEL:

```zig
// Old way
debug_log.info("event", "Connected to mainframe");

// New way
const span = try tracer.start_span("mainframe_connection");
try span.add_event("connected");
span.end();
```

## API Reference

See `src/opentelemetry.zig` for complete API documentation.

## External Resources

- [OpenTelemetry Docs](https://opentelemetry.io/docs/)
- [OTLP Specification](https://opentelemetry.io/docs/specs/otlp/)
- [Jaeger Documentation](https://www.jaegertracing.io/docs/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [Grafana Docs](https://grafana.com/docs/)

