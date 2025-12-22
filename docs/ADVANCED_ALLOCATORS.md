# Advanced Allocator Patterns (v0.11.1)

## Overview

Advanced allocators provide specialized memory management strategies for different performance requirements in the zig-3270 emulator. This guide covers three complementary allocator patterns designed to optimize memory usage in hot paths.

## Allocator Types

### 1. Ring Buffer Allocator

The ring buffer allocator implements a circular buffer with wraparound semantics, ideal for streaming data processing with bounded memory.

#### Features

- **Circular Buffer**: Fixed capacity with automatic wraparound
- **Bounded Memory**: No unbounded growth
- **Zero-Copy Peek**: View data without consuming
- **Wrap-Around Tracking**: Know when buffer cycles

#### Usage Pattern

```zig
var rb = try RingBufferAllocator.init(allocator, 4096);
defer rb.deinit();

// Write data (wraps automatically)
const bytes_written = try rb.write(data);

// Peek without consuming
const available = rb.available();
var out: [256]u8 = undefined;
const peeked = try rb.peek(&out);

// Read (consumes data)
const read_bytes = try rb.read(&out);
```

#### Performance Characteristics

- **Write**: O(1) amortized (may span wrap boundary)
- **Read**: O(1) amortized
- **Peek**: O(1) amortized
- **Space**: Fixed O(n) where n = capacity

#### Network I/O Use Case

Excellent for socket read buffers with high throughput:

```zig
// Ring buffer for socket reads
var socket_buffer = try RingBufferAllocator.init(allocator, 65536);

// Read from socket
const read = try socket.read(&socket_buffer.buffer);
_ = try socket_buffer.write(received_data);

// Process available data
while (socket_buffer.available() > 0) {
    const view = try socket_buffer.peek(&processing_buf);
    // Process view
    try socket_buffer.advance_read(processed_bytes);
}
```

### 2. Fixed Pool Allocator

The fixed pool allocator manages a pre-allocated pool of fixed-size blocks, eliminating allocation overhead for hot paths.

#### Features

- **Fixed-Size Blocks**: Identical block sizes for O(1) allocation
- **Pre-Allocated**: All blocks allocated at initialization
- **Zero Fragmentation**: Blocks are identical
- **Exhaustion Detection**: Clear error when pool full
- **Block Reuse Tracking**: Statistics on pool efficiency

#### Usage Pattern

```zig
var pool = try FixedPoolAllocator.init(allocator, 256, 100);
defer pool.deinit();

const block = try pool.allocate(); // O(1)
defer try pool.deallocate(block);

// Use block for temporary storage
std.mem.copy(u8, block, data);
```

#### Performance Characteristics

- **Allocate**: O(1) constant time
- **Deallocate**: O(1) constant time
- **Space**: Fixed O(n*m) where n=blocks, m=block_size
- **Hit Rate**: Tracks reuse statistics

#### Command Buffer Use Case

Perfect for command processing buffers:

```zig
// Pre-allocate 50 command buffers (1920 bytes each for 24x80 screen)
var cmd_pool = try FixedPoolAllocator.init(allocator, 1920, 50);

// In command loop
const cmd_buffer = try cmd_pool.allocate();
defer try cmd_pool.deallocate(cmd_buffer);

// Process command
executor.execute(cmd_buffer);
```

### 3. Scratch Allocator

The scratch allocator provides temporary allocation with reset semantics, perfect for per-frame or per-request allocations.

#### Features

- **Chunk-Based**: Allocates in configurable chunks (default 4KB)
- **Reset Semantics**: Clear all allocations with single reset
- **Automatic Expansion**: Handles allocations larger than chunk size
- **Peak Tracking**: Monitors maximum memory usage
- **Statistics**: Detailed usage metrics

#### Usage Pattern

```zig
var scratch = try ScratchAllocator.init(allocator);
defer scratch.deinit();

// Process frame 1
const buf1 = try scratch.alloc(128);
const buf2 = try scratch.alloc(256);

// When done with frame, reset for reuse
scratch.reset(); // All allocations become invalid

// Process frame 2 (reuses same chunks)
const buf3 = try scratch.alloc(100);
```

#### Performance Characteristics

- **Alloc**: O(1) amortized (bump pointer within chunk)
- **Reset**: O(1) amortized (pointer reset)
- **Space**: O(n) where n = total allocated
- **Peak Tracking**: Detailed metrics available

#### Frame Processing Use Case

Excellent for per-frame allocations:

```zig
// Main game loop equivalent
while (running) {
    defer scratch.reset(); // Auto-cleanup
    
    // Temporary per-frame allocations
    const frame_data = try scratch.alloc(1024);
    const parsed = try scratch.alloc(512);
    
    // Process screen update
    process_frame(frame_data);
}
```

## Memory Management Patterns

### Pattern 1: Bounded Streaming

Combine ring buffer + zero-copy parser for network streams:

```zig
var rb = try RingBufferAllocator.init(allocator, 65536);
defer rb.deinit();

// Read from network
const read_bytes = try socket.read(&temp_buf);
_ = try rb.write(temp_buf[0..read_bytes]);

// Parse without allocation
while (rb.available() > header_size) {
    var view: [256]u8 = undefined;
    const peeked = try rb.peek(&view);
    
    const msg_len = parse_header(view);
    if (peeked >= msg_len) {
        var msg: [256]u8 = undefined;
        _ = try rb.read(&msg);
        process_message(&msg);
    }
}
```

