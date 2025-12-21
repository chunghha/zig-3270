const std = @import("std");
const emulator = @import("emulator.zig");
const protocol = @import("protocol.zig");
const command_mod = @import("command.zig");
const buffer_pool = @import("buffer_pool.zig");
const field_storage = @import("field_storage.zig");
const field_cache = @import("field_cache.zig");
const AllocationTracker = @import("allocation_tracker.zig").AllocationTracker;
const session_storage = @import("session_storage.zig");
const renderer = @import("renderer.zig");

// Real-world workload simulations

test "benchmark: typical mainframe session pattern" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
    defer pool.deinit();

    // Simulate realistic session: 70% writes, 20% reads, 10% control
    const session_cycles = 1000;
    var write_count: u32 = 0;
    var read_count: u32 = 0;
    var erase_count: u32 = 0;

    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    const timer_start = std.time.nanoTimestamp();

    for (0..session_cycles) |cycle| {
        const cmd_type = switch (cycle % 10) {
            0...6 => protocol.CommandCode.write, // 70% writes
            7...8 => protocol.CommandCode.read_modified, // 20% reads
            9 => protocol.CommandCode.erase_write, // 10% control
            else => unreachable,
        };

        switch (cmd_type) {
            .write => write_count += 1,
            .read_modified => read_count += 1,
            .erase_write => erase_count += 1,
            else => {},
        }

        switch (cmd_type) {
            .write => {
                // Typical write: 3-5 fields, varying sizes
                const field_count = 3 + @as(u8, @truncate(cycle % 3));
                const cmd = try create_realistic_write_command(allocator, &pool, field_count, cycle);
                defer allocator.free(cmd.data);
                try emu.execute_command(cmd);
            },
            .read_modified => {
                // Simulate user input in random fields
                if (emu.field_count() > 0) {
                    const field_idx = @as(u32, @truncate(cycle % emu.field_count()));
                    try simulate_user_input(emu, field_idx, cycle);
                }
            },
            .erase_write => {
                // Clear screen and write new header
                const cmd = try create_erase_write_command(allocator, &pool, cycle);
                defer allocator.free(cmd.data);
                try emu.execute_command(cmd);
            },
            else => unreachable,
        }
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ms = @as(f64, @floatFromInt(timer_end - timer_start)) / 1_000_000.0;

    std.debug.print("\n=== Typical Mainframe Session ===\n");
    std.debug.print("Cycles: {}, Duration: {d:.2}ms, Avg: {d:.3}ms/cycle\n", .{ session_cycles, elapsed_ms, elapsed_ms / @as(f64, @floatFromInt(session_cycles)) });

    std.debug.print("write: {} commands\n", .{write_count});
    if (read_count > 0) std.debug.print("read_modified: {} commands\n", .{read_count});
    if (erase_count > 0) std.debug.print("erase_write: {} commands\n", .{erase_count});

    tracker.report();
}

test "benchmark: memory pressure behavior" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    // Test with constrained allocator
    const constrained_bytes = 64 * 1024; // 64KB limit
    const constrained_buffer = try parent.alloc(u8, constrained_bytes);
    defer parent.free(constrained_buffer);
    var constrained_allocator = std.heap.FixedBufferAllocator.init(constrained_buffer);

    var tracker = AllocationTracker.init(constrained_allocator.allocator());
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
    defer pool.deinit();

    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    const timer_start = std.time.nanoTimestamp();

    // Try to stress the constrained allocator
    var successful_operations: u32 = 0;
    var failed_operations: u32 = 0;

    for (0..500) |cycle| {
        // Create larger commands to trigger pressure
        const cmd = try create_large_write_command(allocator, &pool, cycle);
        defer allocator.free(cmd.data);

        if (emu.execute_command(cmd)) {
            successful_operations += 1;
        } else |_| {
            failed_operations += 1;
        }
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ms = @as(f64, @floatFromInt(timer_end - timer_start)) / 1_000_000.0;

    std.debug.print("\n=== Memory Pressure Test ===\n");
    std.debug.print("Constrained: {} bytes, Success: {}, Failed: {}, Duration: {d:.2}ms\n", .{ constrained_bytes, successful_operations, failed_operations, elapsed_ms });
    std.debug.print("Success rate: {d:.1}%\n", .{@as(f64, @floatFromInt(successful_operations)) / @as(f64, @floatFromInt(successful_operations + failed_operations)) * 100.0});

    tracker.report();
}

