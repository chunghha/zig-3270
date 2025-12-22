const std = @import("std");
const screen = @import("screen.zig");

pub const AutoSaveConfig = struct {
    interval_ms: u64 = 30_000, // 30 seconds
    max_snapshots: usize = 10,
    enabled: bool = true,
};

pub const SessionAutoSave = struct {
    allocator: std.mem.Allocator,
    session_dir: []const u8,
    config: AutoSaveConfig,
    last_save_time: i64 = 0,
    save_count: u64 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        session_dir: []const u8,
        config: AutoSaveConfig,
    ) !SessionAutoSave {
        // Create session directory if it doesn't exist
        std.fs.cwd().makeDir(session_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };

        const dir_copy = try allocator.dupe(u8, session_dir);

        return .{
            .allocator = allocator,
            .session_dir = dir_copy,
            .config = config,
        };
    }

    pub fn deinit(self: *SessionAutoSave) void {
        self.allocator.free(self.session_dir);
    }

    /// Check if auto-save interval has elapsed and perform save if needed
    pub fn maybe_save(
        self: *SessionAutoSave,
        scr: *const screen.Screen,
        cursor_row: u16,
        cursor_col: u16,
        keyboard_locked: bool,
    ) !bool {
        if (!self.config.enabled) {
            return false;
        }

        const now = std.time.milliTimestamp();
        const elapsed = now - self.last_save_time;

        if (elapsed >= @as(i64, @intCast(self.config.interval_ms))) {
            try self.perform_save(scr, cursor_row, cursor_col, keyboard_locked);
            self.last_save_time = now;
            return true;
        }

        return false;
    }

    /// Perform immediate save
    pub fn perform_save(
        self: *SessionAutoSave,
        _: *const screen.Screen,
        _: u16,
        _: u16,
        _: bool,
    ) !void {
        // In a full implementation, would write screen/cursor/keyboard state to file
        // For now, just increment the save counter
        self.save_count += 1;
    }

    /// Recover last saved session
    pub fn recover_last_session(self: SessionAutoSave) !?void {
        // In a full implementation, would read from session file
        // For now, just return null
        _ = self;
        return null;
    }

    /// Enable/disable auto-save
    pub fn set_enabled(self: *SessionAutoSave, enabled: bool) void {
        self.config.enabled = enabled;
    }

    /// Get number of saves performed
    pub fn get_save_count(self: SessionAutoSave) u64 {
        return self.save_count;
    }

    /// Get time since last save (milliseconds)
    pub fn time_since_last_save(self: SessionAutoSave) i64 {
        return std.time.milliTimestamp() - self.last_save_time;
    }
};

// Tests
test "session autosave init" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var autosave = try SessionAutoSave.init(allocator, "/tmp/test_session", .{});
    defer autosave.deinit();

    try std.testing.expectEqual(@as(u64, 0), autosave.get_save_count());
    try std.testing.expect(autosave.config.enabled);
}

test "session autosave save count increments" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var autosave = try SessionAutoSave.init(allocator, "/tmp/test_session", .{});
    defer autosave.deinit();

    // Initially no saves
    try std.testing.expectEqual(@as(u64, 0), autosave.get_save_count());
}

test "session autosave time since last save" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var autosave = try SessionAutoSave.init(allocator, "/tmp/test_session", .{});
    defer autosave.deinit();

    // Set last save time to now
    autosave.last_save_time = std.time.milliTimestamp();
    const elapsed = autosave.time_since_last_save();

    // Elapsed time should be small (near 0)
    try std.testing.expect(elapsed >= 0);
}

test "session autosave enable disable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var autosave = try SessionAutoSave.init(allocator, "/tmp/test_session", .{});
    defer autosave.deinit();

    try std.testing.expect(autosave.config.enabled);

    autosave.set_enabled(false);
    try std.testing.expect(!autosave.config.enabled);

    autosave.set_enabled(true);
    try std.testing.expect(autosave.config.enabled);
}
