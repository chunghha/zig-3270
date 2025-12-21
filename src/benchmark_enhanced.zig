const std = @import("std");
const parser = @import("parser.zig");
const stream_parser = @import("stream_parser.zig");
const executor = @import("executor.zig");
const command_mod = @import("command.zig");
const protocol = @import("protocol.zig");
const emulator = @import("emulator.zig");
const AllocationTracker = @import("allocation_tracker.zig").AllocationTracker;

// Enhanced benchmarks measuring allocations and memory impact

test "benchmark enhanced: parser throughput with allocation tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    // Create 1KB test data
    var data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    // Fill with pattern
    for (0..1024) |i| {
        data[i] = @as(u8, @truncate(i % 256));
    }

    // Reset tracker after setup
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    // Benchmark: parse bytes sequentially
    const timer_start = std.time.nanoTimestamp();

    var p = parser.Parser.init(allocator, data);
    var bytes_read: u32 = 0;

    while (p.has_more()) {
        _ = try p.read();
        bytes_read += 1;
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
    const throughput_mb_s = (1024.0 / elapsed_us) * 1000.0;

    std.debug.print("Parser: {d:.2} MB/s, ", .{throughput_mb_s});
    tracker.report();

    try std.testing.expectEqual(@as(u32, 1024), bytes_read);
    try std.testing.expectEqual(@as(usize, 0), tracker.allocations);
}

test "benchmark enhanced: stream parser allocation count" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    // Create 10KB test data with repeated command pattern
    var data = try allocator.alloc(u8, 10240);
    defer allocator.free(data);

    // Create a repeating pattern: command code + data
    var i: u32 = 0;
    while (i < 10240) {
        data[i] = @intFromEnum(protocol.CommandCode.write);
        i += 1;
        if (i < 10240) {
            data[i] = 0x42;
            i += 1;
        }
        if (i < 10240) {
            data[i] = 'X';
            i += 1;
        }
    }

    // Reset tracker after setup
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    // Benchmark: parse stream
    const timer_start = std.time.nanoTimestamp();

    var sp = stream_parser.StreamParser.init(allocator, data);
    var cmd_count: u32 = 0;

    while (try sp.next_command()) |cmd| {
        cmd_count += 1;
        var cmd_copy = cmd;
        cmd_copy.deinit(allocator);
        if (cmd_count >= 100) break;
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
    const cmd_per_ms = @as(f64, @floatFromInt(cmd_count)) / (elapsed_us / 1000.0);

    std.debug.print("Stream Parser: {d:.0} cmd/ms, {d} commands, ", .{ cmd_per_ms, cmd_count });
    tracker.report();

    try std.testing.expect(cmd_count > 0);
}

test "benchmark enhanced: executor with allocation tracking" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Create a command that writes to the entire screen (1920 bytes)
    var order_data = try std.ArrayList(u8).initCapacity(allocator, 1920);
    defer order_data.deinit(allocator);

    // Fill screen with data
    try order_data.append(allocator, 0x11);
    try order_data.append(allocator, 0x00);
    try order_data.append(allocator, 0x00);

    for (0..1920) |j| {
        try order_data.append(allocator, if (j % 26 < 25) 'A' + @as(u8, @truncate(j % 26)) else ' ');
    }

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

    // Reset tracker after setup
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    // Benchmark: execute command
    const timer_start = std.time.nanoTimestamp();

    for (0..100) |_| {
        try exec.execute(cmd);
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
    const bytes_written = 1920 * 100;
    const throughput_mb_s = (@as(f64, @floatFromInt(bytes_written)) / elapsed_us) * 1000.0 / (1024.0 * 1024.0);

    std.debug.print("Executor: {d:.2} MB/s, ", .{throughput_mb_s});
    tracker.report();
}

test "benchmark enhanced: field management allocations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Reset tracker after setup
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    // Benchmark: add many fields
    const timer_start = std.time.nanoTimestamp();

    for (0..100) |i| {
        const start = @as(u16, @truncate((i % 19) * 80));
        try emu.add_field(start, 40, .{});
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("Field Management: {} fields in {d:.2} µs, ", .{ 100, elapsed_us });
    tracker.report();

    try std.testing.expectEqual(@as(usize, 100), emu.field_count());
}

test "benchmark enhanced: character write throughput" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Reset tracker after setup
    tracker.allocations = 0;
    tracker.deallocations = 0;
    tracker.peak_bytes = 0;
    tracker.current_bytes = 0;

    // Benchmark: write many characters
    const timer_start = std.time.nanoTimestamp();

    for (0..24) |row| {
        for (0..80) |col| {
            try emu.write_char(@as(u16, @truncate(row)), @as(u16, @truncate(col)), 'A' + @as(u8, @truncate((row + col) % 26)));
        }
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
    const total_writes = 24 * 80;
    const throughput_kc_s = @as(f64, @floatFromInt(total_writes)) / (elapsed_us / 1000.0);

    std.debug.print("Character Write: {d:.0} chars/ms, ", .{throughput_kc_s});
    tracker.report();
}

test "benchmark enhanced: address conversion" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const parent = gpa.allocator();

    var tracker = AllocationTracker.init(parent);
    const allocator = tracker.allocator();

    const parse_utils = @import("parse_utils.zig");

    // Benchmark: address conversions
    const timer_start = std.time.nanoTimestamp();

    var conversions: u32 = 0;
    for (0..24) |row| {
        for (0..80) |col| {
            const addr = protocol.Address{ .row = @as(u8, @truncate(row)), .col = @as(u8, @truncate(col)) };
            const buf = parse_utils.address_to_buffer(addr);
            const addr2 = parse_utils.buffer_to_address(buf);
            _ = addr2;
            conversions += 1;
        }
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;
    const throughput_kc_s = @as(f64, @floatFromInt(conversions)) / (elapsed_us / 1000.0);

    std.debug.print("Address Conversion: {d:.0} conv/ms, ", .{throughput_kc_s});
    tracker.report();

    try std.testing.expectEqual(@as(u32, 1920), conversions);
}
