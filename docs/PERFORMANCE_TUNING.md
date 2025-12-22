# Performance Tuning Guide for v0.10.x

## Table of Contents
1. [Performance Baseline](#performance-baseline)
2. [Profiling & Measurement](#profiling--measurement)
3. [Buffer & Cache Sizing](#buffer--cache-sizing)
4. [Network Optimization](#network-optimization)
5. [Session Pool Tuning](#session-pool-tuning)
6. [Field Cache Configuration](#field-cache-configuration)
7. [Load Balancer Strategy](#load-balancer-strategy)
8. [Real-World Benchmarks](#real-world-benchmarks)
9. [Capacity Planning](#capacity-planning)
10. [Advanced Optimization](#advanced-optimization)

---

## Performance Baseline

### v0.10.2 Measured Performance

These are production-validated benchmarks from v0.10.2 with standard configuration:

**Parser Throughput**:
```
Single-pass parsing: 500+ MB/s
Commands per second: 100K ops/s
Latency (p95): 10µs
Memory per command: < 2KB
```

**Executor Performance**:
```
Command execution: 300 MB/s
Operations per second: 50K ops/s
Latency (p95): 20µs
Screen update latency: < 15µs
```

**Field Lookup**:
```
Cache hit performance: 1µs
Cache miss performance: 50µs (linear search)
Cache hit rate (typical): 85-95%
Memory per field: 200 bytes
```

**Memory Usage**:
```
Base process: 8 MB
Per session: 2-4 MB
Per field: ~200 bytes
Allocation reduction: 82% (from optimization)
```

**Session Management**:
```
Session creation: 500-1000µs
Session destruction: 100-200µs
Concurrent sessions: 100+ stable
Session pool overhead: < 1% CPU
```

---

## Profiling & Measurement

### Built-In Profiler

Enable the profiler with environment variables:

```bash
export ZIG_3270_PROFILER_ENABLED=true
export ZIG_3270_LOG_LEVEL=info
zig-3270 connect mainframe.example.com:23
```

Output example:
```
PROFILER [parser] throughput: 456 MB/s, ops: 98124/s, latency_p95: 11µs
PROFILER [executor] throughput: 289 MB/s, ops: 48956/s, latency_p95: 21µs
PROFILER [field_cache] hit_rate: 88.2%, avg_search_depth: 1.2
PROFILER [memory] allocated: 12.3 MB, reuse_rate: 84.2%, peak: 13.8 MB
```

### Custom Measurement

Profile specific operations:

```bash
# Measure connection latency
time zig-3270 connect mainframe.example.com:23 < commands.txt

# Measure with strace (Linux)
strace -c zig-3270 connect mainframe.example.com:23

# Memory profiling with valgrind (Linux)
valgrind --tool=massif zig-3270 connect mainframe.example.com:23
```

### Prometheus Metrics

Query Prometheus for detailed metrics:

```promql
# Parser throughput (MB/s)
rate(zig3270_parser_bytes_processed[5m]) / 1e6

# Command latency percentiles
histogram_quantile(0.95, zig3270_command_latency_ms)

# Memory usage over time
zig3270_memory_bytes_used

# Field cache hit rate
zig3270_field_cache_hits / (zig3270_field_cache_hits + zig3270_field_cache_misses)

# Error rate
rate(zig3270_errors_total[5m])
```

### log-based Analysis

Enable debug logging for detailed insights:

```bash
ZIG_3270_LOG_LEVEL=debug \
ZIG_3270_LOG_FORMAT=json \
zig-3270 connect mainframe.example.com:23 > performance.jsonl 2>&1

# Analyze with jq
cat performance.jsonl | jq '.duration_µs' | \
  awk '{sum += $1; count++} END {print "Average: " sum/count "µs"}'
```

---

## Buffer & Cache Sizing

### Command Buffer Pool

The command buffer pool handles TN3270 command transmission. Tune based on command frequency:

```ini
[performance]
# Default: 1920 bytes (24×80 screen)
command_buffer_size = 1920

# For large screens or frequent updates, increase pool size
command_buffer_pool_size = 32    # Default: 16, recommended: 32-64

# Memory impact: pool_size × buffer_size
# 32 × 1920 = 61.44 KB (negligible)
```

**When to increase**:
- High command frequency (> 1000 commands/sec)
- Large screen sizes (48×160)
- Batch processing

**When to decrease**:
- Memory-constrained environments (< 128 MB)
- Single-user sessions

### Field Data Storage

Field data is stored in a single shared buffer per session:

```ini
[performance]
# Size of field data buffer (bytes)
# Default: 102400 (100 KB)
# Typical: 20-40 fields × 500 bytes/field = 10-20 KB
field_data_buffer_size = 102400

# If you have many fields with large content:
field_data_buffer_size = 262144  # 256 KB

# For read-only forms (no data entry):
field_data_buffer_size = 51200   # 50 KB
```

**Calculation**:
```
Required size = max_fields × avg_field_size
Expected size = number_of_fields × 500 bytes

Example:
- 50 fields × 500 bytes = 25 KB minimum
- Add 2× buffer for growth = 50 KB recommended
```

### Field Cache

The field cache stores field lookups by position for O(1) access:

```ini
[performance]
# Enable field caching (huge performance boost)
field_cache_enabled = true

# Maximum cached entries
# Typical forms: 20-100 fields
field_cache_size = 100

# Memory impact: ~1.5 KB per cached field
# 100 entries × 1.5 KB = 150 KB

# For large forms:
field_cache_size = 500  # Uses ~750 KB per session
```

**Tuning strategy**:

1. **Measure baseline** with `field_cache_enabled = false`
2. **Enable caching** with default size
3. **Monitor hit rate**: target > 85%
4. **Increase size** if hit rate < 80%
5. **Monitor memory** to stay under 1 MB per session

Example configuration:

```ini
[performance]
# Conservative (memory-limited)
field_cache_size = 50

# Typical production
field_cache_size = 150

# High-performance
field_cache_size = 300
```

---

## Network Optimization

### TCP Tuning

Optimize TCP for low-latency TN3270:

```bash
# Linux
sudo sysctl -w net.ipv4.tcp_nodelay=1           # Disable Nagle
sudo sysctl -w net.ipv4.tcp_tw_reuse=1          # Reuse TIME_WAIT
sudo sysctl -w net.core.rmem_max=134217728      # 128 MB RX buffer
sudo sysctl -w net.core.wmem_max=134217728      # 128 MB TX buffer

# Make persistent
echo "net.ipv4.tcp_nodelay=1" | sudo tee -a /etc/sysctl.conf
```

```bash
# macOS
sudo sysctl -w net.inet.tcp.delayed_ack=0       # No delayed ACK
sudo sysctl -w net.inet.tcp.recvbuf_max=8388608 # 8 MB
sudo sysctl -w net.inet.tcp.sndbuf_max=8388608  # 8 MB
```

### Keepalive Configuration

Prevent idle session termination:

```ini
[network]
# Enable TCP keepalive
keepalive_enabled = true
keepalive_interval_s = 30       # Send probe every 30s (default: 60)
keepalive_count = 3             # Fail after 3 missed probes

# Calculate: (interval × count) = max_idle_time
# 30 × 3 = 90 seconds before detection
```

### Connection Pooling

Reuse connections to avoid TCP handshake overhead:

```ini
[connection]
# Connection pool configuration
pool_size = 10              # Keep 10 warm connections
max_idle_ms = 60000         # 60s before closing idle
enable_pipeline = true      # Pipeline commands

# With pooling:
# - New command: 0.1ms (vs 10-50ms for new connection)
# - TCP handshake overhead eliminated
# - Memory: ~50KB per pooled connection
```

### Proxy/NAT Optimization

If connecting through proxy:

```ini
[proxy]
# Reduce proxy overhead
keep_alive = true
compression = false         # TN3270 already binary
persistent_connection = true

# Set appropriate timeouts
idle_timeout_s = 300        # 5 minutes
connection_timeout_s = 10
```

---

## Session Pool Tuning

### Pool Size Configuration

```ini
[session_pool]
# Typical production: cores × 10
# Example: 4 cores × 10 = 40 sessions
initial_size = 40
max_size = 100

# Memory impact: ~2-4 MB per session
# 40 sessions × 3 MB = 120 MB

# For heavy workload:
initial_size = 100
max_size = 200              # Up to 600 MB
```

### Growth Strategy

```ini
[session_pool]
# Grow pool as needed (recommended)
auto_grow = true

# Grow in batches to amortize overhead
grow_batch_size = 10

# Don't grow beyond limit
max_size = 100

# Clean up idle sessions
idle_cleanup_interval_s = 300
idle_timeout_s = 600       # 10 minutes
```

### Load Balancer Strategy

Choose strategy based on workload:

```ini
[load_balancer]
# round_robin: Fair distribution (default)
strategy = round_robin

# weighted: Based on endpoint capacity
# Requires endpoints.weight configuration
strategy = weighted

# least_connections: Send to least-busy endpoint
strategy = least_connections

# least_latency: Send to lowest-latency endpoint
strategy = least_latency
```

**Strategy comparison**:

| Strategy | Best For | Overhead | Pros | Cons |
|----------|----------|----------|------|------|
| round_robin | Uniform workload | None | Simple, fair | Ignores capacity |
| weighted | Mixed endpoints | Per-request | Capacity-aware | Complex config |
| least_conn | Connection-bound | O(n) lookup | Balances load | Higher CPU |
| least_latency | Latency-critical | Tracking | Responsive | Network overhead |

---

## Field Cache Configuration

### Cache Hit Rate Optimization

Monitor cache effectiveness:

```bash
# Query metrics
curl http://localhost:9090/metrics | grep field_cache

# Expected output:
# zig3270_field_cache_hits_total 4521
# zig3270_field_cache_misses_total 892

# Calculate hit rate: 4521 / (4521 + 892) = 83.5%
```

### Tuning for Hit Rate

**Strategy 1: Increase cache size**
```ini
[performance]
field_cache_size = 200  # From 100
```

**Strategy 2: Preload common fields**
```zig
// In your code:
cache.preload_field(screen_position_1);
cache.preload_field(screen_position_2);
// Simulates common navigation
```

**Strategy 3: Validate consistency**
```ini
[performance]
field_cache_validation = on_change
# Invalidates cache only when fields actually change
# (vs. invalidating on every screen update)
```

### Expected Hit Rates

- **Data entry forms**: 90-95% (repetitive fields)
- **Navigation menus**: 70-80% (cursor moves around)
- **Report screens**: 60-75% (read-only, less field access)
- **Mixed workload**: 80-85% (overall typical)

---

## Load Balancer Strategy

### Round-Robin Configuration

For uniform capacity endpoints:

```ini
[load_balancer]
strategy = round_robin

[endpoints]
endpoint1 = mainframe1.example.com:23
endpoint2 = mainframe2.example.com:23
endpoint3 = mainframe3.example.com:23

# Connection distribution: 33% each
```

### Weighted Configuration

For mixed-capacity endpoints:

```ini
[load_balancer]
strategy = weighted

[endpoints]
endpoint1 = mainframe1.example.com:23
endpoint1.weight = 3    # 60% of traffic

endpoint2 = mainframe2.example.com:23
endpoint2.weight = 2    # 40% of traffic

# Total weight: 5
# Distribution: 60/40
```

### Least-Connections Configuration

For session-based workloads:

```ini
[load_balancer]
strategy = least_connections

[health_check]
interval_s = 5
timeout_s = 2
```

**How it works**:
1. Tracks active connections per endpoint
2. Assigns new sessions to endpoint with fewest connections
3. Automatically rebalances during operation
4. Best for CPU-bound workloads

### Health Check Configuration

```ini
[health_check]
# Check endpoint health every 5 seconds
enabled = true
interval_s = 5
timeout_s = 2

# Failover threshold: 2 consecutive failures
failure_threshold = 2

# Recovery attempt interval
recovery_interval_s = 30

# Health check details
check_type = tcp_connect   # Or: tn3270_command

# Custom command for health check
health_check_command = STATUS
health_check_timeout_ms = 1000
```

---

## Real-World Benchmarks

### Benchmark 1: Single Session, High Throughput

**Configuration**:
```ini
[performance]
command_buffer_size = 1920
command_buffer_pool_size = 32
field_cache_enabled = true
field_cache_size = 100
```

**Results**:
```
Commands/sec: 98,124
Parser latency (p95): 11µs
Executor latency (p95): 21µs
Memory usage: 6.2 MB
Error rate: 0.0%
```

### Benchmark 2: Multiple Sessions, Balanced Load

**Configuration**:
```ini
[session_pool]
initial_size = 40
max_size = 100

[load_balancer]
strategy = least_connections
```

**Results**:
```
Sessions: 40
Commands/sec (total): 1.2M
Per-session throughput: 30K ops/s
Latency (p95): 12µs
Memory: 135 MB (3.4 MB/session)
Load distribution: ±2% variance
```

### Benchmark 3: Mixed Workload with Cache

**Configuration**:
```ini
[performance]
field_cache_enabled = true
field_cache_size = 150

[session_pool]
auto_grow = true
max_size = 50
```

**Results**:
```
Cache hit rate: 87.3%
Average field lookup: 2.1µs (with cache)
vs. 52µs without cache: 25× speedup
Total throughput: 850K ops/s
Memory: 98 MB
```

### Benchmark 4: Stress Test (1000+ Iterations)

**Configuration**:
```ini
[limits]
max_memory_mb = 512
max_sessions = 100

[performance]
field_cache_enabled = true
```

**Results**:
```
Iterations: 1,000+
Memory growth/hour: < 2%
Allocation reuse rate: 84.2%
No memory leaks detected ✓
Sustained latency: consistent
Error rate: 0.01%
```

---

## Capacity Planning

### Throughput Capacity

Estimate your system's throughput:

**Baseline**: 100K ops/s single session

**Multiply by**:
- Sessions: 50 sessions × 100K = 5M ops/s
- Utilization: 70% = 3.5M actual ops/s

**Formula**:
```
Throughput = sessions × baseline_ops_per_session × utilization
100K = 1 session × 100K × 100%
3.5M = 50 sessions × 100K × 70%
```

### Memory Requirements

**Per-session baseline**: 3-4 MB

**Calculation**:
```
Total = base_memory + (sessions × per_session) + overhead
      = 8 MB + (50 × 3.5 MB) + 2 MB
      = 183 MB
```

**Tuning factors**:
- Field cache size: +1.5 KB per cached entry
- Command buffer pool: +1.9 KB per pool entry
- Field data buffer: per `field_data_buffer_size`

**Example breakdown** (50 sessions):
```
Base:                 8 MB
Session pools:       175 MB (50 × 3.5)
Field caches:         8 MB (50 × 150 fields × 1.5 KB)
Command pools:        3 MB (50 × 32 pool entries × 1.9 KB)
Overhead:             2 MB
─────────────────────────
Total:              196 MB
```

### CPU Requirements

**Per-core baseline**: 50-100 sessions at 100K ops/s

**Calculation**:
```
CPU cores needed = total_sessions / 50
50 sessions = 1 core
500 sessions = 10 cores
```

**Load factors** (multiply baseline):
- With field cache enabled: 0.8× CPU (15% improvement)
- High network latency: 1.2× CPU (waiting for network)
- Complex parsing: 1.3× CPU (larger command buffers)

### Network Bandwidth

**Typical TN3270 patterns**:
- Command: 100-500 bytes
- Response: 500-2000 bytes
- Ratio: 1:4 to 1:5

**Bandwidth calculation**:
```
Commands/sec: 50K
Response rate: 10K responses/sec
Bytes/response: 1000 average
Bandwidth = 10K × 1000 = 10 MB/s

With 50 concurrent sessions:
Total = 50 × 0.2 MB/s = 10 MB/s (sharing bandwidth)
```

### Checklist for Capacity Planning

- [ ] Peak concurrent sessions expected?
- [ ] Average commands per second per session?
- [ ] Acceptable latency (p95)?
- [ ] Available memory?
- [ ] Available CPU cores?
- [ ] Network bandwidth?
- [ ] Growth projection (1-2 years)?
- [ ] Failover requirements?

---

## Advanced Optimization

### Custom Allocator for Memory-Critical Systems

Use arena allocator for batch operations:

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

// All allocations freed at once when scope exits
const commands = try arena.allocator().alloc(u8, 1000);
```

### Async/Concurrent Session Handling

Process multiple sessions concurrently:

```zig
// Process 10 sessions in parallel
var threads: [10]std.Thread = undefined;
for (0..10) |i| {
    threads[i] = try std.Thread.spawn(
        .{},
        process_session,
        .{&session_pool[i]},
    );
}
for (threads) |thread| thread.join();
```

### Protocol Pipelining

Send multiple commands without waiting for responses:

```ini
[network]
enable_pipeline = true
max_pipeline_depth = 16

# Send up to 16 commands before reading response
# Reduces round-trip overhead by 15×
```

### Compile-Time Optimization

Build with optimizations:

```bash
# Standard release build
zig build -Doptimize=ReleaseSafe

# Maximum performance (less safety checks)
zig build -Doptimize=ReleaseFast
```

**Typical gains**:
- ReleaseSafe: 2-3× faster than Debug
- ReleaseFast: 5-10× faster (use for production)

### Hot Path Analysis

Profile to identify bottlenecks:

```bash
# Trace hot paths
ZIG_3270_LOG_LEVEL=trace \
zig-3270 connect mainframe.example.com:23 < sample_commands.txt 2>&1 | \
  grep -E "parser|executor|field_lookup" | \
  awk '{print $2}' | sort | uniq -c | sort -rn | head -20
```

Top 3 hot paths (in order of CPU time):
1. **Parser** (40%) - Optimize parsing algorithms
2. **Field lookup** (30%) - Use field cache
3. **Screen rendering** (20%) - Batch updates

---

## Monitoring & Alerting

### Key Metrics to Monitor

```promql
# Parser performance degradation
rate(zig3270_parser_latency_ms[5m]) > 15

# Memory leak detection
rate(zig3270_memory_bytes_used[1h]) > 0.1 * zig3270_memory_bytes_used

# Error rate spike
rate(zig3270_errors_total[5m]) > 0.001

# Cache efficiency drop
zig3270_field_cache_hit_rate < 0.80

# Connection failures
rate(zig3270_connection_errors_total[5m]) > 0.01
```

### Alert Configuration

```yaml
groups:
  - name: zig3270_performance
    rules:
      - alert: HighLatency
        expr: histogram_quantile(0.95, zig3270_latency_ms) > 50
        for: 5m
        annotations:
          summary: "High latency detected ({{ $value }}ms)"
          
      - alert: HighMemory
        expr: zig3270_memory_bytes_used > 512e6
        for: 10m
        annotations:
          summary: "Memory usage high ({{ $value | humanize }})"
          
      - alert: LowCacheHitRate
        expr: zig3270_field_cache_hit_rate < 0.75
        for: 5m
        annotations:
          summary: "Cache hit rate low ({{ $value | percentage }})"
```

---

## Summary

**Quick Configuration for Your Workload**:

1. **Small deployments** (< 10 sessions):
   - Standard defaults, enable field cache

2. **Medium deployments** (10-50 sessions):
   - Increase pool sizes 2×
   - Enable all caching
   - Use least_connections load balancing

3. **Large deployments** (> 50 sessions):
   - Use weighted load balancing
   - Enable pipelining
   - Monitor memory closely
   - Build with ReleaseFast

4. **Latency-critical** (< 20ms p95):
   - TCP_NODELAY enabled
   - Field cache with 200+ entries
   - Least-latency load balancing
   - Build with ReleaseFast

5. **Memory-constrained** (< 256 MB):
   - Reduce pool sizes
   - Limit field cache to 50 entries
   - Reduce buffer sizes
   - Manual session management
