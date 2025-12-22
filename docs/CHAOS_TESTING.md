# Chaos Engineering & Stress Testing (v0.11.1)

## Overview

Chaos testing framework enables fault injection testing to validate system resilience under adverse conditions. This guide covers 50+ chaos scenarios including network faults, resource exhaustion, and cascading failures.

## Philosophy

Chaos engineering validates system behavior under failure by intentionally injecting faults. Rather than hoping systems are resilient, we prove it through testing.

### Principles

1. **Controlled Disruption**: Inject failures in controlled test environment
2. **Hypothesis Testing**: Make predictions, then validate with chaos
3. **Graduated Intensity**: Start small, increase fault complexity
4. **Observation**: Measure recovery and system behavior
5. **Automation**: Repeatable tests for CI/CD integration

## Quick Start

### Basic Chaos Test

```zig
var coordinator = ChaosCoordinator.init(allocator, seed);
defer coordinator.deinit();

// Define fault scenario
const scenario = ChaosScenario{
    .name = "network_delay_500ms",
    .scenario_type = .network_delay,
    .probability = 1.0, // Always trigger
    .duration_ms = 500,
    .target_component = "network",
};

// Add and enable
try coordinator.add_scenario(scenario);
coordinator.enable();

// Run with fault active
var fault = try coordinator.maybe_inject_fault();
if (fault != null) {
    std.debug.print("Fault injected: {}\n", .{fault.?.name});
}

// Clean up expired faults
coordinator.clean_expired_faults();
```

## 50+ Chaos Scenarios

### Category: Network Faults (10 scenarios)

#### 1. Network Delay
```zig
.scenario_type = .network_delay,
.duration_ms = 100,
.target_component = "network",
```
**Impact**: Response time increase, timeout risk  
**Expected Behavior**: Requests complete but slower  
**Recovery**: Automatic when delay ends

#### 2. Packet Loss
```zig
.scenario_type = .packet_loss,
.probability = 0.1, // 10% loss
```
**Impact**: Incomplete commands, retries needed  
**Expected Behavior**: Retry mechanism engages  
**Recovery**: Exponential backoff then success

#### 3. Packet Corruption
```zig
.scenario_type = .packet_corruption,
```
**Impact**: Invalid data received  
**Expected Behavior**: Error detection, reconnect  
**Recovery**: New connection established

#### 4. Connection Timeout
```zig
.scenario_type = .connection_timeout,
.duration_ms = 5000,
```
**Impact**: Complete connection failure  
**Expected Behavior**: Failover to backup  
**Recovery**: Automatic reconnection

#### 5. Partial Packet
```zig
.scenario_type = .partial_packet,
```
**Impact**: Incomplete frame received  
**Expected Behavior**: Wait for rest or timeout  
**Recovery**: Reassembly or reconnect

#### 6. Duplicate Packet
```zig
.scenario_type = .duplicate_packet,
```
**Impact**: Duplicate processing  
**Expected Behavior**: Deduplication works  
**Recovery**: Idempotency ensures correctness

#### 7. Out-of-Order Packets
```zig
.scenario_type = .out_of_order_packets,
```
**Impact**: Resequencing required  
**Expected Behavior**: Buffer and reorder  
**Recovery**: Window-based ordering

#### 8. Zero-Byte Write
```zig
.scenario_type = .zero_byte_write,
```
**Impact**: No data sent  
**Expected Behavior**: Retry or timeout  
**Recovery**: Normal write succeeds

#### 9. Slow Read
```zig
.scenario_type = .slow_read,
.duration_ms = 1000,
```
**Impact**: Reading blocked  
**Expected Behavior**: Wait or timeout  
**Recovery**: I/O resumes normally

#### 10. Slow Write
```zig
.scenario_type = .slow_write,
.duration_ms = 1000,
```
**Impact**: Writing blocked  
**Expected Behavior**: Buffer fills or timeout  
**Recovery**: Writing resumes

### Category: Connection Faults (8 scenarios)

#### 11. Random Disconnect
```zig
.scenario_type = .random_disconnect,
```
**Impact**: Unexpected connection loss  
**Expected Behavior**: Detect loss, reconnect  
**Recovery**: Automatic reconnection

#### 12. Half-Open Connection
```zig
.scenario_type = .half_open_connection,
```
**Impact**: One direction works, other blocked  
**Expected Behavior**: Write succeeds, read hangs  
**Recovery**: Timeout triggers reconnect

#### 13. Reset Connection
```zig
.scenario_type = .reset_connection,
```
**Impact**: TCP RST received  
**Expected Behavior**: Immediate close  
**Recovery**: New connection

#### 14. Close Without Flush
```zig
.scenario_type = .close_without_flush,
```
**Impact**: Data loss on close  
**Expected Behavior**: Data may be lost  
**Recovery**: Application-level retries

