const std = @import("std");
const screen = @import("screen.zig");
const protocol = @import("protocol.zig");

/// Screen history and scrollback management
pub const ScreenHistory = struct {
    snapshots: std.ArrayList(ScreenSnapshot),
    current_index: usize,
    max_history: usize,
    allocator: std.mem.Allocator,

    pub const ScreenSnapshot = struct {
        buffer: []u8,
        rows: u16,
        cols: u16,
        timestamp: i64,
        sequence_number: u64,
    };

    /// Initialize screen history with specified capacity
    pub fn init(allocator: std.mem.Allocator, max_history: usize) ScreenHistory {
        return .{
            .snapshots = std.ArrayList(ScreenSnapshot).init(allocator),
            .current_index = 0,
            .max_history = max_history,
            .allocator = allocator,
        };
    }

    /// Save current screen state to history
    pub fn save_snapshot(self: *ScreenHistory, scr: *const screen.Screen) !void {
        // If we're not at the end of history, discard future entries
        if (self.current_index < self.snapshots.items.len) {
            for (self.current_index..self.snapshots.items.len) |i| {
                self.allocator.free(self.snapshots.items[i].buffer);
            }
            self.snapshots.shrinkRetainingCapacity(self.current_index);
        }

        // Copy screen buffer
        const buffer_copy = try self.allocator.dupe(u8, scr.buffer);

        const snapshot = ScreenSnapshot{
            .buffer = buffer_copy,
            .rows = scr.rows,
            .cols = scr.cols,
            .timestamp = std.time.milliTimestamp(),
            .sequence_number = self.snapshots.items.len,
        };

        try self.snapshots.append(snapshot);
        self.current_index = self.snapshots.items.len - 1;

        // Remove old entries if exceeding max history
        if (self.snapshots.items.len > self.max_history) {
            const oldest = self.snapshots.orderedRemove(0);
            self.allocator.free(oldest.buffer);
            self.current_index -= 1;
        }
    }

    /// Navigate to previous screen in history
    pub fn previous(self: *ScreenHistory) ?*const ScreenSnapshot {
        if (self.current_index > 0) {
            self.current_index -= 1;
            return &self.snapshots.items[self.current_index];
        }
        return null;
    }

    /// Navigate to next screen in history
    pub fn next(self: *ScreenHistory) ?*const ScreenSnapshot {
        if (self.current_index < self.snapshots.items.len - 1) {
            self.current_index += 1;
            return &self.snapshots.items[self.current_index];
        }
        return null;
    }

    /// Jump to specific history entry by index
    pub fn jump_to(self: *ScreenHistory, index: usize) ?*const ScreenSnapshot {
        if (index < self.snapshots.items.len) {
            self.current_index = index;
            return &self.snapshots.items[index];
        }
        return null;
    }

    /// Get current snapshot
    pub fn current(self: *ScreenHistory) ?*const ScreenSnapshot {
        if (self.snapshots.items.len > 0) {
            return &self.snapshots.items[self.current_index];
        }
        return null;
    }

    /// Get total number of snapshots
    pub fn count(self: ScreenHistory) usize {
        return self.snapshots.items.len;
    }

    /// Get current index in history
    pub fn current_index_get(self: ScreenHistory) usize {
        return self.current_index;
    }

    /// Clear all history
    pub fn clear(self: *ScreenHistory) void {
        for (self.snapshots.items) |snapshot| {
            self.allocator.free(snapshot.buffer);
        }
        self.snapshots.clearRetainingCapacity();
        self.current_index = 0;
    }

    /// Deinitialize history
    pub fn deinit(self: *ScreenHistory) void {
        self.clear();
        self.snapshots.deinit();
    }
};

// Tests
test "screen_history: init creates empty history" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    try std.testing.expectEqual(@as(usize, 0), history.count());
    try std.testing.expectEqual(@as(?*const ScreenHistory.ScreenSnapshot, null), history.current());
}

test "screen_history: save_snapshot stores screen data" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try scr.write_char(0, 0, 'A');
    try history.save_snapshot(&scr);

    try std.testing.expectEqual(@as(usize, 1), history.count());
    const snap = history.current().?;
    try std.testing.expectEqual(@as(u16, 24), snap.rows);
    try std.testing.expectEqual(@as(u16, 80), snap.cols);
}

test "screen_history: previous navigates backward" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);

    try std.testing.expectEqual(@as(usize, 2), history.current_index_get());

    _ = history.previous();
    try std.testing.expectEqual(@as(usize, 1), history.current_index_get());

    _ = history.previous();
    try std.testing.expectEqual(@as(usize, 0), history.current_index_get());

    try std.testing.expectEqual(@as(?*const ScreenHistory.ScreenSnapshot, null), history.previous());
}

test "screen_history: next navigates forward" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);

    _ = history.previous();
    _ = history.previous();
    try std.testing.expectEqual(@as(usize, 0), history.current_index_get());

    _ = history.next();
    try std.testing.expectEqual(@as(usize, 1), history.current_index_get());

    _ = history.next();
    try std.testing.expectEqual(@as(usize, 2), history.current_index_get());
}

test "screen_history: jump_to goes to specific index" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);

    const snap = history.jump_to(2);
    try std.testing.expectEqual(@as(usize, 2), history.current_index_get());
    try std.testing.expect(snap != null);
}

test "screen_history: clear removes all snapshots" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);

    history.clear();

    try std.testing.expectEqual(@as(usize, 0), history.count());
    try std.testing.expectEqual(@as(usize, 0), history.current_index_get());
}

test "screen_history: max_history enforces limit" {
    var history = ScreenHistory.init(std.testing.allocator, 5);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    for (0..10) |_| {
        try history.save_snapshot(&scr);
    }

    try std.testing.expectEqual(@as(usize, 5), history.count());
}

test "screen_history: navigating forward from past goes to current" {
    var history = ScreenHistory.init(std.testing.allocator, 10);
    defer history.deinit();

    var scr = try screen.Screen.init(std.testing.allocator, 24, 80);
    defer scr.deinit();

    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);
    try history.save_snapshot(&scr);

    _ = history.previous();
    _ = history.previous();

    // Navigate forward twice back to current
    _ = history.next();
    _ = history.next();

    try std.testing.expectEqual(@as(usize, 2), history.current_index_get());
}
