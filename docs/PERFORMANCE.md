# Performance & Profiling Guide

## Overview

This document outlines performance considerations, hot paths, and memory optimization strategies for the zig-3270 TN3270 emulator.

## Profiler Usage

The `profiler.zig` module provides memory and timing analysis:

```zig
const profiler_mod = @import("profiler.zig");

var profiler = profiler_mod.Profiler.init(allocator);
defer profiler.deinit();

// Record allocations
profiler.record_alloc(1024);
profiler.record_free(512);

// Time operations
{
    var scope = profiler.scope("operation_name");
    defer scope.end();
    // ... do work
}

// Get statistics
const mem_stats = profiler.get_memory_stats();
const timing_stats = profiler.get_timing_stats("operation_name");
```

## Hot Paths

### 1. Parser (parser.zig)

**Current Performance**:
- ~500+ MB/s throughput on sequential byte reads
- O(1) operations for peek/read
- No allocations in hot loop

**Optimization Status**: ✓ Optimized
- Uses stack-based buffer (no heap allocation during parsing)
- Direct byte access without bounds checking overhead
- Streaming parser for sequential data

### 2. Stream Parser (stream_parser.zig)

**Current Performance**:
- Commands parsed at ~2000+ commands/ms
- Minimal allocations per command (only for command.data)
- No unnecessary buffering

**Optimization Status**: Partially Optimized
- Consider pooling command allocations to reduce GC pressure
- Current: 1 allocation per command for data buffer
- Suggested: Pre-allocate pool of buffers for common sizes (e.g., 1920 bytes for screen)

### 3. Data Entry (data_entry.zig)

**Current Performance**:
- Field lookups are O(field_count) linear search
- Tab/Home operations iterate through fields
- Character insertion copies field data

**Optimization Status**: Could be improved
- **Hot Path 1**: Field lookups in `tab()`, `home()`, `insert_char()`, etc.
  - Current: Linear search through field list
  - Suggestion: Cache last accessed field, use indexed lookup
  
- **Hot Path 2**: Character insertion in `insert_char()`
  - Current: Field data is copied on each insert
  - Suggestion: Use circular buffer or copy-on-write semantics

- **Memory Issue**: Each field stores character data - consider external storage
  - Current: Field includes `data: []u8` allocation
  - Suggestion: Separate field metadata from field data storage

### 4. Executor (executor.zig)

**Current Performance**:
- Screen writes at ~50+ MB/s
- Address conversions are O(1)
- Order parsing is O(data_length)

**Optimization Status**: Optimized
- Direct address calculations (no lookups)
- Minimal allocations
- Streaming order processing

### 5. Screen Buffer (screen.zig)

**Current Performance**:
- Character writes are O(1)
- Full screen clear is O(1920)
- All operations are in-place (no allocations)

**Optimization Status**: ✓ Optimized
- Pre-allocated 1920-byte buffer
- No dynamic resizing
- Direct index access

## Memory Patterns

### Current State

```
Total Source: 32 modules, 3,820 lines
Peak Observed Usage: < 1 MB (typical TN3270 session)
Allocations per Command: ~1-2 (command.data + order parsing)
```

### Allocation Sites

1. **CommandParser.parse_command()** - Allocates command.data
2. **CommandParser.parse_orders()** - Allocates each Order.data
3. **DataEntry.insert_char()** - Copies field data
4. **Stream Parser** - Allocates command on each parse

### Optimization Opportunities

#### 1. Command Data Buffer Pool (High Impact)

**Problem**: Each command allocation is unique size, causing fragmentation

**Solution**: Use arena allocator per command batch
```zig
// Current
const data = try allocator.dupe(u8, buffer[1..]);

// Proposed
const arena = try ArenaAllocator.init(allocator);
defer arena.deinit();
const data = try arena.allocator().dupe(u8, buffer[1..]);
```

**Impact**: 30-50% reduction in allocator calls during high-throughput scenarios

#### 2. Field Data Externalization

**Problem**: Field data stored in Field struct, allocated inline

**Solution**: Store field data in external array, reference by handle
```zig
// Current
pub const Field = struct {
    data: []u8,  // Individual allocation
};

// Proposed
pub const Field = struct {
    data_handle: FieldDataHandle,  // Reference to pooled data
};

pub const FieldDataStorage = struct {
    data: []u8,  // Single 1920-byte allocation
    field_ranges: [][2]usize,  // [offset, length] for each field
};
```

**Impact**: Single allocation instead of N allocations per screen

#### 3. Streaming Parsing Without Intermediate Buffers

**Problem**: Stream parser builds commands in memory, then returns

**Solution**: Use callback-based parsing for direct execution
```zig
// Current
while (try sp.next_command()) |cmd| { exec.execute(cmd); }

// Proposed
try sp.parse_and_execute(executor.execute_fn);
```

**Impact**: Eliminate temporary command allocations on critical path

## Running Benchmarks

Run the full benchmark suite with allocation tracking:

```bash
task test              # All tests including benchmarks
task test-benchmark    # Only benchmark tests (6 original + 6 enhanced + impact tests)
```

### Available Benchmark Tests

#### Original Benchmarks (measuring throughput)
- Parser throughput (1KB buffer) - 500+ MB/s
- Stream parser throughput (10KB data, 100 commands) - 2000+ cmd/ms
- Executor throughput (screen writes) - 50+ MB/s
- Field management overhead - per-field operation timing
- Character write throughput - full screen operations
- Address conversion performance - 1920+ conversions/ms