test "benchmark: long-running stability" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
    defer pool.deinit();

    const extended_cycles = 10_000;
    const MemorySnapshot = struct {
        cycle: u32,
        allocations: usize,
        peak_bytes: usize,
        current_bytes: usize,
    };
    var memory_snapshots = std.ArrayList(MemorySnapshot).init(allocator);
    defer memory_snapshots.deinit();

    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    const timer_start = std.time.nanoTimestamp();

    for (0..extended_cycles) |cycle| {
        // Vary operation intensity
        const operation_type = cycle % 4;

        switch (operation_type) {
            0 => {
                // Heavy field operations
                for (0..5) |_| {
                    const start = @as(u16, @truncate((cycle % 20) * 80));
                    try emu.add_field(start, 10, .{});
                }
            },
            1 => {
                // Buffer pool stress
                var buffers = try allocator.alloc([]u8, 10);
                defer allocator.free(buffers);

                for (0..10) |i| {
                    buffers[i] = try pool.acquire();
                }

                for (buffers) |buf| {
                    pool.release(buf) catch {};
                }
            },
            2 => {
                // Screen operations
                for (0..80) |col| {
                    try emu.write_char(0, @as(u16, @truncate(col)), 'A' + @as(u8, @truncate(col % 26)));
                }
            },
            3 => {
                // Mixed operations
                const cmd = try create_realistic_write_command(allocator, &pool, 3, cycle);
                defer allocator.free(cmd.data);
                try emu.execute_command(cmd);
            },
            else => unreachable,
        }

        // Take memory snapshots every 1000 cycles
        if (cycle % 1000 == 0) {
            try memory_snapshots.append(.{
                .cycle = @intCast(cycle),
                .allocations = tracker.allocations,
                .peak_bytes = tracker.peak_bytes,
                .current_bytes = tracker.current_bytes,
            });
        }
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_seconds = @as(f64, @floatFromInt(timer_end - timer_start)) / 1_000_000_000.0;

    std.debug.print("\n=== Long-Running Stability ===\n");
    std.debug.print("Cycles: {}, Duration: {d:.2}s, Avg: {d:.3}ms/cycle\n", .{ extended_cycles, elapsed_seconds, (elapsed_seconds * 1000.0) / @as(f64, @floatFromInt(extended_cycles)) });

    // Memory growth analysis
    if (memory_snapshots.items.len > 1) {
        const first = memory_snapshots.items[0];
        const last = memory_snapshots.items[memory_snapshots.items.len - 1];

        std.debug.print("Memory growth: {}→{} allocations ({}), {}→{} peak bytes ({})\n", .{ first.allocations, last.allocations, last.allocations - first.allocations, first.peak_bytes, last.peak_bytes, @as(i64, @intCast(last.peak_bytes)) - @as(i64, @intCast(first.peak_bytes)) });
    }

    tracker.report();
}

test "benchmark: optimization vs naive implementation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    const test_cycles = 1000;
    var optimized_duration: f64 = undefined;
    var naive_duration: f64 = undefined;

    // Test optimized implementation
    {
        var tracker = AllocationTracker.init(parent);
        const allocator = tracker.allocator();

        var emu = try emulator.Emulator.init(allocator, 24, 80);
        defer emu.deinit();

        var pool = buffer_pool.CommandBufferPool.init(allocator, 1920);
        defer pool.deinit();

        tracker.allocations = 0;
        tracker.deallocations = 0;
        tracker.peak_bytes = 0;
        tracker.current_bytes = 0;

        const optimized_start = std.time.nanoTimestamp();

        for (0..test_cycles) |cycle| {
            const cmd = try create_realistic_write_command(allocator, &pool, 3, cycle);
            defer allocator.free(cmd.data);
            try emu.execute_command(cmd);
        }

        const optimized_end = std.time.nanoTimestamp();
        optimized_duration = @as(f64, @floatFromInt(optimized_end - optimized_start)) / 1_000_000.0;

        std.debug.print("\n=== Optimization Impact Analysis ===\n");
        std.debug.print("OPTIMIZED: {d:.2}ms, ", .{optimized_duration});
        tracker.report();
    }

    // Simulate naive implementation (direct allocations, no pooling)
    {
        var tracker = AllocationTracker.init(parent);
        const allocator = tracker.allocator();

        var emu = try emulator.Emulator.init(allocator, 24, 80);
        defer emu.deinit();

        tracker.allocations = 0;
        tracker.deallocations = 0;
        tracker.peak_bytes = 0;
        tracker.current_bytes = 0;

        const naive_start = std.time.nanoTimestamp();

        for (0..test_cycles) |cycle| {
            // Naive: direct allocation for each command
            const cmd = try create_naive_command(allocator, cycle);
            defer allocator.free(cmd.data);
            try emu.execute_command(cmd);
        }

        const naive_end = std.time.nanoTimestamp();
        naive_duration = @as(f64, @floatFromInt(naive_end - naive_start)) / 1_000_000.0;

        std.debug.print("NAIVE:      {d:.2}ms, ", .{naive_duration});
        tracker.report();

        // Calculate improvement
        const improvement = (naive_duration - optimized_duration) / naive_duration * 100.0;
        std.debug.print("Performance improvement: {d:.1}%\n", .{improvement});
    }
}