### Pattern 2: Command Pool + Scratch

Combine fixed pool for command buffers with scratch for temporaries:

```zig
var cmd_pool = try FixedPoolAllocator.init(allocator, 1920, 50);
var scratch = try ScratchAllocator.init(allocator);
defer cmd_pool.deinit();
defer scratch.deinit();

while (process_commands) {
    defer scratch.reset();
    
    const cmd_buf = try cmd_pool.allocate();
    defer try cmd_pool.deallocate(cmd_buf);
    
    // Command execution (fixed buffer)
    const result = try executor.execute(cmd_buf);
    
    // Analysis (scratch allocations)
    const analysis = try scratch.alloc(256);
    analyze_result(result, analysis);
}
```

### Pattern 3: Tiered Allocation

Use multiple allocators for different scopes:

```zig
// Session-level: General purpose allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

// Frame-level: Scratch allocator
var scratch = try ScratchAllocator.init(gpa.allocator());
defer scratch.deinit();

// Hot-path: Fixed pool
var pool = try FixedPoolAllocator.init(gpa.allocator(), 256, 100);
defer pool.deinit();

// Usage hierarchy:
// - Session setup: GeneralPurpose
// - Per-frame: Scratch (reset each frame)
// - Hot loops: FixedPool
```

## Performance Metrics

### Ring Buffer Allocator

Typical performance for 64KB buffer:

- Write 16 packets (1KB each): <1µs per packet
- Read with wraparound: <1µs per packet
- Peek: <500ns per operation

### Fixed Pool Allocator

For 256-byte blocks, 100-block pool:

- Allocate (hit): ~50ns
- Allocate (new): ~200ns
- Deallocate: ~50ns
- Hit rate: 85-95% in typical scenarios

### Scratch Allocator

For per-frame allocations (4KB chunks):

- Alloc (within chunk): ~50ns
- Alloc (new chunk): ~500ns
- Reset: ~10ns

## Configuration Recommendations

### For Network I/O

```zig
// Ring buffer: 2x max frame size
const NETWORK_BUFFER_SIZE = 2 * 65536;
var rb = try RingBufferAllocator.init(allocator, NETWORK_BUFFER_SIZE);

// Handle maximum TCP window
```

### For Command Processing

```zig
// Fixed pool: 3270 protocol
// Screen is 24x80 = 1920 bytes
// Command buffer format adds ~100 bytes overhead
const COMMAND_BUFFER_SIZE = 2048;
const POOL_SIZE = 50; // Typical concurrent commands

var pool = try FixedPoolAllocator.init(allocator, COMMAND_BUFFER_SIZE, POOL_SIZE);
```

### For Temporary Processing

```zig
// Scratch allocator: 4KB chunks
// Typical frame needs 8-16KB
var scratch = try ScratchAllocator.init(allocator);

// Reset at frame boundaries
scratch.reset();
```

## Migration Guide

### From GeneralPurposeAllocator

Before:
```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// In hot loop
const buf = try allocator.alloc(u8, 256);
defer allocator.free(buf);
```

After:
```zig
var pool = try FixedPoolAllocator.init(allocator, 256, 50);
defer pool.deinit();

// In hot loop
const buf = try pool.allocate();
defer try pool.deallocate(buf);
```

## Advanced Topics

### Custom Chunk Sizes

For scratch allocator, modify ChunkSize constant:

```zig
// In src/advanced_allocators.zig
const ChunkSize = 8192; // 8KB chunks instead of 4KB
```

### Integrating with Existing Code

The allocators are compatible with standard Zig patterns:

```zig
// Can be wrapped if needed
pub const CustomAllocator = struct {
    pool: FixedPoolAllocator,
    
    pub fn alloc(self: *@This(), len: usize) ![]u8 {
        if (len != pool_size) return error.InvalidSize;
        return try self.pool.allocate();
    }
};
```

## Benchmarks

See `docs/PERFORMANCE_TUNING.md` for benchmark results comparing:
- General purpose allocator
- Ring buffer allocator
- Fixed pool allocator
- Scratch allocator

Results show:
- 20-40% allocation reduction with fixed pools
- 10-15% throughput improvement with ring buffers
- 5-10% improvement with scratch for frame processing

## Best Practices

1. **Match Allocator to Lifetime**: Use fixed pool for stable sizes, scratch for temporary
2. **Profile First**: Measure allocation patterns before choosing allocator
3. **Test Exhaustion**: Verify pool size is adequate under load
4. **Monitor Statistics**: Use available stats methods to validate efficiency
5. **Document Decisions**: Comment why specific allocator was chosen

## References

- TN3270 Protocol: Typical command size 1920 bytes (24×80 screen)
- TCP Window: 65536 bytes typical, can be larger
- Frame Rate: 60fps = 16ms per frame budget
- Memory Budget: Embedded targets 128MB-256MB typical

## See Also

- `docs/PERFORMANCE_TUNING.md` - Performance configuration
- `docs/OPERATIONS.md` - Resource management recommendations
- `src/advanced_allocators.zig` - Implementation details