#### Enhanced Benchmarks (with allocation tracking)
- `benchmark enhanced: parser throughput with allocation tracking`
- `benchmark enhanced: stream parser allocation count`
- `benchmark enhanced: executor with allocation tracking`
- `benchmark enhanced: field management allocations`
- `benchmark enhanced: character write throughput`
- `benchmark enhanced: address conversion`

#### Optimization Impact Benchmarks
- Buffer pool allocation reduction (30-50% improvement)
- Field data externalization (N→1 allocations)
- Field cache hit rate measurement
- Combined optimization summary

## Profiling Example

```zig
const profiler_mod = @import("profiler.zig");

test "profile emulator session" {
    var profiler = profiler_mod.Profiler.init(allocator);
    defer profiler.deinit();

    var emu = try Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Profile command execution
    {
        var scope = profiler.scope("execute_command");
        defer scope.end();
        try emu.execute_command(cmd);
    }

    // Print report
    var stdout = std.io.getStdOut().writer();
    try profiler.print_memory_report(stdout);
    try profiler.print_timing_report(stdout);
}
```

## Guidelines for New Code

### Memory Allocation

1. **Prefer Stack**: For small fixed-size allocations (<4KB)
   ```zig
   var buffer: [256]u8 = undefined;  // Not allocated from heap
   ```

2. **Use Arena Allocators**: For batches of related allocations
   ```zig
   var arena = try ArenaAllocator.init(allocator);
   defer arena.deinit();
   // Many allocations from arena - single deallocation
   ```

3. **Avoid Allocation in Hot Loops**: Profile first!
   - Parser loop: No allocations ✓
   - Executor loop: Minimize allocations
   - Field navigation: Cache results

### Timing Critical Sections

1. **Use profiler scope for timing**:
   ```zig
   var scope = profiler.scope("operation");
   defer scope.end();
   ```

2. **Avoid string formatting in hot paths**
   - Use binary logging instead
   - Format only when needed for display

3. **Cache Computations**:
   - Field lookups: Cache current field
   - Address calculations: Pre-compute offsets

## Measurement Results

### Baseline Performance (v0.5.1)

#### Throughput Metrics
| Operation | Throughput | Allocation Impact |
|-----------|-----------|----------|
| Parser byte read | 500+ MB/s | 0 allocations (stack-based) |
| Stream parser | 2000+ cmd/ms | 1 allocation per command |
| Executor writes | 50+ MB/s | 0 allocations (streaming) |
| Address conversion | 1920+ conversions/ms | 0 allocations |
| Field navigation | O(field_count) | O(n) linear search |
| Character write | 24K chars/ms | 0 allocations |

#### Memory Profile (Single 24×80 Screen)
| Component | Current | With Optimization |
|-----------|---------|----------|
| Screen buffer | 1.9 KB | 1.9 KB |
| Field storage (20 fields) | 20 allocations | 1 allocation (externalized) |
| Command buffers (100 parses) | 100 allocations | ~20 allocations (pooled) |
| **Total allocations** | 120+ | ~22 (82% reduction potential) |

### Memory Profile (1920-char screen, 5 fields)

| Component | Allocation | Status |
|-----------|----------|--------|
| Screen buffer | 1.9 KB | Fixed, optimized |
| Field storage | ~0.5 KB | Variable, could optimize |
| Command data | ~1-2 KB | Per command, could pool |
| **Total** | **~4 KB** | Within limits |

## Optimization Targets Status (v0.5.1)

### High Priority - IMPLEMENTED ✓

#### ✓ Command Data Buffer Pooling
- **Status**: Implemented in `buffer_pool.zig`
- **Impact**: 30-50% reduction in allocations (tested: reuse rates up to 50%+)
- **Testing**: 
  - `BufferPool(T)` generic pool with acquire/release
  - `CommandBufferPool` specialized for 1920-byte command buffers
  - `VariableBufferPool` for mixed-size allocations
  - 3 comprehensive tests with pool statistics

#### ✓ Field Data Externalization
- **Status**: Implemented in `field_storage.zig`
- **Impact**: N→1 allocations (20 fields → 1 allocation)
- **Features**:
  - Single preallocated buffer (configurable capacity)
  - Field handle system for range references
  - O(1) character access within fields
  - 5 comprehensive tests with statistics

#### ✓ Field Lookup Caching
- **Status**: Implemented in `field_cache.zig`
- **Impact**: O(n)→O(1) for repeated lookups (tab, home, insert)
- **Features**:
  - Cache hit/miss tracking with statistics
  - Automatic cache invalidation on field changes
  - Configurable validation callbacks
  - 4 comprehensive tests

### Medium Priority - Future

- [ ] Callback-based stream parsing (eliminate temp allocations)
- [ ] Copy-on-write for field data
- [ ] SIMD operations for screen updates (if applicable)

### Low Priority - Future

- [ ] Custom allocator for protocol buffers
- [ ] Zero-copy protocol parsing
- [ ] JIT compilation for command execution

## See Also

- `benchmark.zig` - Benchmark tests for performance measurement
- `profiler.zig` - Memory and timing profiler
- `ARCHITECTURE.md` - System design and module boundaries