// Helper functions for benchmark scenarios

fn create_realistic_write_command(
    allocator: std.mem.Allocator,
    pool: *buffer_pool.CommandBufferPool,
    field_count: u8,
    cycle: usize,
) !command_mod.Command {
    const buf = try pool.acquire();
    defer pool.release(buf) catch {};

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    // Create realistic field layout
    var current_addr: u16 = 0;

    for (0..field_count) |field_idx| {
        // Set buffer address
        try data.append(0x11);
        try data.append(@as(u8, @truncate(current_addr >> 8)));
        try data.append(@as(u8, @truncate(current_addr & 0xFF)));

        // Start field with attributes
        try data.append(0x1D);
        const field_attr = protocol.FieldAttribute{
            .protected = if (field_idx == 0) true else false,
            .numeric = false,
            .intensified = (field_idx % 2 == 0),
            .display = true,
        };
        try data.append(@intFromEnum(field_attr));

        // Field data (varying lengths)
        const field_length = 5 + @as(u8, @truncate((cycle + field_idx) % 15));
        for (0..field_length) |char_idx| {
            try data.append('A' + @as(u8, @truncate((cycle + field_idx + char_idx) % 26)));
        }

        current_addr += 1 + field_length;
        if (current_addr >= 24 * 80 - 20) break;
    }

    return command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, data.items),
    };
}

fn create_large_write_command(
    allocator: std.mem.Allocator,
    pool: *buffer_pool.CommandBufferPool,
    cycle: usize,
) !command_mod.Command {
    const buf = try pool.acquire();
    defer pool.release(buf) catch {};

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    // Create larger command for memory pressure testing
    try data.append(0x11);
    try data.append(0x00);
    try data.append(0x00);

    // Large amount of data
    const data_size = 1500 + @as(usize, @truncate(cycle % 400));
    for (0..data_size) |i| {
        try data.append('X' + @as(u8, @truncate(i % 26)));
    }

    return command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, data.items),
    };
}

fn create_erase_write_command(
    allocator: std.mem.Allocator,
    pool: *buffer_pool.CommandBufferPool,
    cycle: usize,
) !command_mod.Command {
    _ = pool; // Unused in this implementation

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    // Erase Write to start of screen
    try data.append(0x05); // Erase Write
    try data.append(0x11);
    try data.append(0x00);
    try data.append(0x00);

    // Header line
    const header_text = "SESSION ";
    for (0..header_text.len) |i| {
        try data.append(header_text[i]);
    }

    // Session number
    const session_num = cycle % 1000;
    const session_str = try std.fmt.allocPrint(allocator, "{}", .{session_num});
    defer allocator.free(session_str);

    for (session_str) |char| {
        try data.append(char);
    }

    return command_mod.Command{
        .code = protocol.CommandCode.erase_write,
        .data = try allocator.dupe(u8, data.items),
    };
}

fn simulate_user_input(emu: *emulator.Emulator, field_idx: u32, cycle: usize) !void {
    _ = cycle; // Unused in this implementation
    if (field_idx < emu.field_count()) {
        // Simulate typing in field
        const input_text = "DATA";
        for (0..input_text.len) |i| {
            try emu.write_char(0, @as(u16, @truncate(i)), input_text[i]);
        }
    }
}

fn create_naive_command(allocator: std.mem.Allocator, cycle: usize) !command_mod.Command {
    // Naive implementation: direct allocation, no pooling
    var data = try allocator.alloc(u8, 100);

    data[0] = @intFromEnum(protocol.CommandCode.write);
    data[1] = 0x11;
    data[2] = 0x00;
    data[3] = 0x00;

    for (4..100) |i| {
        data[i] = 'A' + @as(u8, @truncate((cycle + i) % 26));
    }

    return command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = data,
    };
}