#### 15. Rapid Reconnect
```zig
.scenario_type = .rapid_reconnect,
.duration_ms = 500,
```
**Impact**: Many disconnect/reconnect cycles  
**Expected Behavior**: Backoff prevents thundering herd  
**Recovery**: Exponential backoff prevents storm

#### 16. ACK Loss
```zig
.scenario_type = .ack_loss,
```
**Impact**: Sender doesn't know about successful sends  
**Expected Behavior**: Retransmits on timeout  
**Recovery**: Duplicate detection

#### 17. SYN Flood
```zig
.scenario_type = .syn_flood,
```
**Impact**: Connection queue exhaustion  
**Expected Behavior**: Some connections rejected  
**Recovery**: Rate limiting kicks in

#### 18. Slowloris Attack
```zig
.scenario_type = .slowloris_attack,
.duration_ms = 30000,
```
**Impact**: Server resources tied up  
**Expected Behavior**: Timeouts eventually trigger  
**Recovery**: Cleanup of stale connections

### Category: Protocol Faults (6 scenarios)

#### 19. Malformed Command
```zig
.scenario_type = .malformed_command,
```
**Impact**: Invalid protocol data  
**Expected Behavior**: Parser rejects  
**Recovery**: Error handling graceful

#### 20. Invalid Protocol State
```zig
.scenario_type = .invalid_protocol_state,
```
**Impact**: Unexpected command for current state  
**Expected Behavior**: State machine rejects  
**Recovery**: Reset to known state

#### 21. Buffer Overflow
```zig
.scenario_type = .buffer_overflow,
```
**Impact**: Data exceeds buffer  
**Expected Behavior**: Bounds checking prevents  
**Recovery**: Error handling

#### 22. Early Close
```zig
.scenario_type = .early_close,
```
**Impact**: Connection closed mid-command  
**Expected Behavior**: Incomplete command detection  
**Recovery**: Automatic reconnect

#### 23. Late Data Arrival
```zig
.scenario_type = .late_data_arrival,
```
**Impact**: Data arrives after timeout expected  
**Expected Behavior**: Ignore or buffer  
**Recovery**: New request sent

#### 24. TLS Handshake Failure
```zig
.scenario_type = .tls_handshake_failure,
```
**Impact**: Encryption negotiation fails  
**Expected Behavior**: Connection rejected  
**Recovery**: Retry or fallback

### Category: Resource Faults (8 scenarios)

#### 25. Memory Pressure
```zig
.scenario_type = .memory_pressure,
.duration_ms = 2000,
```
**Impact**: Low memory condition  
**Expected Behavior**: Graceful degradation  
**Recovery**: Memory freed, operation resumes

#### 26. CPU Spike
```zig
.scenario_type = .cpu_spike,
.duration_ms = 1000,
```
**Impact**: CPU busy  
**Expected Behavior**: Operations slower  
**Recovery**: CPU normalizes

#### 27. Disk I/O Blockage
```zig
.scenario_type = .disk_io_blockage,
.duration_ms = 3000,
```
**Impact**: Disk access blocked  
**Expected Behavior**: I/O timeouts  
**Recovery**: Disk I/O resumes

#### 28. File Descriptor Exhaustion
```zig
.scenario_type = .file_descriptor_exhaustion,
```
**Impact**: Can't open new files/sockets  
**Expected Behavior**: Operations fail  
**Recovery**: Cleanup enables new FDs

#### 29. Thread Starvation
```zig
.scenario_type = .thread_starvation,
```
**Impact**: All threads busy  
**Expected Behavior**: Tasks queue  
**Recovery**: Threads complete

#### 30. Lock Contention
```zig
.scenario_type = .lock_contention,
```
**Impact**: Mutex highly contested  
**Expected Behavior**: Serialization  
**Recovery**: Reduced contention

#### 31. Cache Invalidation
```zig
.scenario_type = .cache_invalidation,
```
**Impact**: Cached data becomes stale  
**Expected Behavior**: Refetch from source  
**Recovery**: New cache valid

#### 32. Out-of-Memory
```zig
.scenario_type = .out_of_memory,
```
**Impact**: Allocation fails  
**Expected Behavior**: Circuit breaker  
**Recovery**: Memory becomes available

### Category: Load Faults (8 scenarios)

#### 33. Concurrent Connections Spike
```zig
.scenario_type = .concurrent_connections_spike,
```
**Impact**: Sudden load increase  
**Expected Behavior**: Queue builds, then processed  
**Recovery**: Load balancer distributes

#### 34. Burst Traffic
```zig
.scenario_type = .burst_traffic,
```
**Impact**: High traffic for short time  
**Expected Behavior**: Buffer fills temporarily  
**Recovery**: Traffic normalizes

