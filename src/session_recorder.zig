const std = @import("std");

pub const SessionEvent = struct {
    timestamp: u64,
    event_type: EventType,
    data: []const u8,

    pub const EventType = enum {
        command,
        response,
        keyboard_input,
        screen_update,
    };
};

pub const SessionRecorder = struct {
    allocator: std.mem.Allocator,
    events_buffer: ?[]SessionEvent = null,
    events_len: usize = 0,
    events_capacity: usize = 0,
    start_time: i64 = 0,

    pub fn init(allocator: std.mem.Allocator) SessionRecorder {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SessionRecorder) void {
        if (self.events_buffer) |buffer| {
            for (buffer[0..self.events_len]) |event| {
                self.allocator.free(event.data);
            }
            self.allocator.free(buffer);
        }
    }

    /// Start recording session
    pub fn start(self: *SessionRecorder) void {
        self.start_time = std.time.milliTimestamp();
        self.events_len = 0;
    }

    /// Record an event
    pub fn record(
        self: *SessionRecorder,
        event_type: SessionEvent.EventType,
        data: []const u8,
    ) !void {
        const now = std.time.milliTimestamp();
        const elapsed: u64 = if (self.start_time > 0)
            @intCast(@max(0, now - self.start_time))
        else
            0;

        const data_copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(data_copy);

        const event = SessionEvent{
            .timestamp = elapsed,
            .event_type = event_type,
            .data = data_copy,
        };

        if (self.events_capacity == 0) {
            // First allocation
            const new_capacity = 16;
            const buffer = try self.allocator.alloc(SessionEvent, new_capacity);
            self.events_buffer = buffer;
            self.events_capacity = new_capacity;
            self.events_len = 0;
        }

        if (self.events_len >= self.events_capacity) {
            // Grow capacity
            const new_capacity = self.events_capacity * 2;
            const new_buffer = try self.allocator.alloc(SessionEvent, new_capacity);
            @memcpy(new_buffer[0..self.events_len], self.events_buffer.?[0..self.events_len]);
            self.allocator.free(self.events_buffer.?);
            self.events_buffer = new_buffer;
            self.events_capacity = new_capacity;
        }

        // Append event
        self.events_buffer.?[self.events_len] = event;
        self.events_len += 1;
    }

    /// Get number of recorded events
    pub fn event_count(self: SessionRecorder) usize {
        return self.events_len;
    }

    /// Get event by index
    pub fn get_event(self: SessionRecorder, index: usize) ?SessionEvent {
        if (index < self.events_len and self.events_buffer != null) {
            return self.events_buffer.?[index];
        }
        return null;
    }
};

// Tests
test "session recorder init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var recorder = SessionRecorder.init(allocator);
    defer recorder.deinit();

    try std.testing.expectEqual(@as(usize, 0), recorder.event_count());
}

test "session recorder record event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var recorder = SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.start();
    try recorder.record(.command, "test_command");

    try std.testing.expectEqual(@as(usize, 1), recorder.event_count());

    const event = recorder.get_event(0);
    try std.testing.expect(event != null);
    try std.testing.expectEqual(SessionEvent.EventType.command, event.?.event_type);
    try std.testing.expectEqualSlices(u8, "test_command", event.?.data);
}

test "session recorder multiple events" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var recorder = SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.start();
    try recorder.record(.command, "cmd1");
    try recorder.record(.response, "resp1");
    try recorder.record(.keyboard_input, "key1");

    try std.testing.expectEqual(@as(usize, 3), recorder.event_count());

    const event1 = recorder.get_event(0).?;
    const event2 = recorder.get_event(1).?;
    const event3 = recorder.get_event(2).?;

    try std.testing.expectEqual(SessionEvent.EventType.command, event1.event_type);
    try std.testing.expectEqual(SessionEvent.EventType.response, event2.event_type);
    try std.testing.expectEqual(SessionEvent.EventType.keyboard_input, event3.event_type);
}

test "session recorder event timestamps" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var recorder = SessionRecorder.init(allocator);
    defer recorder.deinit();

    recorder.start();
    try recorder.record(.command, "cmd1");

    const event = recorder.get_event(0).?;
    try std.testing.expect(event.timestamp >= 0);
}

test "session recorder get nonexistent event" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var recorder = SessionRecorder.init(allocator);
    defer recorder.deinit();

    try std.testing.expect(recorder.get_event(0) == null);
    try std.testing.expect(recorder.get_event(100) == null);
}
