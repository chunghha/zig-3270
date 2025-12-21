const std = @import("std");

/// Caches field lookups to optimize O(n) searches to O(1) for repeated access patterns
/// Typical usage: tab navigation, home operations, character insertion
pub const FieldCache = struct {
    const Self = @This();

    /// Cached field lookup result
    cached_address: ?u16 = null,
    cached_field_index: ?usize = null,
    cache_hits: usize = 0,
    cache_misses: usize = 0,

    pub fn init() Self {
        return Self{};
    }

    /// Try to find field at address, using cache if possible
    /// Field index must be provided via callback to check if still valid
    pub fn findField(
        self: *Self,
        address: u16,
        fields_len: usize,
        checkField: fn (usize, u16) bool,
    ) ?usize {
        // Check cache hit
        if (self.cached_address) |cached_addr| {
            if (cached_addr == address) {
                if (self.cached_field_index) |idx| {
                    if (idx < fields_len and checkField(idx, address)) {
                        self.cache_hits += 1;
                        return idx;
                    }
                }
            }
        }

        // Cache miss - search would happen in caller
        self.cache_misses += 1;
        return null;
    }

    /// Update cache with found field
    pub fn updateCache(self: *Self, address: u16, field_index: usize) void {
        self.cached_address = address;
        self.cached_field_index = field_index;
    }

    /// Invalidate cache (e.g., when fields change)
    pub fn invalidate(self: *Self) void {
        self.cached_address = null;
        self.cached_field_index = null;
    }

    /// Get cache statistics
    pub fn getStats(self: *const Self) struct { hits: usize, misses: usize, hit_rate: f64 } {
        const total = self.cache_hits + self.cache_misses;
        const hit_rate = if (total > 0)
            @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(total)) * 100.0
        else
            0.0;

        return .{ .hits = self.cache_hits, .misses = self.cache_misses, .hit_rate = hit_rate };
    }

    /// Print cache statistics
    pub fn printStats(self: *const Self) void {
        const stats = self.getStats();
        std.debug.print(
            "Field Cache: {} hits, {} misses, {d:.1}% hit rate\n",
            .{ stats.hits, stats.misses, stats.hit_rate },
        );
    }
};

/// Field lookup result with caching support
pub const CachedFieldLookup = struct {
    const Self = @This();

    cache: FieldCache,

    pub fn init() Self {
        return Self{
            .cache = FieldCache.init(),
        };
    }

    /// Find field at address with caching
    pub fn find(
        self: *Self,
        address: u16,
        fields: []const struct { contains: fn (u16) bool },
    ) ?usize {
        // Try cache
        if (self.cache.findField(address, fields.len, struct {
            const f = fields;
            pub fn check(idx: usize, addr: u16) bool {
                return f[idx].contains(addr);
            }
        }.check)) |idx| {
            return idx;
        }

        // Search and cache
        for (0..fields.len) |i| {
            if (fields[i].contains(address)) {
                self.cache.updateCache(address, i);
                return i;
            }
        }

        return null;
    }

    /// Invalidate cache when fields are modified
    pub fn invalidateCache(self: *Self) void {
        self.cache.invalidate();
    }
};

test "field cache: basic hit and miss" {
    var cache = FieldCache.init();

    // First lookup: miss
    const result1 = cache.findField(100, 5, struct {
        pub fn check(idx: usize, addr: u16) bool {
            _ = idx;
            _ = addr;
            return false;
        }
    }.check);
    try std.testing.expectEqual(@as(?usize, null), result1);
    try std.testing.expectEqual(@as(usize, 0), cache.cache_hits);
    try std.testing.expectEqual(@as(usize, 1), cache.cache_misses);

    // Cache the result
    cache.updateCache(100, 2);

    // Second lookup: hit
    const result2 = cache.findField(100, 5, struct {
        pub fn check(idx: usize, addr: u16) bool {
            _ = idx;
            _ = addr;
            return true;
        }
    }.check);
    try std.testing.expectEqual(@as(?usize, 2), result2);
    try std.testing.expectEqual(@as(usize, 1), cache.cache_hits);
}

test "field cache: invalidation" {
    var cache = FieldCache.init();

    cache.updateCache(100, 2);
    try std.testing.expectNotEqual(@as(?u16, null), cache.cached_address);

    cache.invalidate();
    try std.testing.expectEqual(@as(?u16, null), cache.cached_address);
    try std.testing.expectEqual(@as(?usize, null), cache.cached_field_index);
}

test "field cache: statistics" {
    var cache = FieldCache.init();

    cache.cache_hits = 9;
    cache.cache_misses = 1;

    const stats = cache.getStats();
    try std.testing.expectEqual(@as(usize, 9), stats.hits);
    try std.testing.expectEqual(@as(usize, 1), stats.misses);
    try std.testing.expect(stats.hit_rate > 89.0 and stats.hit_rate < 91.0);
}

test "field cache: multiple addresses" {
    var cache = FieldCache.init();

    // Cache first address
    cache.updateCache(100, 1);
    try std.testing.expectEqual(@as(?u16, 100), cache.cached_address);

    // Cache different address - overwrites
    cache.updateCache(200, 3);
    try std.testing.expectEqual(@as(?u16, 200), cache.cached_address);
    try std.testing.expectEqual(@as(?usize, 3), cache.cached_field_index);
}