#### 35. Sustained High Load
```zig
.scenario_type = .sustained_high_load,
.duration_ms = 10000,
```
**Impact**: High traffic continuously  
**Expected Behavior**: Resources exhausted  
**Recovery**: Load reduction or scale up

#### 36. Bursty Loss
```zig
.scenario_type = .bursty_loss,
```
**Impact**: Loss comes in bursts not random  
**Expected Behavior**: Pattern-based retries  
**Recovery**: Backoff succeeds

#### 37. Correlated Loss
```zig
.scenario_type = .correlated_loss,
```
**Impact**: Related packets lost together  
**Expected Behavior**: Whole message lost  
**Recovery**: Full message retransmit

#### 38. Jitter Injection
```zig
.scenario_type = .jitter_injection,
```
**Impact**: Variable latency  
**Expected Behavior**: Adaptive timeouts  
**Recovery**: P95 latency tracking

#### 39. Asymmetric Latency
```zig
.scenario_type = .asymmetric_latency,
```
**Impact**: Upstream fast, downstream slow  
**Expected Behavior**: Backpressure  
**Recovery**: Flow control

#### 40. Reordering Window
```zig
.scenario_type = .reordering_window,
```
**Impact**: Packets reordered up to N  
**Expected Behavior**: Sequence buffering  
**Recovery**: Reordering tolerance

### Category: Cascading Failures (6 scenarios)

#### 41. Load Balancer Failure
```zig
.scenario_type = .load_balancer_failure,
```
**Impact**: No request distribution  
**Expected Behavior**: Direct to fallback  
**Recovery**: LB recovery

#### 42. Endpoint Flip
```zig
.scenario_type = .endpoint_flip,
```
**Impact**: Switched to different server  
**Expected Behavior**: Connection metadata changes  
**Recovery**: Reauth may be needed

#### 43. Slow Application Response
```zig
.scenario_type = .slow_application_response,
.duration_ms = 5000,
```
**Impact**: Server processing slow  
**Expected Behavior**: Timeout triggers  
**Recovery**: Retry succeeds

#### 44. Network Partition
```zig
.scenario_type = .network_partition,
.duration_ms = 10000,
```
**Impact**: Bi-directional communication fails  
**Expected Behavior**: Timeout detection  
**Recovery**: Automatic failover

#### 45. BGP Hijack Simulation
```zig
.scenario_type = .bgp_hijack_simulation,
```
**Impact**: Traffic routed wrong  
**Expected Behavior**: Health check fails  
**Recovery**: Fallback endpoint

#### 46. Session Affinity Violation
```zig
.scenario_type = .session_affinity_violation,
```
**Impact**: Routed to different server mid-session  
**Expected Behavior**: State mismatch  
**Recovery**: Reconnect to correct server

### Category: Software Faults (4 scenarios)

#### 47. Race Condition
```zig
.scenario_type = .race_condition,
```
**Impact**: Data corruption from concurrent access  
**Expected Behavior**: Prevented by locking  
**Recovery**: Automatic

#### 48. Stack Overflow
```zig
.scenario_type = .stack_overflow,
```
**Impact**: Stack exhaustion  
**Expected Behavior**: Crash prevented by ulimit  
**Recovery**: Process restart

#### 49. Clock Skew
```zig
.scenario_type = .clock_skew,
```
**Impact**: System clock changes  
**Expected Behavior**: Timeout recalculation  
**Recovery**: Timeout still works

#### 50. Certificate Expiry
```zig
.scenario_type = .certificate_expiry,
```
**Impact**: TLS cert expired  
**Expected Behavior**: TLS fails  
**Recovery**: Cert renewal

## Testing Framework

### Coordinator Pattern

```zig
var coordinator = ChaosCoordinator.init(allocator, seed);
defer coordinator.deinit();

// Add scenarios
try coordinator.add_scenario(scenario1);
try coordinator.add_scenario(scenario2);

// Enable/disable global switch
coordinator.enable();

// Trigger faults
if (try coordinator.maybe_inject_fault()) |fault| {
    // Fault injected, handle it
    std.debug.print("Handling: {}\n", .{fault.name});
}

// Monitor active faults
const active = coordinator.get_active_faults();
for (active) |fault| {
    // Track impact of active fault
}

// Cleanup expired faults
coordinator.clean_expired_faults();

// Get statistics
const stats = coordinator.get_stats();
std.debug.print("Triggered: {}, Recovered: {}\n", 
    .{stats.faults_triggered, stats.recovery_count});
```

### Simulator Pattern

```zig
var simulator = NetworkFaultSimulator.init(allocator, &coordinator);
defer simulator.deinit();

// Simulate sending (may fail, corrupt, delay)
const sent = try simulator.send_packet(data, "server");
if (!sent) {
    // Packet was dropped by fault injection
    std.debug.print("Packet dropped\n", .{});
}

// Simulate receiving
if (try simulator.receive_packet()) |packet| {
    process(packet);
}

// Check if timeout should occur
if (try simulator.simulate_timeout()) {
    // Timeout triggered by chaos
}
```

