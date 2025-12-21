const std = @import("std");

/// Wraps an allocator to track allocation count and peak memory usage
pub const AllocationTracker = struct {
    allocations: usize = 0,
    deallocations: usize = 0,
    peak_bytes: usize = 0,
    current_bytes: usize = 0,
    parent_allocator: std.mem.Allocator,

    pub fn init(parent: std.mem.Allocator) AllocationTracker {
        return AllocationTracker{
            .parent_allocator = parent,
        };
    }

    pub fn allocator(self: *AllocationTracker) std.mem.Allocator {
        return std.mem.Allocator{
            .ptr = self,
            .vtable = &.{
                .alloc = &allocFn,
                .resize = &resizeFn,
                .free = &freeFn,
            },
        };
    }

    fn allocFn(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        var self: *AllocationTracker = @ptrCast(@alignCast(ctx));
        if (self.parent_allocator.rawAlloc(len, ptr_align, ret_addr)) |ptr| {
            self.allocations += 1;
            self.current_bytes += len;
            if (self.current_bytes > self.peak_bytes) {
                self.peak_bytes = self.current_bytes;
            }
            return ptr;
        }
        return null;
    }

    fn resizeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        var self: *AllocationTracker = @ptrCast(@alignCast(ctx));
        if (self.parent_allocator.rawResize(buf, buf_align, new_len, ret_addr)) {
            if (new_len > buf.len) {
                self.current_bytes += (new_len - buf.len);
            } else {
                self.current_bytes -= (buf.len - new_len);
            }
            if (self.current_bytes > self.peak_bytes) {
                self.peak_bytes = self.current_bytes;
            }
            return true;
        }
        return false;
    }

    fn freeFn(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        var self: *AllocationTracker = @ptrCast(@alignCast(ctx));
        self.parent_allocator.rawFree(buf, buf_align, ret_addr);
        self.deallocations += 1;
        self.current_bytes -= buf.len;
    }

    pub fn report(self: *const AllocationTracker) void {
        std.debug.print(
            "Allocations: {}, Deallocations: {}, Net: {}, Peak: {} bytes\n",
            .{ self.allocations, self.deallocations, self.allocations - self.deallocations, self.peak_bytes },
        );
    }
};

test "allocation tracker basics" {
    var tracker = AllocationTracker.init(std.testing.allocator);
    var tracked_allocator = tracker.allocator();

    const buf1 = try tracked_allocator.alloc(u8, 1024);
    defer tracked_allocator.free(buf1);

    try std.testing.expectEqual(@as(usize, 1), tracker.allocations);
    try std.testing.expectEqual(@as(usize, 1024), tracker.peak_bytes);
}
