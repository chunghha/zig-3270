const std = @import("std");
const parser = @import("parser.zig");
const stream_parser = @import("stream_parser.zig");
const executor = @import("executor.zig");
const command_mod = @import("command.zig");
const protocol = @import("protocol.zig");
const emulator = @import("emulator.zig");

// Benchmarks for parsing throughput and performance

test "benchmark: parser throughput on 1KB buffer" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create 1KB test data
    var data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);

    // Fill with pattern
    for (0..1024) |i| {
        data[i] = @as(u8, @truncate(i % 256));
    }

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
    const throughput_mb_s = (1024.0 / elapsed_us) * 1000.0; // Convert to MB/s

    std.debug.print("Parser throughput: {d:.2} MB/s ({d:.2} µs for 1KB)\n", .{ throughput_mb_s, elapsed_us });

    try std.testing.expectEqual(@as(u32, 1024), bytes_read);
}

test "benchmark: stream parser command parsing on 10KB data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create 10KB test data with repeated command pattern
    var data = try allocator.alloc(u8, 10240);
    defer allocator.free(data);

    // Create a repeating pattern: command code + data
    var i: u32 = 0;
    while (i < 10240) {
        data[i] = @intFromEnum(protocol.CommandCode.write); // 0x01
        i += 1;
        if (i < 10240) {
            data[i] = 0x42; // WCC
            i += 1;
        }
        if (i < 10240) {
            data[i] = 'X'; // data
            i += 1;
        }
    }

    // Benchmark: parse stream
    const timer_start = std.time.nanoTimestamp();

    var sp = stream_parser.StreamParser.init(allocator, data);
    var cmd_count: u32 = 0;

    while (try sp.next_command()) |cmd| {
        cmd_count += 1;
        var cmd_copy = cmd;
        cmd_copy.deinit(allocator);
        if (cmd_count >= 100) break; // Limit to 100 commands for time
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("Stream parser: {d} commands parsed in {d:.2} µs ({d:.2} cmd/ms)\n", .{ cmd_count, elapsed_us, @as(f64, @floatFromInt(cmd_count)) / (elapsed_us / 1000.0) });

    try std.testing.expect(cmd_count > 0);
}

test "benchmark: executor throughput on screen writes" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    var exec = executor.Executor.init(allocator, &emu.screen_buffer, &emu.field_manager);

    // Create a command that writes to the entire screen (1920 bytes)
    var order_data = try std.ArrayList(u8).initCapacity(allocator, 1920);
    defer order_data.deinit(allocator);

    // Fill screen with data
    try order_data.append(allocator, 0x11); // Set Buffer Address
    try order_data.append(allocator, 0x00); // (0, 0)
    try order_data.append(allocator, 0x00);

    for (0..1920) |j| {
        try order_data.append(allocator, if (j % 26 < 25) 'A' + @as(u8, @truncate(j % 26)) else ' ');
    }

    const cmd = command_mod.Command{
        .code = protocol.CommandCode.write,
        .data = try allocator.dupe(u8, order_data.items),
    };
    defer allocator.free(cmd.data);

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

    std.debug.print("Executor throughput: {d:.2} MB/s ({d:.2} µs for {} commands)\n", .{ throughput_mb_s, elapsed_us, 100 });
}

test "benchmark: field management overhead" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

    // Benchmark: add many fields
    const timer_start = std.time.nanoTimestamp();

    for (0..100) |i| {
        const start = @as(u16, @truncate((i % 19) * 80));
        try emu.add_field(start, 40, .{});
    }

    const timer_end = std.time.nanoTimestamp();
    const elapsed_ns = timer_end - timer_start;
    const elapsed_us = @as(f64, @floatFromInt(elapsed_ns)) / 1000.0;

    std.debug.print("Field management: {} fields added in {d:.2} µs ({d:.2} µs per field)\n", .{ 100, elapsed_us, elapsed_us / 100.0 });

    try std.testing.expectEqual(@as(usize, 100), emu.field_count());
}

test "benchmark: screen write character operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var emu = try emulator.Emulator.init(allocator, 24, 80);
    defer emu.deinit();

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
    const throughput_kc_s = @as(f64, @floatFromInt(total_writes)) / (elapsed_us / 1000.0); // kilo-chars/sec

    std.debug.print("Character write throughput: {d:.0} chars/ms ({d:.2} µs total for {} chars)\n", .{ throughput_kc_s, elapsed_us, total_writes });
}

test "benchmark: address conversion performance" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    std.debug.print("Address conversions: {d:.0} conversions/ms ({d:.2} µs total)\n", .{ throughput_kc_s, elapsed_us });

    try std.testing.expectEqual(@as(u32, 1920), conversions);
}