### Stress Test Pattern

```zig
var executor = StressTestExecutor.init(allocator, &coordinator);
defer executor.deinit();

for (scenarios) |scenario| {
    try executor.run_scenario(scenario);
}

executor.print_report();
const results = executor.get_results();
for (results) |result| {
    std.debug.print("[{}] {} - {}ms\n", 
        .{if (result.success) "PASS" else "FAIL", 
          result.scenario_name, result.duration_ms});
}
```

### Validator Pattern

```zig
var validator = ResilienceValidator.init(allocator);
defer validator.deinit();

// Record events during chaos test
try validator.checkpoint();

// Simulate fault recovery
std.posix.nanosleep(0, 100 * 1_000_000); // 100ms recovery

try validator.record_recovery_time(100);

// Validate SLA
if (validator.validate_sla(200)) { // 200ms max
    std.debug.print("SLA met\n", .{});
}

// Get metrics
const avg = validator.avg_recovery_time();
std.debug.print("Avg recovery: {d:.1}ms\n", .{avg});
```

## Test Scenarios by Use Case

### Scenario: Testing Auto-Failover

```zig
var coordinator = ChaosCoordinator.init(allocator, seed);
defer coordinator.deinit();

const scenarios = [_]ChaosScenario{
    // Primary endpoint fails
    .{ .name = "primary_down", .scenario_type = .connection_timeout, 
      .duration_ms = 5000, .target_component = "primary" },
    // Secondary responds
};

// Should automatically switch to secondary
// Validate with health checker
```

### Scenario: Testing Retry Logic

```zig
const scenarios = [_]ChaosScenario{
    // Transient packet loss
    .{ .name = "transient_loss", .scenario_type = .packet_loss,
      .probability = 0.05, .duration_ms = 1000 },
};

// Requests should succeed after retry
// Validate exponential backoff
```

### Scenario: Testing Memory Limits

```zig
const scenarios = [_]ChaosScenario{
    .{ .name = "memory_pressure", .scenario_type = .memory_pressure,
      .duration_ms = 10000 },
    .{ .name = "concurrent_spike", 
      .scenario_type = .concurrent_connections_spike },
};

// System should gracefully degrade
// No OOM crash
```

## Best Practices

### 1. Start Small

```zig
// First: Single fault
.probability = 1.0,
.duration_ms = 100,

// Then: Probabilistic
.probability = 0.1,
.duration_ms = 1000,
```

### 2. Measure Everything

```zig
const stats = coordinator.get_stats();
const validator_avg = validator.avg_recovery_time();

// Log for analysis
std.debug.print("Recovery: {d:.1}ms, SLA: {}\n",
    .{validator_avg, validator.validate_sla(200)});
```

### 3. Automate in CI/CD

```yaml
# CI test suite
- Test suite: Chaos scenarios (50 tests)
  - Each scenario: <5 seconds
  - Total: <4 minutes
  - Pass criteria: 100% recovery
```

### 4. Document Expectations

```zig
const scenario = ChaosScenario{
    .name = "network_delay_200ms",
    // Expected: Requests complete in 200-300ms
    // Recovery: Automatic after 200ms
    // SLA: <500ms max
    .scenario_type = .network_delay,
    .duration_ms = 200,
};
```

## Debugging Failures

### When a Chaos Test Fails

1. **Check Active Faults**
   ```zig
   const active = coordinator.get_active_faults();
   for (active) |fault| {
       std.debug.print("Active fault: {}\n", .{fault.scenario.name});
   }
   ```

2. **Check Statistics**
   ```zig
   const stats = coordinator.get_stats();
   std.debug.print("Triggered: {}, Recovery: {}\n",
       .{stats.faults_triggered, stats.recovery_count});
   ```

3. **Reproduce with Same Seed**
   ```zig
   // Use same seed for reproducibility
   var coordinator = ChaosCoordinator.init(allocator, 12345);
   ```

4. **Reduce Scope**
   ```zig
   // Test single scenario instead of all
   try executor.run_scenario(one_scenario);
   ```

## Performance Impact

Running chaos tests:
- Single scenario: <100ms overhead
- 50 scenarios: ~5 second test suite
- No impact on production (coordinator disabled by default)

## Integration with CI/CD

```yaml
test:
  - name: unit tests
    command: zig build test
  - name: chaos tests
    command: zig build chaos_test
    timeout: 10m
  - name: stress tests  
    command: zig build stress_test
    timeout: 30m
```

## See Also

- `docs/PERFORMANCE_TUNING.md` - Performance validation
- `docs/OPERATIONS.md` - Recovery procedures
- `src/chaos_testing.zig` - Implementation details
